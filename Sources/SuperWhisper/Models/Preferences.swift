import Foundation
import Carbon
import AppKit

public enum CloudProviderPreset: String, CaseIterable, Identifiable, Sendable {
    case deepinfra = "deepinfra"
    case groq = "groq"
    case openai = "openai"
    case custom = "custom"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .deepinfra: return "DeepInfra (Ultra-fast & cheap)"
        case .groq: return "Groq (LPU accelerated, whisper-large-v3)"
        case .openai: return "OpenAI (Official whisper-1)"
        case .custom: return "Custom (OpenAI-compatible / Self-hosted)"
        }
    }
    
    public var defaultBaseURL: String {
        switch self {
        case .deepinfra: return "https://api.deepinfra.com/v1/openai"
        case .groq: return "https://api.groq.com/openai/v1"
        case .openai: return "https://api.openai.com/v1"
        case .custom: return "http://localhost:8000/v1"
        }
    }
    
    public var defaultModel: String {
        switch self {
        case .deepinfra: return "openai/whisper-large-v3"
        case .groq: return "whisper-large-v3"
        case .openai: return "whisper-1"
        case .custom: return "whisper-1"
        }
    }
    
    public var keyPlaceholder: String {
        switch self {
        case .deepinfra: return "DeepInfra API Key"
        case .groq: return "gsk_..."
        case .openai: return "sk-proj-..."
        case .custom: return "API Key (optional for local/self-hosted)"
        }
    }
    
    public var websiteURL: URL? {
        switch self {
        case .deepinfra: return URL(string: "https://deepinfra.com")
        case .groq: return URL(string: "https://console.groq.com")
        case .openai: return URL(string: "https://platform.openai.com")
        case .custom: return nil
        }
    }
}

public enum TranscriptionEngineMode: String, CaseIterable, Identifiable, Sendable {
    case hybrid = "hybrid"
    case cloudOnly = "cloud"
    case localOnly = "local"
    
    public var id: String { rawValue }
    
    @MainActor
    public var title: String {
        switch self {
        case .hybrid: return L10n.tr("Hybrid (Cloud + Offline Fallback)", "Гибридный (Облако + офлайн-фоллбек)")
        case .cloudOnly: return L10n.tr("Cloud Only (Ultra-fast)", "Только облако (Сверхбыстро)")
        case .localOnly: return L10n.tr("Local Only (100% On-Device)", "Только локально (100% на устройстве)")
        }
    }
    
    @MainActor
    public var shortDescription: String {
        switch self {
        case .hybrid:
            return L10n.tr(
                "Uses cloud when online for instant 1-2s response. Seamlessly falls back to local WhisperKit when offline.",
                "Использует облако при наличии сети (1-2 сек). Без интернета автоматически переключается на локальный WhisperKit."
            )
        case .cloudOnly:
            return L10n.tr(
                "Always uses cloud API on dedicated GPUs. Maximum speed with zero local Mac heat or battery drain.",
                "Всегда через облачный API на GPU. Максимальная скорость без нагрева Mac и разряда батареи."
            )
        case .localOnly:
            return L10n.tr(
                "Always runs on Apple Silicon Neural Engine / Metal GPU. 100% privacy without any internet connection.",
                "Всегда работает на чипе Apple Silicon (CoreML/Metal). 100% приватность без подключения к сети."
            )
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
        case .largeV3Turbo: return "Large-v3-Turbo (598 MB — Best Accuracy)"
        case .small: return "Small (460 MB — Balanced)"
        case .base: return "Base (140 MB — Fast & Light)"
        case .tiny: return "Tiny (75 MB — Instant)"
        }
    }
    
    @MainActor
    public var description: String {
        switch self {
        case .largeV3Turbo:
            return L10n.tr("Flagship Whisper model with highest multilingual accuracy and punctuation.", "Флагманская модель с наилучшей точностью и пунктуацией.")
        case .small:
            return L10n.tr("Great quality-to-speed balance for 8GB Mac configurations.", "Отличный баланс скорости и качества для любых Mac.")
        case .base:
            return L10n.tr("Fast inference with minimal RAM footprint.", "Быстрое выполнение, минимальное потребление RAM.")
        case .tiny:
            return L10n.tr("Instant startup and minimal resource usage.", "Мгновенный старт и минимальный вес.")
        }
    }
}

@MainActor
public final class Preferences: ObservableObject {
    public static let shared = Preferences()
    
    private let defaults = UserDefaults.standard
    
    public static let defaultDeepInfraKey = ProcessInfo.processInfo.environment["DEEPINFRA_API_KEY"] ?? ""
    
    // UI Language (Default: English)
    @Published public var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: "appLanguage")
        }
    }
    
    // Cloud Provider & Custom Endpoints
    @Published public var cloudProvider: CloudProviderPreset {
        didSet {
            defaults.set(cloudProvider.rawValue, forKey: "cloudProvider")
        }
    }
    
    @Published public var cloudBaseURL: String {
        didSet {
            defaults.set(cloudBaseURL, forKey: "cloudBaseURL")
        }
    }
    
    @Published public var cloudApiKey: String {
        didSet {
            defaults.set(cloudApiKey, forKey: "cloudApiKey")
            defaults.set(cloudApiKey, forKey: "deepInfraApiKey") // keep backward compat
        }
    }
    
    @Published public var cloudModel: String {
        didSet {
            defaults.set(cloudModel, forKey: "cloudModel")
        }
    }
    
    // Backward compatibility accessor
    public var deepInfraApiKey: String {
        get { cloudApiKey }
        set { cloudApiKey = newValue }
    }
    
    public var deepInfraModel: String {
        get { cloudModel }
        set { cloudModel = newValue }
    }
    
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
        // UI Language: Default English for international appeal, Russian selectable
        let savedLangRaw = defaults.string(forKey: "appLanguage") ?? AppLanguage.english.rawValue
        self.appLanguage = AppLanguage(rawValue: savedLangRaw) ?? .english
        
        // Cloud Provider
        let savedProviderRaw = defaults.string(forKey: "cloudProvider") ?? CloudProviderPreset.deepinfra.rawValue
        let initialProvider = CloudProviderPreset(rawValue: savedProviderRaw) ?? .deepinfra
        self.cloudProvider = initialProvider
        
        self.cloudBaseURL = defaults.string(forKey: "cloudBaseURL") ?? initialProvider.defaultBaseURL
        self.cloudApiKey = defaults.string(forKey: "cloudApiKey") ?? (defaults.string(forKey: "deepInfraApiKey") ?? Preferences.defaultDeepInfraKey)
        let savedCloudModel = defaults.string(forKey: "cloudModel") ?? defaults.string(forKey: "deepInfraModel")
        let resolvedCloudModel: String
        if initialProvider == .deepinfra && savedCloudModel == "openai/whisper-large-v3-turbo" {
            resolvedCloudModel = CloudProviderPreset.deepinfra.defaultModel
            defaults.set(resolvedCloudModel, forKey: "cloudModel")
            defaults.set(resolvedCloudModel, forKey: "deepInfraModel")
        } else if initialProvider == .groq && savedCloudModel == "whisper-large-v3-turbo" {
            resolvedCloudModel = CloudProviderPreset.groq.defaultModel
            defaults.set(resolvedCloudModel, forKey: "cloudModel")
        } else {
            resolvedCloudModel = savedCloudModel ?? initialProvider.defaultModel
        }
        self.cloudModel = resolvedCloudModel
        
        // Default hotkey: Option + Space (kVK_Space = 49, optionKey = 2048)
        let savedCode = defaults.object(forKey: "customKeyCode") as? UInt32 ?? UInt32(kVK_Space)
        let savedMods = defaults.object(forKey: "customModifiers") as? UInt32 ?? UInt32(optionKey)
        let savedTitle = defaults.string(forKey: "customShortcutDisplay") ?? "⌥ Space"
        
        self.customKeyCode = savedCode
        self.customModifiers = savedMods
        self.customShortcutDisplay = savedTitle
        
        let savedModeRaw = defaults.string(forKey: "transcriptionMode") ?? TranscriptionEngineMode.hybrid.rawValue
        self.transcriptionMode = TranscriptionEngineMode(rawValue: savedModeRaw) ?? .hybrid
        
        let savedLocalModelRaw = defaults.string(forKey: "localModel") ?? LocalWhisperModel.largeV3Turbo.rawValue
        self.localModel = LocalWhisperModel(rawValue: savedLocalModelRaw) ?? .largeV3Turbo
        
        self.language = defaults.string(forKey: "language") ?? "auto"
        self.autoPaste = defaults.object(forKey: "autoPaste") as? Bool ?? true
        self.restoreClipboard = defaults.object(forKey: "restoreClipboard") as? Bool ?? true
        self.soundFeedback = defaults.object(forKey: "soundFeedback") as? Bool ?? true
        self.hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
    }
    
    public func selectProviderPreset(_ preset: CloudProviderPreset) {
        self.cloudProvider = preset
        self.cloudBaseURL = preset.defaultBaseURL
        self.cloudModel = preset.defaultModel
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
