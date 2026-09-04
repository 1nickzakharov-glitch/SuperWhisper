import Foundation
@preconcurrency import AVFoundation
import Accelerate

private final class FFTAnalyzer: @unchecked Sendable {
    private let fftSize = 1024
    private var window: [Float]
    private var fft: vDSP.FFT<DSPSplitComplex>?
    
    init() {
        var w = [Float](repeating: 0.0, count: 1024)
        vDSP_hann_window(&w, vDSP_Length(1024), Int32(vDSP_HANN_NORM))
        self.window = w
        self.fft = vDSP.FFT(log2n: vDSP_Length(10), radix: .radix2, ofType: DSPSplitComplex.self)
    }
    
    func computeBands(samples: [Float], sampleRate: Double) -> [Float] {
        guard samples.count >= fftSize, let fft = self.fft else {
            return Array(repeating: 0.04, count: 9)
        }
        
        var windowed = [Float](repeating: 0.0, count: fftSize)
        vDSP_vmul(Array(samples.prefix(fftSize)), 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
        
        var real = [Float](repeating: 0.0, count: fftSize / 2)
        var imag = [Float](repeating: 0.0, count: fftSize / 2)
        var resultBands = [Float](repeating: 0.04, count: 9)
        
        real.withUnsafeMutableBufferPointer { rPtr in
            imag.withUnsafeMutableBufferPointer { iPtr in
                var split = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { wPtr in
                    wPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { cPtr in
                        vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                fft.forward(input: split, output: &split)
                
                var mags = [Float](repeating: 0.0, count: fftSize / 2)
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(fftSize / 2))
                
                let binHz = sampleRate / Double(fftSize)
                // 9 balanced bands covering the human speech range with equalized perception
                let edges: [(Double, Double)] = [
                    (100, 220), (220, 380), (380, 600), (600, 950),
                    (950, 1500), (1500, 2300), (2300, 3400), (3400, 4800), (4800, 6500)
                ]
                
                for (i, edge) in edges.enumerated() {
                    let b0 = max(1, Int(edge.0 / binHz))
                    let b1 = min(fftSize / 2 - 1, Int(edge.1 / binHz))
                    if b1 >= b0 {
                        var sum: Float = 0.0
                        for b in b0...b1 { sum += mags[b] }
                        let avg = sum / Float(b1 - b0 + 1)
                        // Frequency tilt gain: boosts higher harmonics proportionally
                        let tiltGain: Float = 0.14 + Float(i) * 0.05
                        resultBands[i] = min(max(sqrt(avg * tiltGain), 0.04), 1.0)
                    }
                }
            }
        }
        
        return resultBands
    }
}

private final class AudioEngineController: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var hasInstalledTap = false
    private let bufferLock = NSLock()
    private var recordedMonoSamples: [Float] = []
    private var inputSampleRate: Double = 48000.0
    private let fftAnalyzer = FFTAnalyzer()
    
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
    
    func startMonitoring(onLevelUpdate: @escaping @Sendable (Float, [Float]) -> Void) throws {
        stop()
        
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw NSError(domain: "AudioCaptureService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Неверный формат микрофона"])
        }
        self.inputSampleRate = format.sampleRate
        let sr = format.sampleRate
        let analyzer = self.fftAnalyzer
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable (buffer, time) in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            if frameLength == 0 { return }
            
            var rms: Float = 0.0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
            let level = min(max(sqrt(rms * 28.0), 0.04), 1.0)
            
            let rawSamples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
            let bandLevels = analyzer.computeBands(samples: rawSamples, sampleRate: sr)
            
            onLevelUpdate(level, bandLevels)
        }
        
        hasInstalledTap = true
        engine.prepare()
        try engine.start()
    }
    
    func startRecording(onLevelUpdate: @escaping @Sendable (Float, [Float]) -> Void) throws {
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
        let sr = format.sampleRate
        let analyzer = self.fftAnalyzer
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
            let level = currentlyPaused ? 0.02 : min(max(sqrt(rms * 28.0), 0.04), 1.0)
            
            let rawSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            let bandLevels: [Float]
            if currentlyPaused {
                bandLevels = Array(repeating: 0.04, count: 9)
            } else {
                bandLevels = analyzer.computeBands(samples: rawSamples, sampleRate: sr)
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
    
    public func stopRecordingAsync() async -> [Float] {
        guard isRecording else { return [] }
        
        self.isRecording = false
        self.isPaused = false
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
    
    // Smooth symmetrical attack & decay: eliminates micro-jitter while keeping speech response vivid
    private func updateLevels(level: Float, bands: [Float]) {
        self.rmsLevel = self.rmsLevel * 0.70 + level * 0.30
        for i in 0..<min(bands.count, self.audioLevels.count) {
            let target = bands[i]
            if target > self.audioLevels[i] {
                // Smooth rise
                self.audioLevels[i] = self.audioLevels[i] * 0.70 + target * 0.30
            } else {
                // Smooth decay
                self.audioLevels[i] = self.audioLevels[i] * 0.80 + target * 0.20
            }
        }
    }
}
