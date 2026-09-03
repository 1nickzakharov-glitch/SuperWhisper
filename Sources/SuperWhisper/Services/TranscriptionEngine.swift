import Foundation
@preconcurrency import WhisperKit
import AVFoundation

public actor TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private var isWarmedUp = false
    private let modelName: String
    
    public init(modelName: String = "openai_whisper-large-v3-v20240930_626MB") {
        self.modelName = modelName
    }
    
    public func resolveModelFolder() async throws -> URL {
        let fileManager = FileManager.default
        
        // Search candidates
        let candidatePaths: [URL] = [
            // Standard Documents cache location
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml/\(modelName)"),
            // Application Support location
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("SuperWhisper/Models/\(modelName)"),
            // Caches location
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("huggingface/hub/models--argmaxinc--whisperkit-coreml/\(modelName)")
        ].compactMap { $0 }
        
        for url in candidatePaths {
            if fileManager.fileExists(atPath: url.path) {
                print("📁 [TranscriptionEngine] Found local model at: \(url.path)")
                return url
            }
        }
        
        // If not found locally, download using WhisperKit
        print("📥 [TranscriptionEngine] Model not found locally, downloading \(modelName)...")
        let downloadedFolder = try await WhisperKit.download(variant: modelName)
        return downloadedFolder
    }
    
    public func initialize() async throws {
        if whisperKit != nil { return }
        
        let modelFolder = try await resolveModelFolder()
        print("🚀 [TranscriptionEngine] Initializing WhisperKit from \(modelFolder.path)...")
        let wk = try await WhisperKit(modelFolder: modelFolder.path, verbose: false)
        self.whisperKit = wk
        self.isWarmedUp = true
        print("✅ [TranscriptionEngine] Initialized successfully! Model: \(wk.modelVariant)")
    }
    
    public func isReady() -> Bool {
        return whisperKit != nil
    }
    
    public func transcribe(audioSamples: [Float], language: String? = "ru") async throws -> String {
        guard let whisperKit else {
            throw NSError(domain: "SuperWhisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Движок распознавания не инициализирован"])
        }
        
        guard !audioSamples.isEmpty else {
            return ""
        }
        
        let start = Date()
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            detectLanguage: language == nil,
            chunkingStrategy: .vad
        )
        
        let results = try await whisperKit.transcribe(audioArray: audioSamples, decodeOptions: options)
        let duration = Date().timeIntervalSince(start)
        
        let fullText = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Clean special tokens if any leaked
        let cleaned = fullText
            .replacingOccurrences(of: "<\\|.*?\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("🎙️ [TranscriptionEngine] Transcribed \(audioSamples.count) samples in \(String(format: "%.2f", duration))s: \(cleaned)")
        return cleaned
    }
}
