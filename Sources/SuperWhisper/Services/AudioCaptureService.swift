import Foundation
@preconcurrency import AVFoundation
import Accelerate

private final class AudioEngineController: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var hasInstalledTap = false
    private let bufferLock = NSLock()
    private var recordedMonoSamples: [Float] = []
    private var inputSampleRate: Double = 48000.0
    
    private let pauseLock = NSLock()
    private var _isPaused = false
    public var isPaused: Bool {
        get {
            pauseLock.lock()
            defer { pauseLock.unlock() }
            return _isPaused
        }
        set {
            pauseLock.lock()
            _isPaused = newValue
            pauseLock.unlock()
        }
    }
    
    func startMonitoring(onLevelUpdate: @escaping @Sendable (Float) -> Void) throws {
        stop()
        
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "AudioCaptureService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Неверный формат микрофона"])
        }
        self.inputSampleRate = format.sampleRate
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable (buffer, time) in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            if frameLength == 0 { return }
            
            var rms: Float = 0.0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
            
            // Logarithmic decibel scaling: calibrated for Mac built-in microphone
            // Floor at -52 dB (cuts background room noise), span 34 dB (up to -18 dB for normal/loud speech)
            let db = 20.0 * log10(max(rms, 0.00002))
            let normalized = max(0.0, min(1.0, (db + 52.0) / 34.0))
            // Square root expansion gives responsive liftoff on gentle voice without clipping on loud voice
            let level = sqrt(normalized)
            
            onLevelUpdate(level)
        }
        
        hasInstalledTap = true
        engine.prepare()
        try engine.start()
    }
    
    func startRecording(onLevelUpdate: @escaping @Sendable (Float) -> Void) throws {
        stop()
        
        bufferLock.lock()
        recordedMonoSamples.removeAll(keepingCapacity: true)
        bufferLock.unlock()
        self.isPaused = false
        
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "AudioCaptureService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Неверный формат микрофона"])
        }
        self.inputSampleRate = format.sampleRate
        let chCount = Int(format.channelCount)
        
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable (buffer, time) in
            let currentlyPaused = self.isPaused
            let frameLength = Int(buffer.frameLength)
            if frameLength == 0 { return }
            guard let channelData = buffer.floatChannelData else { return }
            
            if !currentlyPaused {
                var monoChunk = [Float](repeating: 0.0, count: frameLength)
                if chCount == 1 {
                    _ = monoChunk.withUnsafeMutableBufferPointer { dstPtr in
                        memcpy(dstPtr.baseAddress!, channelData[0], frameLength * MemoryLayout<Float>.size)
                    }
                } else {
                    for i in 0..<frameLength {
                        var sum: Float = 0.0
                        for ch in 0..<chCount {
                            sum += channelData[ch][i]
                        }
                        monoChunk[i] = sum / Float(chCount)
                    }
                }
                
                self.bufferLock.lock()
                self.recordedMonoSamples.append(contentsOf: monoChunk)
                self.bufferLock.unlock()
            }
            
            var rms: Float = 0.0
            vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(frameLength))
            let db = 20.0 * log10(max(rms, 0.00002))
            let normalized = max(0.0, min(1.0, (db + 52.0) / 34.0))
            let level = currentlyPaused ? 0.0 : sqrt(normalized)
            
            onLevelUpdate(level)
        }
        
        hasInstalledTap = true
        engine.prepare()
        try engine.start()
    }
    
    func stop() {
        if hasInstalledTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        engine.stop()
    }
    
    func drainSamplesConvertedTo16k() -> [Float] {
        stop()
        
        bufferLock.lock()
        let rawSamples = recordedMonoSamples
        recordedMonoSamples.removeAll(keepingCapacity: true)
        bufferLock.unlock()
        
        guard !rawSamples.isEmpty else { return [] }
        
        let sr = self.inputSampleRate
        if abs(sr - 16000.0) < 1.0 {
            return rawSamples
        }
        
        guard let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sr, channels: 1, interleaved: false),
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return rawSamples
        }
        
        let frameCount = AVAudioFrameCount(rawSamples.count)
        guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            return rawSamples
        }
        srcBuffer.frameLength = frameCount
        memcpy(srcBuffer.floatChannelData![0], rawSamples, rawSamples.count * MemoryLayout<Float>.size)
        
        let targetCapacity = AVAudioFrameCount(Double(frameCount) * (16000.0 / sr) + 1024)
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else {
            return rawSamples
        }
        
        var err: NSError?
        final class SupplyState: @unchecked Sendable { var supplied = false }
        let state = SupplyState()
        
        converter.convert(to: dstBuffer, error: &err) { _, outStatus in
            if !state.supplied {
                state.supplied = true
                outStatus.pointee = .haveData
                return srcBuffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }
        
        if err == nil && dstBuffer.frameLength > 0, let data = dstBuffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: data, count: Int(dstBuffer.frameLength)))
        }
        
        return rawSamples
    }
}

@MainActor
public final class AudioCaptureService: ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var isPaused = false
    @Published public private(set) var isMonitoring = false
    @Published public private(set) var rmsLevel: Float = 0.0
    @Published public private(set) var audioLevels: [Float] = Array(repeating: 0.04, count: 9)
    
    private let controller = AudioEngineController()
    
    public init() {}
    
    public func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized {
            return true
        } else if status == .denied || status == .restricted {
            return false
        }
        
        if #available(macOS 14.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    public func startMonitoring() {
        guard !isRecording && !isMonitoring else { return }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        guard status == .authorized else { return }
        
        do {
            try controller.startMonitoring { [weak self] level in
                DispatchQueue.main.async {
                    self?.updateLevels(level: level)
                }
            }
            self.isMonitoring = true
        } catch {
            print("⚠️ [AudioCaptureService] Failed monitoring: \(error)")
        }
    }
    
    public func stopMonitoring() {
        guard isMonitoring else { return }
        controller.stop()
        self.isMonitoring = false
        self.rmsLevel = 0.0
        self.audioLevels = Array(repeating: 0.04, count: 9)
    }
    
    public func startRecording() throws {
        if isMonitoring {
            stopMonitoring()
        }
        guard !isRecording else { return }
        
        try controller.startRecording { [weak self] level in
            DispatchQueue.main.async {
                self?.updateLevels(level: level)
            }
        }
        
        self.isRecording = true
        self.isPaused = false
        self.rmsLevel = 0.0
        self.audioLevels = Array(repeating: 0.04, count: 9)
        print("🎙️ [AudioCaptureService] Recording started.")
    }
    
    public func togglePause() {
        guard isRecording else { return }
        self.isPaused.toggle()
        controller.isPaused = self.isPaused
        print("⏸️ [AudioCaptureService] Paused: \(isPaused)")
    }
    
    public func stopRecording() -> [Float] {
        guard isRecording else { return [] }
        
        let samples = controller.drainSamplesConvertedTo16k()
        self.isRecording = false
        self.isPaused = false
        self.rmsLevel = 0.0
        self.audioLevels = Array(repeating: 0.04, count: 9)
        print("🛑 [AudioCaptureService] Recording stopped. Output \(samples.count) samples (16kHz).")
        return samples
    }
    
    public func stopRecordingAsync() async -> [Float] {
        guard isRecording else { return [] }
        
        self.isRecording = false
        self.isPaused = false
        
        // Grace buffer (350ms): keep audio tap running for a third of a second
        // to flush hardware CoreAudio buffers and capture the natural acoustic tail
        // of the final spoken word without clipping.
        try? await Task.sleep(nanoseconds: 350_000_000)
        
        self.rmsLevel = 0.0
        self.audioLevels = Array(repeating: 0.04, count: 9)
        
        let ctrl = self.controller
        return await Task.detached(priority: .userInitiated) {
            let samples = ctrl.drainSamplesConvertedTo16k()
            print("🛑 [AudioCaptureService] Async drain finished: \(samples.count) samples (16kHz).")
            return samples
        }.value
    }
    
    public func cancelRecording() {
        guard isRecording else { return }
        _ = controller.drainSamplesConvertedTo16k()
        self.isRecording = false
        self.isPaused = false
        self.rmsLevel = 0.0
        self.audioLevels = Array(repeating: 0.04, count: 9)
        print("❌ [AudioCaptureService] Recording cancelled.")
    }
    
    // Smooth asymmetrical attack & decay with peak lingering:
    // - Snappy attack: lifts quickly on speech onset without abrupt jumping
    // - Fluid graceful decay: peaks float and glide down organically instead of collapsing
    private func updateLevels(level: Float) {
        if level > self.rmsLevel {
            // Responsive attack on speech syllables
            self.rmsLevel = self.rmsLevel * 0.30 + level * 0.70
        } else {
            // Fluid lingering decay: smooth natural glide down
            self.rmsLevel = self.rmsLevel * 0.86 + level * 0.14
        }
    }
}
