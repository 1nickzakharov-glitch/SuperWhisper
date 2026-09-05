import Foundation
import Carbon
import AppKit

public enum TranscriptionEngineMode: String, CaseIterable, Identifiable, Sendable {
    case hybrid = "hybrid"
    case cloudOnly = "cloud"
    case localOnly = "local"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .hybrid: return "Гибридный (Облако + офлайн-фоллбек)"
        case .cloudOnly: return "Только облако (DeepInfra)"
        case .localOnly: return "Только локально (WhisperKit)"
        }
    }
    
    public var shortDescription: String {
        switch self {
        case .hybrid: return "Если есть интернет — мгновенно через DeepInfra (1-2 сек). Без сети — автономно на Mac через WhisperKit."
        case .cloudOnly: return "Всегда через DeepInfra (Whisper Large-v3-Turbo на GPU). Максимальная скорость без нагрева Mac."
        case .localOnly: return "Всегда на локальном Apple Silicon чипе (CoreML). 100% приватность без обращения к сети."
        }
    }
}

public enum LocalWhisperModel: String, CaseIterable, Identifiable, Sendable {
    case largeV3Turbo = "openai_whisper-large-v3-v20240930_626MB"
    case small = "openai_whisper-small"
    case base = "openai_whisper-base"
    case tiny = "openai_whisper-tiny"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .largeV3Turbo: return "Large-v3-Turbo (598 МБ — макс. точность)"
        case .small: return "Small (460 МБ — сбалансированная)"
        case .base: return "Base (140 МБ — быстрая)"
        case .tiny: return "Tiny (75 МБ — ультра-лёгкая)"
        }
    }
    
    public var description: String {
        switch self {
        case .largeV3Turbo: return "Лучшая точность распознавания русского языка и сложной пунктуации."
        case .small: return "Отличный баланс скорости и качества для любых Mac."
        case .base: return "Быстрое выполнение, минимальное потребление оперативной памяти."
        case .tiny: return "Мгновенная инициализация, подходит для быстрых команд."
        }
    }
}

@MainActor
public final class Preferences: ObservableObject {
    public static let shared = Preferences()
    
    private let defaults = UserDefaults.standard
    
    // Default fallback from environment if provided; empty for clean public installs
    public static let defaultDeepInfraKey = ProcessInfo.processInfo.environment["DEEPINFRA_API_KEY"] ?? ""
    
    // Local offline Whisper model variant
    @Published public var localModel: LocalWhisperModel {
        didSet {
            defaults.set(localModel.rawValue, forKey: "localModel")
            NotificationCenter.default.post(name: .localModelDidChange, object: nil)
        }
    }
    
    // Transcription mode: hybrid, cloud, or local
    @Published public var transcriptionMode: TranscriptionEngineMode {
        didSet {
            defaults.set(transcriptionMode.rawValue, forKey: "transcriptionMode")
        }
    }
    
    @Published public var deepInfraApiKey: String {
        didSet {
            defaults.set(deepInfraApiKey, forKey: "deepInfraApiKey")
        }
    }
    
    @Published public var deepInfraModel: String {
        didSet {
            defaults.set(deepInfraModel, forKey: "deepInfraModel")
        }
    }
    
    // Custom hotkey storage
    @Published public var customKeyCode: UInt32 {
        didSet {
            defaults.set(customKeyCode, forKey: "customKeyCode")
            NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        }
    }
    
    @Published public var customModifiers: UInt32 {
        didSet {
            defaults.set(customModifiers, forKey: "customModifiers")
            NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        }
    }
    
    @Published public var customShortcutDisplay: String {
        didSet {
            defaults.set(customShortcutDisplay, forKey: "customShortcutDisplay")
        }
    }
    
    @Published public var language: String {
        didSet {
            defaults.set(language, forKey: "language")
        }
    }
    
    @Published public var autoPaste: Bool {
        didSet {
            defaults.set(autoPaste, forKey: "autoPaste")
        }
    }
    
    @Published public var restoreClipboard: Bool {
        didSet {
            defaults.set(restoreClipboard, forKey: "restoreClipboard")
        }
    }
    
    @Published public var soundFeedback: Bool {
        didSet {
            defaults.set(soundFeedback, forKey: "soundFeedback")
        }
    }
    
    @Published public var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }
    
    private init() {
        // Default hotkey: Option + Space (kVK_Space = 49, optionKey = 2048)
        let savedCode = defaults.object(forKey: "customKeyCode") as? UInt32 ?? UInt32(kVK_Space)
        let savedMods = defaults.object(forKey: "customModifiers") as? UInt32 ?? UInt32(optionKey)
        let savedTitle = defaults.string(forKey: "customShortcutDisplay") ?? "⌥ Space"
        
        self.customKeyCode = savedCode
        self.customModifiers = savedMods
        self.customShortcutDisplay = savedTitle
        
        self.language = defaults.string(forKey: "language") ?? "ru"
        self.autoPaste = defaults.object(forKey: "autoPaste") as? Bool ?? true
        self.restoreClipboard = defaults.object(forKey: "restoreClipboard") as? Bool ?? true
        self.soundFeedback = defaults.object(forKey: "soundFeedback") as? Bool ?? true
        let savedLocalModelRaw = defaults.string(forKey: "localModel") ?? LocalWhisperModel.largeV3Turbo.rawValue
        self.localModel = LocalWhisperModel(rawValue: savedLocalModelRaw) ?? .largeV3Turbo
        
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        
        let savedModeRaw = defaults.string(forKey: "transcriptionMode") ?? TranscriptionEngineMode.hybrid.rawValue
        self.transcriptionMode = TranscriptionEngineMode(rawValue: savedModeRaw) ?? .hybrid
        
        self.deepInfraApiKey = defaults.string(forKey: "deepInfraApiKey") ?? Preferences.defaultDeepInfraKey
        self.deepInfraModel = defaults.string(forKey: "deepInfraModel") ?? "openai/whisper-large-v3-turbo"
    }
    
    public func setCustomShortcut(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.customKeyCode = keyCode
        self.customModifiers = modifiers
        self.customShortcutDisplay = display
    }
    
    public func resetToDefaultShortcut() {
        setCustomShortcut(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey),
            display: "⌥ Space"
        )
    }
}

extension Notification.Name {
    public static let hotkeyDidChange = Notification.Name("SuperWhisper.hotkeyDidChange")
    public static let localModelDidChange = Notification.Name("SuperWhisper.localModelDidChange")
}
