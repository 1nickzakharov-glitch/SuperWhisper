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
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelFolder = appSupport.appendingPathComponent("SuperWhisper/Models/\(modelName)")
        
        if fileManager.fileExists(atPath: modelFolder.path) {
            print("📁 [TranscriptionEngine] Found local model at: \(modelFolder.path)")
            return modelFolder
        }
        
        print("📥 [TranscriptionEngine] Downloading \(modelName)...")
        let downloadedFolder = try await WhisperKit.download(variant: modelName)
        return downloadedFolder
    }
    
    public func initialize() async throws {
        if whisperKit != nil { return }
        
        let modelFolder = try await resolveModelFolder()
        print("🚀 [TranscriptionEngine] Loading WhisperKit with .cpuAndGPU from \(modelFolder.path)...")
        
        let compute = ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndGPU,
            textDecoderCompute: .cpuAndGPU,
            prefillCompute: .cpuAndGPU
        )
        
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            computeOptions: compute,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true
        )
        
        let wk = try await WhisperKit(config)
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
        
        // 1. Trim trailing silence from audio buffer to prevent decoder hallucinations
        let trimmedSamples = trimTrailingSilence(audioSamples)
        guard !trimmedSamples.isEmpty else { return "" }
        
        let start = Date()
        let audioDuration = Double(trimmedSamples.count) / 16000.0
        
        // VAD chunking only for speech over 30s
        let chunking: ChunkingStrategy? = audioDuration > 30.0 ? .vad : nil
        
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            detectLanguage: language == nil,
            chunkingStrategy: chunking
        )
        
        let results = try await whisperKit.transcribe(audioArray: trimmedSamples, decodeOptions: options)
        let duration = Date().timeIntervalSince(start)
        
        // 2. Filter segments: if Whisper's own VAD determined a segment is silence (>0.75 no-speech probability),
        // discard only that silent segment without touching any spoken words.
        var validTextParts: [String] = []
        for res in results {
            if res.segments.isEmpty {
                let clean = res.text.replacingOccurrences(of: "<\\|.*?\\|>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { validTextParts.append(clean) }
            } else {
                for seg in res.segments {
                    if seg.noSpeechProb < 0.75 {
                        let clean = seg.text.replacingOccurrences(of: "<\\|.*?\\|>", with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty { validTextParts.append(clean) }
                    }
                }
            }
        }
        
        let rawJoined = validTextParts.joined(separator: " ")
        let formatted = TextPunctuationFormatter.format(rawJoined)
        print("🎙️ [TranscriptionEngine] Transcribed \(String(format: "%.2f", audioDuration))s in \(String(format: "%.2f", duration))s: \(formatted)")
        return formatted
    }
    
    private func trimTrailingSilence(_ samples: [Float]) -> [Float] {
        guard samples.count > 1600 else { return samples } // Keep short audio
        
        let windowSize = 800 // 50ms at 16kHz
        var endIndex = samples.count
        
        // Search backwards from end for speech energy (RMS > 0.005)
        while endIndex > windowSize {
            let start = endIndex - windowSize
            var sumSquares: Float = 0.0
            for i in start..<endIndex {
                sumSquares += samples[i] * samples[i]
            }
            let rms = sqrt(sumSquares / Float(windowSize))
            if rms > 0.006 {
                // Keep 300ms buffer after last sound so endings aren't clipped
                let paddedEnd = min(samples.count, endIndex + 4800)
                return Array(samples[0..<paddedEnd])
            }
            endIndex -= windowSize
        }
        
        return samples
    }
}
