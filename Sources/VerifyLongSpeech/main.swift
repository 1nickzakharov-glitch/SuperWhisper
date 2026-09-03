import Foundation
import AVFoundation
import WhisperKit

print("🎙️ === Running Comprehensive Multi-Paragraph Russian Transcription Test ===")
let modelPath = "/Users/nikitazaharov/Documents/huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB"
let audioPath = "/tmp/long_speech_16k.wav"

Task {
    do {
        let wk = try await WhisperKit(modelFolder: modelPath, verbose: false)
        let audioURL = URL(fileURLWithPath: audioPath)
        let audioFile = try AVAudioFile(forReading: audioURL)
        let frameCount = UInt32(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
            fatalError("Buffer allocation failed")
        }
        try audioFile.read(into: buffer)
        
        guard let data = buffer.floatChannelData?[0] else { fatalError("No channel data") }
        let samples = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
        let audioDuration = Double(samples.count) / 16000.0
        print("🔊 Audio loaded: \(samples.count) samples (\(String(format: "%.2f", audioDuration))s)")
        
        let start = Date()
        let options = DecodingOptions(task: .transcribe, language: "ru", temperature: 0.0)
        let results = try await wk.transcribe(audioArray: samples, decodeOptions: options)
        let elapsed = Date().timeIntervalSince(start)
        
        print("⚡ Transcribed in \(String(format: "%.2f", elapsed))s (Real-time factor: \(String(format: "%.2f", elapsed / audioDuration))x)")
        
        let fullText = results.map { $0.text }.joined(separator: " ")
        print("\n📜 Full Transcribed Text:\n\(fullText)\n")
        
        print("📊 Segments count: \(results.flatMap { $0.segments }.count)")
        for res in results {
            for seg in res.segments {
                print(String(format: "[%05.2f -> %05.2f]: %@", seg.start, seg.end, seg.text))
            }
        }
        
        let textLower = fullText.lowercased()
        let hasFirst = textLower.contains("первая часть") || textLower.contains("старом приложении")
        let hasSecond = textLower.contains("втором абзаце") || textLower.contains("свифт") || textLower.contains("силикон")
        let hasThird = textLower.contains("третьем абзаце") || textLower.contains("гладко") || textLower.contains("вставке")
        
        print("\n🔎 Verification of Paragraphs:")
        print("  - Paragraph 1 (Beginning): \(hasFirst ? "✅ PASSED" : "❌ FAILED")")
        print("  - Paragraph 2 (Middle):    \(hasSecond ? "✅ PASSED" : "❌ FAILED")")
        print("  - Paragraph 3 (Ending):    \(hasThird ? "✅ PASSED" : "❌ FAILED")")
        
        if hasFirst && hasSecond && hasThird {
            print("\n🎉 VERIFICATION PASSED: No middle drop, complete speech transcribed accurately!")
            exit(0)
        } else {
            print("\n❌ VERIFICATION FAILED: Missing text segments!")
            exit(1)
        }
    } catch {
        print("❌ Error: \(error)")
        exit(1)
    }
}

RunLoop.main.run()
