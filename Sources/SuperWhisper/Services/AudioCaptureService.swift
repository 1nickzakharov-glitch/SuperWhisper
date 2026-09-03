import Foundation
@preconcurrency import AVFoundation
import Accelerate

private final class AudioEngineController: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var hasInstalledTap = false
    private let lock = NSLock()
    private var capturedBuffers: [AVAudioPCMBuffer] = []
    private var inputFormat: AVAudioFormat?
    public var isPaused = false
    
    func startMonitoring(onLevelUpdate: @escaping @Sendable (Float, [Float]) -> Void) throws {
        stop()
        
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "AudioCaptureService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Неверный формат микрофона"])
        }
        self.inputFormat = format
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable (buffer, time) in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            if frameLength == 0 { return }
            
            var rms: Float = 0.0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
            // Boosted logarithmic/sqrt response for natural speech sensitivity
            let level = min(max(sqrt(rms * 40.0), 0.04), 1.0)
            
            var bandLevels = [Float](repeating: 0.04, count: 9)
            let bandSize = frameLength / 9
            if bandSize > 0 {
                for i in 0..<9 {
                    var bRms: Float = 0.0
                    vDSP_rmsqv(channelData.advanced(by: i * bandSize), 1, &bRms, vDSP_Length(bandSize))
                    bandLevels[i] = min(max(sqrt(bRms * 50.0), 0.04), 1.0)
                }
            }
            
            onLevelUpdate(level, bandLevels)
        }
        
        hasInstalledTap = true
        engine.prepare()
        try engine.start()
    }
    
    func startRecording(onLevelUpdate: @escaping @Sendable (Float, [Float]) -> Void) throws {
        stop()
        
        lock.lock()
        capturedBuffers.removeAll(keepingCapacity: true)
        isPaused = false
        lock.unlock()
        
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "AudioCaptureService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Неверный формат микрофона"])
        }
        self.inputFormat = format
        
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable (buffer, time) in
            if !self.isPaused {
                if let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) {
                    copy.frameLength = buffer.frameLength
                    let chCount = Int(buffer.format.channelCount)
                    for ch in 0..<chCount {
                        if let src = buffer.floatChannelData?[ch], let dst = copy.floatChannelData?[ch] {
                            memcpy(dst, src, Int(buffer.frameLength) * MemoryLayout<Float>.size)
                        }
                    }
                    self.lock.lock()
                    self.capturedBuffers.append(copy)
                    self.lock.unlock()
                }
            }
            
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            if frameLength == 0 { return }
            
            var rms: Float = 0.0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
            // Boosted response: normal speech reaches 0.60..0.85
            let level = self.isPaused ? 0.02 : min(max(sqrt(rms * 40.0), 0.04), 1.0)
            
            var bandLevels = [Float](repeating: 0.04, count: 9)
            let bandSize = frameLength / 9
            if bandSize > 0 {
                for i in 0..<9 {
                    var bRms: Float = 0.0
                    vDSP_rmsqv(channelData.advanced(by: i * bandSize), 1, &bRms, vDSP_Length(bandSize))
                    bandLevels[i] = self.isPaused ? 0.04 : min(max(sqrt(bRms * 50.0), 0.04), 1.0)
                }
            }
            
            onLevelUpdate(level, bandLevels)
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
        
        lock.lock()
        let buffers = capturedBuffers
        capturedBuffers.removeAll(keepingCapacity: true)
        lock.unlock()
        
        guard let sourceFormat = inputFormat, !buffers.isEmpty else { return [] }
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false) else { return [] }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { return [] }
        
        final class SupplyState: @unchecked Sendable { var supplied = false }
        var outputSamples: [Float] = []
        
        for buf in buffers {
            let ratio = 16000.0 / sourceFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buf.frameLength) * ratio + 512)
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { continue }
            
            var err: NSError?
            let state = SupplyState()
            converter.convert(to: outBuf, error: &err) { _, outStatus in
                if !state.supplied {
                    state.supplied = true
                    outStatus.pointee = .haveData
                    return buf
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }
            
            if err == nil && outBuf.frameLength > 0, let data = outBuf.floatChannelData?[0] {
                let chunk = Array(UnsafeBufferPointer(start: data, count: Int(outBuf.frameLength)))
                outputSamples.append(contentsOf: chunk)
            }
        }
        
        return outputSamples
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
            try controller.startMonitoring { [weak self] level, bands in
                DispatchQueue.main.async {
                    self?.updateLevels(level: level, bands: bands)
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
        
        try controller.startRecording { [weak self] level, bands in
            DispatchQueue.main.async {
                self?.updateLevels(level: level, bands: bands)
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
    
    public func cancelRecording() {
        guard isRecording else { return }
        _ = controller.drainSamplesConvertedTo16k()
        self.isRecording = false
        self.isPaused = false
        self.rmsLevel = 0.0
        self.audioLevels = Array(repeating: 0.04, count: 9)
        print("❌ [AudioCaptureService] Recording cancelled.")
    }
    
    private func updateLevels(level: Float, bands: [Float]) {
        self.rmsLevel = self.rmsLevel * 0.20 + level * 0.80
        for i in 0..<min(bands.count, self.audioLevels.count) {
            self.audioLevels[i] = self.audioLevels[i] * 0.25 + bands[i] * 0.75
        }
    }
}
