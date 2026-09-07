import Foundation
import AppKit

public enum HistoryStatus: Codable, Sendable, Equatable {
    case processing
    case completed
    case failed(reason: String)
    
    private enum CodingKeys: String, CodingKey {
        case type, reason
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "processing":
            self = .processing
        case "completed":
            self = .completed
        case "failed":
            let reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "Ошибка распознавания"
            self = .failed(reason: reason)
        default:
            self = .completed
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .processing:
            try container.encode("processing", forKey: .type)
        case .completed:
            try container.encode("completed", forKey: .type)
        case .failed(let reason):
            try container.encode("failed", forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }
}

public struct HistoryItem: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let duration: TimeInterval
    public var text: String
    public var status: HistoryStatus
    public var audioFileName: String?
    
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: createdAt)
    }
    
    public var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}

@MainActor
public final class HistoryService: ObservableObject {
    public static let shared = HistoryService()
    
    @Published public private(set) var items: [HistoryItem] = []
    
    private let fileManager = FileManager.default
    private let retentionSeconds: TimeInterval = 24 * 60 * 60 // 24 hours
    
    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SuperWhisper/History", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private var audioCacheDirectory: URL {
        let dir = storageDirectory.appendingPathComponent("AudioCache", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private var historyFileURL: URL {
        storageDirectory.appendingPathComponent("history.json")
    }
    
    private init() {
        loadHistory()
        purgeOldEntries()
    }
    
    public func addEntry(id: UUID = UUID(), duration: TimeInterval, audioSamples: [Float]) -> HistoryItem {
        let audioFileName = "\(id.uuidString).wav"
        let audioURL = audioCacheDirectory.appendingPathComponent(audioFileName)
        
        // Save audio to disk so user never loses their recording
        Task.detached(priority: .utility) {
            let wavData = AudioWAVEncoder.encodeToWAV(samples: audioSamples, sampleRate: 16000)
            try? wavData.write(to: audioURL, options: .atomic)
        }
        
        let item = HistoryItem(
            id: id,
            createdAt: Date(),
            duration: duration,
            text: "",
            status: .processing,
            audioFileName: audioFileName
        )
        
        items.insert(item, at: 0)
        saveHistory()
        return item
    }
    
    public func updateEntry(id: UUID, text: String, status: HistoryStatus) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].text = text
        items[idx].status = status
        saveHistory()
    }
    
    public func deleteEntry(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[idx]
        if let audioFileName = item.audioFileName {
            let audioURL = audioCacheDirectory.appendingPathComponent(audioFileName)
            try? fileManager.removeItem(at: audioURL)
        }
        items.remove(at: idx)
        saveHistory()
    }
    
    public func clearAll() {
        for item in items {
            if let audioFileName = item.audioFileName {
                let audioURL = audioCacheDirectory.appendingPathComponent(audioFileName)
                try? fileManager.removeItem(at: audioURL)
            }
        }
        items.removeAll()
        saveHistory()
    }
    
    public func copyToClipboard(item: HistoryItem) {
        guard !item.text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
    }
    
    public func loadAudioSamples(for item: HistoryItem) -> [Float]? {
        guard let audioFileName = item.audioFileName else { return nil }
        let audioURL = audioCacheDirectory.appendingPathComponent(audioFileName)
        guard fileManager.fileExists(atPath: audioURL.path) else { return nil }
        
        guard let data = try? Data(contentsOf: audioURL), data.count > 44 else { return nil }
        let pcmData = data.subdata(in: 44..<data.count)
        var samples = [Float](repeating: 0, count: pcmData.count / 2)
        pcmData.withUnsafeBytes { rawBuffer in
            let int16Ptr = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<samples.count {
                samples[i] = Float(int16Ptr[i]) / 32768.0
            }
        }
        return samples
    }
    
    public func purgeOldEntries() {
        let cutoff = Date().addingTimeInterval(-retentionSeconds)
        let expired = items.filter { $0.createdAt < cutoff }
        for item in expired {
            if let audioFileName = item.audioFileName {
                let audioURL = audioCacheDirectory.appendingPathComponent(audioFileName)
                try? fileManager.removeItem(at: audioURL)
            }
        }
        items.removeAll(where: { $0.createdAt < cutoff })
        saveHistory()
    }
    
    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: historyFileURL)
            let decoder = JSONDecoder()
            items = try decoder.decode([HistoryItem].self, from: data)
        } catch {
            print("⚠️ [HistoryService] Failed to load history: \(error.localizedDescription)")
        }
    }
    
    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(items)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            print("⚠️ [HistoryService] Failed to save history: \(error.localizedDescription)")
        }
    }
}
