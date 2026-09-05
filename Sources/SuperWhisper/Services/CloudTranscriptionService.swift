import Foundation

public final class CloudTranscriptionService: Sendable {
    public static let shared = CloudTranscriptionService()
    
    private init() {}
    
    public func transcribe(
        audioSamples: [Float],
        baseURL: String,
        apiKey: String,
        model: String,
        language: String?
    ) async throws -> String {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let endpointString: String
        if trimmedBase.hasSuffix("/audio/transcriptions") {
            endpointString = trimmedBase
        } else if trimmedBase.hasSuffix("/") {
            endpointString = "\(trimmedBase)audio/transcriptions"
        } else {
            endpointString = "\(trimmedBase)/audio/transcriptions"
        }
        
        guard let url = URL(string: endpointString) else {
            throw NSError(domain: "CloudTranscription", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid API Endpoint URL: \(trimmedBase)"])
        }
        
        let startEncode = Date()
        let wavData = AudioWAVEncoder.encodeToWAV(samples: audioSamples, sampleRate: 16000)
        let encodeDuration = Date().timeIntervalSince(startEncode)
        print("⚡️ [CloudTranscription] Audio encoded to WAV (\(wavData.count) bytes, \(String(format: "%.2f", Double(audioSamples.count)/16000.0))s) in \(String(format: "%.3f", encodeDuration))s")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0
        
        if !cleanKey.isEmpty {
            request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // 1. Model parameter
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(cleanModel.isEmpty ? "whisper-1" : cleanModel)\r\n".data(using: .utf8)!)
        
        // 2. Language parameter (if specified and not auto)
        if let lang = language, !lang.isEmpty, lang != "auto" {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(lang)\r\n".data(using: .utf8)!)
        }
        
        // 3. Audio file parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        
        // 4. Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        let startUpload = Date()
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let uploadDuration = Date().timeIntervalSince(startUpload)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "CloudTranscription", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            print("❌ [CloudTranscription] HTTP \(httpResponse.statusCode) from \(url.host ?? ""): \(errorText)")
            throw NSError(domain: "CloudTranscription", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(errorText)"])
        }
        
        struct TranscriptionResponse: Decodable {
            let text: String
        }
        
        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        print("✅ [CloudTranscription] Finished in \(String(format: "%.2f", uploadDuration))s. Text: \(text)")
        return text
    }
}
