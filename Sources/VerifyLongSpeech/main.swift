import Foundation
import WhisperKit
import AVFoundation

@main
struct VerifyShort {
    static func main() async {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelFolder = appSupport.appendingPathComponent("SuperWhisper/Models/openai_whisper-large-v3-v20240930_626MB")
        
        let compute = ModelComputeOptions(melCompute: .cpuAndGPU, audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU, prefillCompute: .cpuAndGPU)
        let config = WhisperKitConfig(modelFolder: modelFolder.path, computeOptions: compute, verbose: false, prewarm: false, load: true)
        let wk = try! await WhisperKit(config)
        
        let audioURL = URL(fileURLWithPath: "/tmp/short_test_16k.wav")
        let audioFile = try! AVAudioFile(forReading: audioURL)
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: UInt32(audioFile.length))!
        try! audioFile.read(into: buffer)
        let data = buffer.floatChannelData![0]
        let samples = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
        print("Short audio samples count: \(samples.count) (\(Double(samples.count)/16000.0)s)")
        
        // Test with promptTokens
        let promptText = "Здравствуйте! Это пример русской речи: знаки препинания, запятые, точки, тире и вопросы всегда расставлены правильно."
        let tokens = wk.tokenizer?.encode(text: promptText)
        
        print("\n--- Test 1: With long prompt tokens ---")
        let opt1 = DecodingOptions(task: .transcribe, language: "ru", promptTokens: tokens)
        let res1 = try! await wk.transcribe(audioArray: samples, decodeOptions: opt1)
        print("Result 1 text: '\(res1.map { $0.text }.joined(separator: " "))'")
        
        print("\n--- Test 2: Without prompt tokens (clean) ---")
        let opt2 = DecodingOptions(task: .transcribe, language: "ru")
        let res2 = try! await wk.transcribe(audioArray: samples, decodeOptions: opt2)
        print("Result 2 text: '\(res2.map { $0.text }.joined(separator: " "))'")
        
        print("\n--- Test 3: With short natural prompt: 'Привет, как дела? Хорошо.' ---")
        let shortTokens = wk.tokenizer?.encode(text: "Привет, как дела? Хорошо.")
        let opt3 = DecodingOptions(task: .transcribe, language: "ru", promptTokens: shortTokens)
        let res3 = try! await wk.transcribe(audioArray: samples, decodeOptions: opt3)
        print("Result 3 text: '\(res3.map { $0.text }.joined(separator: " "))'")
    }
}
