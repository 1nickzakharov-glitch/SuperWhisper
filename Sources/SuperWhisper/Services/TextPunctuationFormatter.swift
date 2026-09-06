import Foundation

public enum TextPunctuationFormatter {
    public static func format(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        
        // Filter common Whisper YouTube/subtitles hallucinations on silence/trailing audio
        let hallucinationPatterns = [
            "(?i)(продолжение следует\\.{0,3})",
            "(?i)(субтитры сделал[^.!?]*[.!?,]*)",
            "(?i)(редактор субтитров[^.!?]*[.!?,]*)",
            "(?i)(перевод на русский[^.!?]*[.!?,]*)",
            "(?i)(спасибо за просмотр[^.!?]*[.!?,]*)",
            "(?i)(подписывайтесь на канал[^.!?]*[.!?,]*)",
            "(?i)(ставьте лайк[а-я]*[^.!?]*[.!?,]*)",
            "(?i)(до скорых встреч[^.!?]*[.!?,]*)",
            "(?i)(до скорой встречи[^.!?]*[.!?,]*)",
            "(?i)(to be continued\\.{0,3})",
            "(?i)(thank you for watching[^.!?]*[.!?,]*)",
            "(?i)(subtitles by[^.!?]*[.!?,]*)"
        ]
        for p in hallucinationPatterns {
            text = regexReplace(text, pattern: p, with: "")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        
        // Normalize ellipses and double dots that Whisper often inserts for speech pauses.
        // Dictation should look like clean prose, not subtitle fragments.
        text = regexReplace(text, pattern: "…+", with: ".")
        text = regexReplace(text, pattern: "\\.{2,}", with: ".")
        
        // Remove duplicate spaces
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        
        // Repeated interjections: "раз раз" -> "раз, раз"
        text = regexReplace(text, pattern: "(?i)\\b(раз)\\s+(раз)\\b", with: "$1, $2")
        text = regexReplace(text, pattern: "(?i)\\b(да)\\s+(да)\\b", with: "$1, $2")
        text = regexReplace(text, pattern: "(?i)\\b(нет)\\s+(нет)\\b", with: "$1, $2")
        
        // Commas before common Russian subordinate conjunctions
        let conjunctions = [
            "\\bа\\b", "\\bно\\b", "\\bчто\\b", "\\bчтобы\\b", "\\bчтоб\\b",
            "\\bесли\\b", "\\bкогда\\b", "\\bпотому что\\b", "\\bтак как\\b",
            "\\bто есть\\b", "\\bхотя\\b", "\\bкак будто бы\\b", "\\bкак будто\\b",
            "\\bбудто бы\\b", "\\bбудто\\b", "\\bвпрочем\\b"
        ]
        for conj in conjunctions {
            let pattern = "(?<=[а-яА-ЯёЁa-zA-Z0-9])\\s+(" + conj + ")"
            text = regexReplace(text, pattern: pattern, with: ", $1")
        }
        
        // Parenthetical phrases: set off by commas
        let parentheticals = [
            "\\bс одной стороны\\b", "\\bс другой стороны\\b",
            "\\bкстати\\b", "\\bконечно\\b", "\\bнаверное\\b", "\\bможет быть\\b",
            "\\bпо-моему\\b", "\\bв общем\\b", "\\bв целом\\b", "\\bво-первых\\b",
            "\\bво-вторых\\b", "\\bв-третьих\\b"
        ]
        for par in parentheticals {
            let pattern = "(?<=[а-яА-ЯёЁa-zA-Z0-9])\\s+(" + par + ")"
            text = regexReplace(text, pattern: pattern, with: ", $1,")
            text = text.replacingOccurrences(of: ", ,", with: ",")
            text = text.replacingOccurrences(of: ",,", with: ",")
        }
        
        // Conversational pauses: "смотри, а", "знаешь,"
        text = regexReplace(text, pattern: "(?<=[а-яА-ЯёЁa-zA-Z0-9])\\s+(смотри)\\s*,?\\s+(а\\b)", with: ", $1, $2")
        text = regexReplace(text, pattern: "(?<=[а-яА-ЯёЁa-zA-Z0-9])\\s+(знаешь)\\s*,?", with: ", $1,")
        
        // Ensure sentence boundary before capitalized words if period is missing (e.g. "стало Причём" -> "стало. Причём")
        text = regexReplace(text, pattern: "(?<=[а-яёa-z0-9])\\s+([А-ЯЁ][а-яё]+)", with: ". $1")
        
        // Clean spaces before punctuation
        let punctuationToFix = [",", ".", "!", "?", ":", ";"]
        for p in punctuationToFix {
            text = text.replacingOccurrences(of: " " + p, with: p)
        }
        
        // Clean double commas or comma before period
        text = text.replacingOccurrences(of: ",.", with: ".")
        text = text.replacingOccurrences(of: ", .", with: ".")
        text = text.replacingOccurrences(of: ",,", with: ",")
        
        // Capitalize first letter of entire text
        if let first = text.first {
            text = first.uppercased() + text.dropFirst()
        }
        
        // Capitalize letter after period, exclamation mark, or question mark followed by space
        let capPatterns = [
            ("(\\.\\s+)([a-zа-яё])", 2),
            ("(!\\s+)([a-zа-яё])", 2),
            ("(\\?\\s+)([a-zа-яё])", 2)
        ]
        for (pattern, _) in capPatterns {
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
    
    private static func regexReplace(_ input: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return input }
        let range = NSRange(location: 0, length: input.utf16.count)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: template)
    }
}
