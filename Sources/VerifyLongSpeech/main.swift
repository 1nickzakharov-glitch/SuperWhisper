import Foundation
import WhisperKit
import CoreML
import AVFoundation

@main
struct SpeedBench {
    static func main() async {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelFolder = appSupport.appendingPathComponent("SuperWhisper/Models/openai_whisper-large-v3-v20240930_626MB")
        
        // Load 20s of audio
        let audioURL = URL(fileURLWithPath: "/tmp/long_speech_16k.wav")
        let audioFile = try! AVAudioFile(forReading: audioURL)
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: 320000)! // 20s
        try! audioFile.read(into: buffer, frameCount: 320000)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        print("Benchmarking with 20.0s of audio samples (\(samples.count))...\n")
        
        // Test 1: .cpuAndGPU
        print("--- Test 1: .cpuAndGPU ---")
        let comp1 = ModelComputeOptions(melCompute: .cpuAndGPU, audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU, prefillCompute: .cpuAndGPU)
        let cfg1 = WhisperKitConfig(modelFolder: modelFolder.path, computeOptions: comp1, verbose: false)
        let t0_1 = Date()
        let wk1 = try! await WhisperKit(cfg1)
        print("Model load: \(String(format: "%.2f", Date().timeIntervalSince(t0_1)))s")
        let t1_1 = Date()
        let res1 = try! await wk1.transcribe(audioArray: samples, decodeOptions: DecodingOptions(task: .transcribe, language: "ru"))
        let dur1 = Date().timeIntervalSince(t1_1)
        print("Transcription time: \(String(format: "%.2f", dur1))s")
        
        // Test 2: .cpuAndNeuralEngine (ANE)
        print("\n--- Test 2: .cpuAndNeuralEngine (Apple Neural Engine) ---")
        let comp2 = ModelComputeOptions(melCompute: .cpuAndGPU, audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine, prefillCompute: .cpuOnly)
        let cfg2 = WhisperKitConfig(modelFolder: modelFolder.path, computeOptions: comp2, verbose: false)
        let t0_2 = Date()
        let wk2 = try! await WhisperKit(cfg2)
        print("Model load: \(String(format: "%.2f", Date().timeIntervalSince(t0_2)))s")
        let t1_2 = Date()
        let res2 = try! await wk2.transcribe(audioArray: samples, decodeOptions: DecodingOptions(task: .transcribe, language: "ru"))
        let dur2 = Date().timeIntervalSince(t1_2)
        print("Transcription time: \(String(format: "%.2f", dur2))s")
        
        exit(0)
    }
}
