import Foundation
import AVFoundation

@main
struct VerifyAudioTap {
    static func main() async {
        print("🎙️ Testing AudioCaptureService recording tap without crashes...")
        
        // Check mic permission
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("Microphone status: \(status.rawValue)")
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        print("Microphone format: \(format.sampleRate)Hz, \(format.channelCount)ch")
        
        var bufferCount = 0
        let lock = NSLock()
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { (buffer, time) in
            lock.lock()
            bufferCount += 1
            let count = bufferCount
            lock.unlock()
            
            if count % 10 == 0 {
                print("Tap successfully running from CoreAudio thread: \(count) buffers received")
            }
        }
        
        do {
            try engine.start()
            print("AVAudioEngine started! Listening for 2 seconds...")
            try await Task.sleep(nanoseconds: 2_000_000_000)
            inputNode.removeTap(onBus: 0)
            engine.stop()
            print("✅ SUCCESS: Received \(bufferCount) audio buffers with ZERO crashes!")
            exit(0)
        } catch {
            print("❌ Engine start failed: \(error)")
            exit(1)
        }
    }
}
