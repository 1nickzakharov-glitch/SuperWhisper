import Foundation

public enum AudioWAVEncoder {
    /// Encodes normalized 16kHz mono Float32 audio samples into standard 16-bit PCM WAV data.
    public static func encodeToWAV(samples: [Float], sampleRate: Int = 16000) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let dataSize: UInt32 = UInt32(samples.count * 2)
        let chunkSize: UInt32 = 36 + dataSize
        
        var data = Data()
        data.reserveCapacity(Int(44 + dataSize))
        
        // 1. "RIFF" Header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        withUnsafeBytes(of: chunkSize.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        
        // 2. "fmt " Subchunk
        data.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
        withUnsafeBytes(of: UInt32(16).littleEndian) { data.append(contentsOf: $0) } // Subchunk1Size
        withUnsafeBytes(of: UInt16(1).littleEndian) { data.append(contentsOf: $0) }  // AudioFormat (PCM = 1)
        withUnsafeBytes(of: numChannels.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { data.append(contentsOf: $0) }
        
        // 3. "data" Subchunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        withUnsafeBytes(of: dataSize.littleEndian) { data.append(contentsOf: $0) }
        
        // 4. Audio PCM 16-bit Int samples (clamped)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * 32767.0)
            withUnsafeBytes(of: intSample.littleEndian) { data.append(contentsOf: $0) }
        }
        
        return data
    }
}
