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
        
        let start = Date()
        let audioDuration = Double(audioSamples.count) / 16000.0
        
        // Use VAD chunking only for audio > 30 seconds
        let chunking: ChunkingStrategy? = audioDuration > 30.0 ? .vad : nil
        
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            detectLanguage: language == nil,
            chunkingStrategy: chunking
        )
        
        let results = try await whisperKit.transcribe(audioArray: audioSamples, decodeOptions: options)
        let duration = Date().timeIntervalSince(start)
        
        let rawJoined = results.map { $0.text }.joined(separator: " ")
        let noTokens = rawJoined
            .replacingOccurrences(of: "<\\|.*?\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let formatted = TextPunctuationFormatter.format(noTokens)
        print("🎙️ [TranscriptionEngine] Transcribed \(String(format: "%.2f", audioDuration))s in \(String(format: "%.2f", duration))s: \(formatted)")
        return formatted
    }
}
