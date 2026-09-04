import Foundation

public final class DeepInfraTranscriptionService: Sendable {
    public static let shared = DeepInfraTranscriptionService()
    
    private init() {}
    
    public func transcribe(
        audioSamples: [Float],
        apiKey: String,
        model: String = "openai/whisper-large-v3-turbo",
        language: String? = "ru"
    ) async throws -> String {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NSError(domain: "DeepInfra", code: 401, userInfo: [NSLocalizedDescriptionKey: "DeepInfra API ключ не указан"])
        }
        
        let startEncode = Date()
        let wavData = AudioWAVEncoder.encodeToWAV(samples: audioSamples, sampleRate: 16000)
        let encodeDuration = Date().timeIntervalSince(startEncode)
        print("⚡️ [DeepInfra] Audio encoded to WAV (\(wavData.count) bytes, \(String(format: "%.2f", Double(audioSamples.count)/16000.0))s) in \(String(format: "%.3f", encodeDuration))s")
        
        let url = URL(string: "https://api.deepinfra.com/v1/openai/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25.0
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // 1. model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)
        
        // 2. language parameter (if specified)
        if let lang = language, !lang.isEmpty, lang != "auto" {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(lang)\r\n".data(using: .utf8)!)
        }
        
        // 3. audio file parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        
        // 4. close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        let startUpload = Date()
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let uploadDuration = Date().timeIntervalSince(startUpload)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "DeepInfra", code: 0, userInfo: [NSLocalizedDescriptionKey: "Неверный ответ сервера"])
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            print("❌ [DeepInfra] HTTP \(httpResponse.statusCode): \(errorText)")
            throw NSError(domain: "DeepInfra", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Ошибка DeepInfra (\(httpResponse.statusCode)): \(errorText)"])
        }
        
        struct TranscriptionResponse: Decodable {
            let text: String
        }
        
        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        print("✅ [DeepInfra] Cloud transcription finished in \(String(format: "%.2f", uploadDuration))s. Text: \(text)")
        return text
    }
}
