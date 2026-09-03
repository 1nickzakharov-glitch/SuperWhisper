import Foundation
import WhisperKit

@main
struct VerifyPrompt {
    static func main() async {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelFolder = appSupport.appendingPathComponent("SuperWhisper/Models/openai_whisper-large-v3-v20240930_626MB")
        
        let wk = try! await WhisperKit(modelFolder: modelFolder.path, verbose: false)
        if let tok = wk.tokenizer {
            let tokens = tok.encode(text: "Привет, это пример русской речи: знаки препинания, запятые, точки и заглавные буквы.")
            print("Successfully encoded prompt tokens: \(tokens.count) tokens! First 5: \(tokens.prefix(5))")
        } else {
            print("No tokenizer")
        }
        exit(0)
    }
}
