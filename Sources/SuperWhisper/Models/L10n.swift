import Foundation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case russian = "ru"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        }
    }
}

public enum L10n {
    @MainActor
    public static func tr(_ en: String, _ ru: String) -> String {
        return Preferences.shared.appLanguage == .russian ? ru : en
    }
}
