import Foundation
@preconcurrency import AVFoundation
import Accelerate

private final class RawAudioAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        copy.frameLength = buffer.frameLength
        let channelCount = Int(buffer.format.channelCount)
        for ch in 0..<channelCount {
            if let src = buffer.floatChannelData?[ch], let dst = copy.floatChannelData?[ch] {
                memcpy(dst, src, Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }
        buffers.append(copy)
    }
    
    func drain() -> [AVAudioPCMBuffer] {
        lock.lock()
        defer { lock.unlock() }
        let current = buffers
        buffers.removeAll(keepingCapacity: true)
        return current
    }
}

private final class ConverterState: @unchecked Sendable {
    var hasSupplied = false
}

@MainActor
public final class AudioCaptureService: ObservableObject {
    @Published public private(set) var isRecording = false
    @Published public private(set) var isMonitoring = false
    @Published public private(set) var rmsLevel: Float = 0.0
    @Published public private(set) var audioLevels: [Float] = Array(repeating: 0.05, count: 7)
    
    private let audioEngine = AVAudioEngine()
    private let accumulator = RawAudioAccumulator()
    private var hasInstalledTap = false
    private var inputFormat: AVAudioFormat?
    private static weak var activeService: AudioCaptureService?
    
    public init() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleConfigurationChange()
            }
        }
    }
    
    private func handleConfigurationChange() {
        print("🔄 [AudioCaptureService] Audio engine configuration changed.")
        if isRecording {
            _ = stopRecording()
        } else if isMonitoring {
            stopMonitoring()
        }
    }
    
    public func requestPermission() async -> Bool {
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
        
        AudioCaptureService.activeService = self
        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        
        if hasInstalledTap {
            inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { (buffer, _) in
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            if frameLength == 0 || channelCount == 0 { return }
            
            var monoMix = [Float](repeating: 0.0, count: frameLength)
            for ch in 0..<channelCount {
                let ptr = channelData[ch]
                vDSP_vadd(monoMix, 1, ptr, 1, &monoMix, 1, vDSP_Length(frameLength))
            }
            var scale = 1.0 / Float(channelCount)
            vDSP_vsmul(monoMix, 1, &scale, &monoMix, 1, vDSP_Length(frameLength))
            
            var rms: Float = 0.0
            vDSP_rmsqv(monoMix, 1, &rms, vDSP_Length(frameLength))
            let normalizedLevel = min(max(rms * 10.0, 0.0), 1.0)
            
            var bandLevels = [Float](repeating: 0.05, count: 7)
            let bandSize = frameLength / 7
            if bandSize > 0 {
                monoMix.withUnsafeBufferPointer { monoPtr in
                    guard let base = monoPtr.baseAddress else { return }
                    for i in 0..<7 {
                        var bandRms: Float = 0.0
                        vDSP_rmsqv(base.advanced(by: i * bandSize), 1, &bandRms, vDSP_Length(bandSize))
                        bandLevels[i] = min(max(bandRms * 14.0, 0.05), 1.0)
                    }
                }
            }
            
            DispatchQueue.main.async {
                AudioCaptureService.sharedAudioLevelUpdate(normalizedLevel: normalizedLevel, bands: bandLevels)
            }
        }
        
        hasInstalledTap = true
        do {
            audioEngine.prepare()
            try audioEngine.start()
            self.isMonitoring = true
            print("🎙️ [AudioCaptureService] Monitoring active (Settings mic test).")
        } catch {
            print("⚠️ [AudioCaptureService] Failed to start monitoring: \(error)")
        }
    }
    
    public func stopMonitoring() {
        guard isMonitoring else { return }
        
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        audioEngine.stop()
        self.isMonitoring = false
        self.rmsLevel = 0.0
        self.audioLevels = Array(repeating: 0.05, count: 7)
        AudioCaptureService.activeService = nil
        print("🛑 [AudioCaptureService] Monitoring stopped.")
    }
    
    public func startRecording() throws {
        if isMonitoring {
            stopMonitoring()
        }
        guard !isRecording else { return }
        
        _ = accumulator.drain()
        AudioCaptureService.activeService = self
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        
        guard format.sampleRate > 0 else {
            throw NSError(domain: "AudioCaptureService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Недопустимая частота дискретизации микрофона"])
        }
        
        self.inputFormat = format
        
        if hasInstalledTap {
            inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        
        let accumulator = self.accumulator
        let bufferSize: AVAudioFrameCount = 2048
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { (buffer, time) in
            accumulator.append(buffer)
            
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            if frameLength == 0 || channelCount == 0 { return }
            
            var monoMix = [Float](repeating: 0.0, count: frameLength)
            for ch in 0..<channelCount {
                let ptr = channelData[ch]
                vDSP_vadd(monoMix, 1, ptr, 1, &monoMix, 1, vDSP_Length(frameLength))
            }
            var scale = 1.0 / Float(channelCount)
            vDSP_vsmul(monoMix, 1, &scale, &monoMix, 1, vDSP_Length(frameLength))
            
            var rms: Float = 0.0
            vDSP_rmsqv(monoMix, 1, &rms, vDSP_Length(frameLength))
            let normalizedLevel = min(max(rms * 9.0, 0.0), 1.0)
            
            var bandLevels = [Float](repeating: 0.05, count: 7)
            let bandSize = frameLength / 7
            if bandSize > 0 {
                monoMix.withUnsafeBufferPointer { monoPtr in
                    guard let base = monoPtr.baseAddress else { return }
                    for i in 0..<7 {
                        var bandRms: Float = 0.0
                        vDSP_rmsqv(base.advanced(by: i * bandSize), 1, &bandRms, vDSP_Length(bandSize))
                        bandLevels[i] = min(max(bandRms * 12.0, 0.05), 1.0)
                    }
                }
            }
            
            DispatchQueue.main.async {
                AudioCaptureService.sharedAudioLevelUpdate(normalizedLevel: normalizedLevel, bands: bandLevels)
            }
        }
        
        hasInstalledTap = true
        audioEngine.prepare()
        try audioEngine.start()
        
        self.isRecording = true
        self.rmsLevel = 0.0
        self.audioLevels = Array(repeating: 0.05, count: 7)
        print("🎙️ [AudioCaptureService] Recording started (format: \(format.sampleRate)Hz, \(format.channelCount)ch).")
    }
    
    @MainActor
    private static func sharedAudioLevelUpdate(normalizedLevel: Float, bands: [Float]) {
        guard let service = activeService, (service.isRecording || service.isMonitoring) else { return }
        service.rmsLevel = service.rmsLevel * 0.25 + normalizedLevel * 0.75
        for i in 0..<7 {
            service.audioLevels[i] = service.audioLevels[i] * 0.35 + bands[i] * 0.65
        }
    }
    
    public func stopRecording() -> [Float] {
        guard isRecording else { return [] }
        
        AudioCaptureService.activeService = nil
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        audioEngine.stop()
        
        self.isRecording = false
        self.rmsLevel = 0.0
        self.audioLevels = Array(repeating: 0.05, count: 7)
        
        let rawBuffers = accumulator.drain()
        guard let format = self.inputFormat, !rawBuffers.isEmpty else {
            return []
        }
        
        let converted = convertBuffersTo16kHzMono(buffers: rawBuffers, sourceFormat: format)
        print("🛑 [AudioCaptureService] Recording stopped. Output 16kHz samples: \(converted.count) (\(String(format: "%.2f", Double(converted.count) / 16000.0))s).")
        return converted
    }
    
    private func convertBuffersTo16kHzMono(buffers: [AVAudioPCMBuffer], sourceFormat: AVAudioFormat) -> [Float] {
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false) else {
            return []
        }
        
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            print("⚠️ [AudioCaptureService] Failed to create AVAudioConverter, fallback to direct mix.")
            return []
        }
        
        var outputSamples: [Float] = []
        var bufferIndex = 0
        
        while bufferIndex < buffers.count {
            let currentInput = buffers[bufferIndex]
            let ratio = 16000.0 / sourceFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(currentInput.frameLength) * ratio + 1024)
            
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else { break }
            var error: NSError?
            let state = ConverterState()
            
            converter.convert(to: outBuffer, error: &error) { _, outStatus in
                if !state.hasSupplied {
                    state.hasSupplied = true
                    outStatus.pointee = .haveData
                    return currentInput
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }
            
            if error == nil && outBuffer.frameLength > 0, let data = outBuffer.floatChannelData?[0] {
                let frameCount = Int(outBuffer.frameLength)
                let chunk = Array(UnsafeBufferPointer(start: data, count: frameCount))
                outputSamples.append(contentsOf: chunk)
            }
            
            bufferIndex += 1
        }
        
        return outputSamples
    }
}
