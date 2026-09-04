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
            print("📦 [TranscriptionEngine] Found local model at: \(modelFolder.path)")
            return modelFolder
        }
        
        print("📦 [TranscriptionEngine] Downloading \(modelName)...")
        let downloadedFolder = try await WhisperKit.download(variant: modelName)
        return downloadedFolder
    }
    
    public func initialize() async throws {
        if whisperKit != nil { return }
        
        let modelFolder = try await resolveModelFolder()
        print("🧠 [TranscriptionEngine] Loading WhisperKit with .cpuAndGPU from \(modelFolder.path)...")
        
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
        guard !audioSamples.isEmpty else {
            return ""
        }
        
        // 1. Trim trailing silence from audio buffer to prevent decoder hallucinations
        let trimmedSamples = trimTrailingSilence(audioSamples)
        guard !trimmedSamples.isEmpty else { return "" }
        
        let audioDuration = Double(trimmedSamples.count) / 16000.0
        
        // Read preferences & network state on MainActor
        let (mode, isOnline, apiKey, deepInfraModel) = await MainActor.run {
            (
                Preferences.shared.transcriptionMode,
                NetworkMonitor.shared.isConnected,
                Preferences.shared.deepInfraApiKey,
                Preferences.shared.deepInfraModel
            )
        }
        
        let hasValidApiKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shouldTryCloud = (mode == .cloudOnly) || (mode == .hybrid && isOnline && hasValidApiKey)
        
        // Try Cloud Transcription via DeepInfra first if applicable
        if shouldTryCloud {
            do {
                await MainActor.run {
                    AppState.shared.processingStatusText = "Облако DeepInfra..."
                }
                
                let startCloud = Date()
                let cloudRaw = try await DeepInfraTranscriptionService.shared.transcribe(
                    audioSamples: trimmedSamples,
                    apiKey: apiKey,
                    model: deepInfraModel,
                    language: language
                )
                let cloudDuration = Date().timeIntervalSince(startCloud)
                
                let formatted = TextPunctuationFormatter.format(cloudRaw)
                print("⚡️ [TranscriptionEngine] Cloud transcribed \(String(format: "%.2f", audioDuration))s speech in \(String(format: "%.2f", cloudDuration))s: \(formatted)")
                return formatted
            } catch {
                print("⚠️ [TranscriptionEngine] Cloud transcription failed: \(error.localizedDescription)")
                if mode == .cloudOnly {
                    throw error
                }
                print("🔄 [TranscriptionEngine] Seamlessly falling back to local WhisperKit...")
            }
        }
        
        // Local On-Device Fallback (or Local-Only mode)
        await MainActor.run {
            AppState.shared.processingStatusText = "Локальный WhisperKit..."
        }
        
        return try await transcribeLocally(trimmedSamples: trimmedSamples, audioDuration: audioDuration, language: language)
    }
    
    private func transcribeLocally(trimmedSamples: [Float], audioDuration: Double, language: String?) async throws -> String {
        if whisperKit == nil {
            try await initialize()
        }
        
        guard let whisperKit else {
            throw NSError(domain: "SuperWhisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Локальный движок распознавания не инициализирован"])
        }
        
        let start = Date()
        
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
        
        // Filter segments: discard segments where Whisper's VAD determined noSpeechProb > 0.75
        var validTextParts: [String] = []
        for res in results {
            if res.segments.isEmpty {
                let clean = res.text.replacingOccurrences(of: "<\\|.*?\\|>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { validTextParts.append(clean) }
            } else {
                for seg in res.segments {
                    if seg.noSpeechProb < 0.88 {
                        let clean = seg.text.replacingOccurrences(of: "<\\|.*?\\|>", with: "", options: .regularExpression)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty { validTextParts.append(clean) }
                    }
                }
            }
        }
        
        let rawJoined = validTextParts.joined(separator: " ")
        let formatted = TextPunctuationFormatter.format(rawJoined)
        print("🎙️ [TranscriptionEngine] Locally transcribed \(String(format: "%.2f", audioDuration))s in \(String(format: "%.2f", duration))s: \(formatted)")
        return formatted
    }
    
    private func trimTrailingSilence(_ samples: [Float]) -> [Float] {
        // Keep full audio if shorter than 2.5 seconds (prevents cutting short voice clips)
        guard samples.count > 40000 else { return samples }
        
        let windowSize = 800 // 50ms at 16kHz
        var endIndex = samples.count
        
        // Search backwards from end for speech energy (true silence threshold: RMS > 0.0018)
        while endIndex > windowSize {
            let start = endIndex - windowSize
            var sumSquares: Float = 0.0
            for i in start..<endIndex {
                sumSquares += samples[i] * samples[i]
            }
            let rms = sqrt(sumSquares / Float(windowSize))
            if rms > 0.0018 {
                // Keep generous 1.0s (16000 samples) safety tail after the last sound
                // to guarantee soft consonants, trailing syllables, and reverberation are never clipped
                let paddedEnd = min(samples.count, endIndex + 16000)
                return Array(samples[0..<paddedEnd])
            }
            endIndex -= windowSize
        }
        
        return samples
    }
}
