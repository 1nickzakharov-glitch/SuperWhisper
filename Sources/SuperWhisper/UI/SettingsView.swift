import SwiftUI
import Carbon
import AVFoundation

public enum KeycodeMapper {
    public static func latinName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        default: return "Key\(keyCode)"
        }
    }
}

public struct SettingsView: View {
    @ObservedObject var preferences = Preferences.shared
    @ObservedObject var appState = AppState.shared
    @ObservedObject var networkMonitor = NetworkMonitor.shared
    
    @State private var isRecordingShortcut = false
    @State private var keyMonitor: Any?
    @State private var modelTestResult: String?
    @State private var isTestingModel = false
    @State private var smoothedMicRMS: CGFloat = 0.04
    @State private var showApiKey = false
    @State public var selectedTab: Int = 0
    
    let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem {
                    Label(L10n.tr("General", "Основные"), systemImage: "gearshape")
                }
                .tag(0)
            
            audioTab
                .tabItem {
                    Label(L10n.tr("Microphone", "Микрофон"), systemImage: "mic.fill")
                }
                .tag(1)
            
            modelTab
                .tabItem {
                    Label(L10n.tr("AI Engine", "Нейросеть"), systemImage: "cpu")
                }
                .tag(2)
            
            aboutTab
                .tabItem {
                    Label(L10n.tr("About", "О программе"), systemImage: "info.circle")
                }
                .tag(3)
        }
        .frame(width: 590, height: 510)
        .padding(16)
        .onReceive(timer) { _ in
            appState.refreshPermissions()
        }
    }
    
    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            Section {
                // UI Language
                Picker(L10n.tr("Interface Language:", "Язык интерфейса:"), selection: $preferences.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("Dictation Hotkey:", "Горячая клавиша для диктовки:"))
                        .font(.system(size: 13, weight: .medium))
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .foregroundColor(.accentColor)
                            
                            Text(isRecordingShortcut ? L10n.tr("Press shortcut keys...", "Нажмите комбинацию клавиш...") : preferences.customShortcutDisplay)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(isRecordingShortcut ? .accentColor : .primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(8)
                        
                        Button(isRecordingShortcut ? L10n.tr("Cancel", "Отмена") : L10n.tr("Record Shortcut", "Записать комбинацию")) {
                            if isRecordingShortcut {
                                stopRecordingShortcut()
                            } else {
                                startRecordingShortcut()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    HStack(spacing: 8) {
                        Text(L10n.tr("Presets:", "Пресеты:"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        presetButton("⌥ Space", code: UInt32(kVK_Space), mods: UInt32(optionKey))
                        presetButton("⌃ Space", code: UInt32(kVK_Space), mods: UInt32(controlKey))
                        presetButton("⇧ ⌘ Space", code: UInt32(kVK_Space), mods: UInt32(shiftKey | cmdKey))
                        presetButton("⌥ D", code: UInt32(kVK_ANSI_D), mods: UInt32(optionKey))
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
                
                Picker(L10n.tr("Speech Language:", "Язык распознавания:"), selection: $preferences.language) {
                    Text(L10n.tr("Auto Detect Language", "Автоопределение языка")).tag("auto")
                    Text("English (EN)").tag("en")
                    Text("Русский (RU)").tag("ru")
                    Text("Español (ES)").tag("es")
                    Text("Deutsch (DE)").tag("de")
                    Text("Français (FR)").tag("fr")
                    Text("中文 (ZH)").tag("zh")
                    Text("日本語 (JA)").tag("ja")
                }
                .pickerStyle(.menu)
            } header: {
                Text(L10n.tr("Input & Trigger", "Управление и запуск")).font(.headline)
            }
            
            Section {
                Toggle(L10n.tr("Auto-paste text into active window (⌘V)", "Автоматически вставлять текст в активное окно (⌘V)"), isOn: $preferences.autoPaste)
                    .help(L10n.tr("When disabled, text is only copied to the clipboard.", "Если выключено, текст только копируется в буфер обмена."))
                
                Toggle(L10n.tr("Restore previous clipboard content after paste", "Восстанавливать исходный буфер обмена после вставки"), isOn: $preferences.restoreClipboard)
                    .help(L10n.tr("Preserves your copied files, passwords, or code snippets.", "Сохраняет ваши скопированные файлы, пароли и код."))
                
                Toggle(L10n.tr("Sound feedback on hotkey", "Звуковой сигнал при нажатии хоткея"), isOn: $preferences.soundFeedback)
            } header: {
                Text(L10n.tr("Behavior", "Поведение")).font(.headline)
            }
            
            Section {
                HStack {
                    Text(L10n.tr("Engine readiness:", "Статус готовности к работе:"))
                    Spacer()
                    if appState.isEngineReady {
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text(L10n.tr("Ready (\(preferences.customShortcutDisplay))", "Готов к работе (\(preferences.customShortcutDisplay))"))
                                .foregroundColor(.primary)
                                .font(.system(size: 12, weight: .medium))
                        }
                    } else {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(appState.engineStatusMessage)
                                .foregroundColor(.secondary)
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                }
            } header: {
                Text(L10n.tr("Status", "Статус")).font(.headline)
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Audio Tab
    private var audioTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(.accentColor)
                        Text(L10n.tr("Live input volume:", "Громкость входного сигнала:"))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(String(format: "%.0f%%", Double(appState.audioCapture.rmsLevel * 100)))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    GeometryReader { geo in
                        let targetVal = CGFloat(appState.audioCapture.rmsLevel)
                        let width = max(4.0, targetVal * geo.size.width)
                        
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 12)
                            
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan, .blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: min(geo.size.width, width), height: 12)
                                .animation(.easeOut(duration: 0.08), value: targetVal)
                        }
                    }
                    .frame(height: 14)
                    
                    Text(L10n.tr("Speak to test microphone response.", "Шкала плавно реагирует на громкость голоса."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text(L10n.tr("Microphone Meter", "Индикатор микрофона")).font(.headline)
            }
            
            Section {
                HStack {
                    Text(L10n.tr("Microphone permission:", "Доступ к микрофону:"))
                    Spacer()
                    let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                    if micStatus == .authorized {
                        HStack(spacing: 5) {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                            Text(L10n.tr("Granted", "Разрешён"))
                                .font(.system(size: 12, weight: .medium))
                        }
                    } else {
                        Button(L10n.tr("Request Access", "Запросить доступ")) {
                            AVCaptureDevice.requestAccess(for: .audio) { granted in
                                DispatchQueue.main.async {
                                    if granted {
                                        self.appState.audioCapture.startMonitoring()
                                    }
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("Accessibility permission:", "Универсальный доступ:"))
                                .font(.system(size: 13))
                            Text(L10n.tr("Required for instant Cmd+V auto-pasting into active apps", "Необходим для авто-вставки текста в активное окно"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if appState.isAccessibilityGranted {
                            HStack(spacing: 5) {
                                Circle().fill(Color.green).frame(width: 7, height: 7)
                                Text(L10n.tr("Granted", "Разрешён"))
                                    .font(.system(size: 12, weight: .medium))
                            }
                        } else {
                            Button(L10n.tr("Open System Settings", "Открыть Системные настройки")) {
                                _ = AutoPasteService.checkAccessibilityPermissions(prompt: true)
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text(L10n.tr("Permissions", "Системные разрешения")).font(.headline)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .authorized {
                appState.audioCapture.startMonitoring()
            }
            appState.refreshPermissions()
        }
        .onDisappear {
            appState.audioCapture.stopMonitoring()
        }
    }
    
    // MARK: - Model Tab
    private var modelTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                // Connection and Status Card
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: networkMonitor.isConnected ? "bolt.horizontal.icloud.fill" : "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 22))
                            .foregroundColor(networkMonitor.isConnected ? .accentColor : .orange)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.tr("Speech Transcription Engine", "Движок транскрипции речи"))
                            .font(.headline)
                        Text(networkMonitor.isConnected ? L10n.tr("🟢 Online • Cloud API active", "🟢 Интернет активен • Облачный API доступен") : L10n.tr("🟡 Offline • Local WhisperKit active", "🟡 Офлайн • Активен локальный WhisperKit"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(12)
                
                // Mode Selector
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Processing Mode:", "Режим обработки:")).font(.headline)
                    
                    Picker("Mode", selection: $preferences.transcriptionMode) {
                        ForEach(TranscriptionEngineMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    
                    Text(preferences.transcriptionMode.shortDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
                
                // Cloud Provider Settings
                if preferences.transcriptionMode != .localOnly {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(L10n.tr("Cloud Provider (OpenAI-compatible)", "Облачный сервис (OpenAI-совместимый)")).font(.headline)
                            Spacer()
                            if let web = preferences.cloudProvider.websiteURL {
                                Link(preferences.cloudProvider.rawValue + " ↗", destination: web)
                                    .font(.caption)
                            }
                        }
                        
                        // Preset Picker
                        HStack {
                            Text(L10n.tr("Provider Preset:", "Пресет провайдера:"))
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Picker("", selection: $preferences.cloudProvider) {
                                ForEach(CloudProviderPreset.allCases) { preset in
                                    Text(preset.displayName).tag(preset)
                                }
                            }
                            .frame(width: 330)
                            .onChange(of: preferences.cloudProvider) { _, newPreset in
                                preferences.selectProviderPreset(newPreset)
                            }
                        }
                        
                        // Base URL
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr("Base Endpoint URL:", "Базовый URL эндпоинта:"))
                                .font(.system(size: 12, weight: .medium))
                            TextField("https://...", text: $preferences.cloudBaseURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        
                        // API Key
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr("API Key:", "API Ключ:"))
                                .font(.system(size: 12, weight: .medium))
                            
                            HStack(spacing: 8) {
                                if showApiKey {
                                    TextField(preferences.cloudProvider.keyPlaceholder, text: $preferences.cloudApiKey)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField(preferences.cloudProvider.keyPlaceholder, text: $preferences.cloudApiKey)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                Button(action: { showApiKey.toggle() }) {
                                    Image(systemName: showApiKey ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.borderless)
                                .help(showApiKey ? L10n.tr("Hide key", "Скрыть ключ") : L10n.tr("Show key", "Показать ключ"))
                                
                                Button(L10n.tr("Clear", "Очистить")) {
                                    preferences.cloudApiKey = ""
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Text(L10n.tr("Works with DeepInfra, Groq, OpenAI, or self-hosted vLLM/Whisper servers. Without a key, SuperWhisper works 100% free offline via WhisperKit.", "Работает с DeepInfra, Groq, OpenAI или локальными vLLM серверами. Без ключа приложение работает бесплатно офлайн через WhisperKit."))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        // Model Name
                        HStack {
                            Text(L10n.tr("Model Name:", "Модель:"))
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            TextField("Model identifier", text: $preferences.cloudModel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 330)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(12)
                }
                
                // Local WhisperKit Engine Details
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Local Engine (WhisperKit on Apple Silicon)", "Локальный движок (WhisperKit on Apple Silicon)")).font(.headline)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.tr("Local Model:", "Локальная модель:"))
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Picker("", selection: $preferences.localModel) {
                                ForEach(LocalWhisperModel.allCases) { m in
                                    Text(m.displayName).tag(m)
                                }
                            }
                            .frame(width: 330)
                        }
                        
                        Text(preferences.localModel.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                    
                    VStack(spacing: 8) {
                        infoRow(label: L10n.tr("Hardware Acceleration:", "Аппаратный чип:"), value: "Apple Silicon GPU (Metal) + CPU")
                        infoRow(label: L10n.tr("Offline Readiness:", "Локальный статус:"), value: appState.isEngineReady ? L10n.tr("Ready for offline use", "Готов к автономной работе") : L10n.tr("Initializing...", "Инициализация..."))
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
                
                // Testing Section
                HStack(spacing: 12) {
                    Button(isTestingModel ? L10n.tr("Testing...", "Тестирование...") : L10n.tr("Test Speech Inference", "Проверить инференс")) {
                        isTestingModel = true
                        Task {
                            let res = await appState.runSampleModelTest()
                            self.modelTestResult = res
                            self.isTestingModel = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isTestingModel)
                    
                    if let result = modelTestResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color(red: 0.05, green: 0.08, blue: 0.14))
                    .frame(width: 84, height: 84)
                    .overlay(
                        Circle().stroke(Color.cyan, lineWidth: 3)
                    )
                    .shadow(color: Color.cyan.opacity(0.3), radius: 10)
                
                HStack(spacing: 4) {
                    bar(height: 14)
                    bar(height: 24)
                    bar(height: 38)
                    bar(height: 48)
                    bar(height: 38)
                    bar(height: 24)
                    bar(height: 14)
                }
            }
            
            Text("SuperWhisper")
                .font(.title2.weight(.bold))
            
            Text("Version 1.1.0 (Native Apple Silicon)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(L10n.tr(
                "Smart voice dictation with Liquid Glass HUD, multi-provider cloud support, and on-device WhisperKit inference.",
                "Персональная умная диктовка с интерфейсом Liquid Glass, поддержкой любых облачных API и локальным WhisperKit."
            ))
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)
            .padding(.horizontal, 30)
            
            Button("GitHub Repository ↗") {
                if let url = URL(string: "https://github.com/1nickzakharov-glitch/SuperWhisper") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private func bar(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.cyan)
            .frame(width: 4, height: height)
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
        }
    }
    
    private func presetButton(_ title: String, code: UInt32, mods: UInt32) -> some View {
        Button(title) {
            preferences.setCustomShortcut(keyCode: code, modifiers: mods, display: title)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    
    private func startRecordingShortcut() {
        isRecordingShortcut = true
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let keyCode = UInt32(event.keyCode)
            let flags = event.modifierFlags
            
            if keyCode == 54 || keyCode == 55 || keyCode == 56 || keyCode == 58 || keyCode == 59 || keyCode == 60 || keyCode == 61 || keyCode == 62 {
                return nil
            }
            
            var carbonMods: UInt32 = 0
            var displayParts: [String] = []
            
            if flags.contains(.control) {
                carbonMods |= UInt32(controlKey)
                displayParts.append("⌃")
            }
            if flags.contains(.option) {
                carbonMods |= UInt32(optionKey)
                displayParts.append("⌥")
            }
            if flags.contains(.shift) {
                carbonMods |= UInt32(shiftKey)
                displayParts.append("⇧")
            }
            if flags.contains(.command) {
                carbonMods |= UInt32(cmdKey)
                displayParts.append("⌘")
            }
            
            let keyName = KeycodeMapper.latinName(for: keyCode)
            displayParts.append(keyName)
            
            if carbonMods == 0 {
                carbonMods = UInt32(optionKey)
                displayParts.insert("⌥", at: 0)
            }
            
            let display = displayParts.joined(separator: " ")
            self.preferences.setCustomShortcut(keyCode: keyCode, modifiers: carbonMods, display: display)
            self.stopRecordingShortcut()
            return nil
        }
    }
    
    private func stopRecordingShortcut() {
        isRecordingShortcut = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
