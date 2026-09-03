import Foundation

public enum TextPunctuationFormatter {
    public static func format(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        
        // Remove duplicate spaces
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        
        // Clean spaces before punctuation
        let punctuationToFix = [",", ".", "!", "?", ":", ";"]
        for p in punctuationToFix {
            text = text.replacingOccurrences(of: " " + p, with: p)
        }
        
        // Capitalize first letter of entire text
        if let first = text.first {
            text = first.uppercased() + text.dropFirst()
        }
        
        // Capitalize letter after period, exclamation mark, or question mark
        let patterns = [
            ("(\\.\\s+)([a-zа-яё])", 2),
            ("(!\\s+)([a-zа-яё])", 2),
            ("(\\?\\s+)([a-zа-яё])", 2)
        ]
        
        for (pattern, _) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches.reversed() {
                    if let range = Range(match.range(at: 2), in: text) {
                        let lowerChar = String(text[range])
                        text.replaceSubrange(range, with: lowerChar.uppercased())
                    }
                }
            }
        }
        
        // Add trailing period if text does not end in punctuation
        let lastChar = text.last
        if lastChar != "." && lastChar != "!" && lastChar != "?" && lastChar != ":" && lastChar != ";" && lastChar != "…" {
            text.append(".")
        }
        
        return text
    }
}
