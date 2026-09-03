import Foundation
import WhisperKit
import CoreML
import AVFoundation

@main
struct VerifyComputeOptions {
    static func main() async {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelFolder = appSupport.appendingPathComponent("SuperWhisper/Models/openai_whisper-large-v3-v20240930_626MB")
        
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
        
        print("Initializing...")
        let wk = try! await WhisperKit(config)
        
        print("Testing transcription speed with .cpuAndGPU...")
        let audioURL = URL(fileURLWithPath: "/tmp/long_speech_16k.wav")
        let audioFile = try! AVAudioFile(forReading: audioURL)
        let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: UInt32(audioFile.length))!
        try! audioFile.read(into: buffer)
        let data = buffer.floatChannelData![0]
        let samples = Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
        
        let t0 = Date()
        let options = DecodingOptions(task: .transcribe, language: "ru", chunkingStrategy: .vad)
        let res = try! await wk.transcribe(audioArray: samples, decodeOptions: options)
        let elapsed = Date().timeIntervalSince(t0)
        print("Transcribed 40s audio in \(String(format: "%.2f", elapsed))s!")
        print("Result preview: \(res.map { $0.text }.joined(separator: " ").prefix(120))...")
        exit(0)
    }
}
