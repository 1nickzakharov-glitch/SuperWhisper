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
    
    let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()
    
    public init() {}
    
    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("Основные", systemImage: "gearshape")
                }
            
            audioTab
                .tabItem {
                    Label("Микрофон", systemImage: "mic.fill")
                }
            
            modelTab
                .tabItem {
                    Label("Нейросеть", systemImage: "cpu")
                }
            
            aboutTab
                .tabItem {
                    Label("О программе", systemImage: "info.circle")
                }
        }
        .frame(width: 580, height: 490)
        .padding(16)
        .onReceive(timer) { _ in
            appState.refreshPermissions()
        }
    }
    
    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Горячая клавиша для диктовки:")
                        .font(.system(size: 13, weight: .medium))
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .foregroundColor(.accentColor)
                            
                            Text(isRecordingShortcut ? "Нажмите комбинацию клавиш..." : preferences.customShortcutDisplay)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(isRecordingShortcut ? .accentColor : .primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(8)
                        
                        Button(isRecordingShortcut ? "Отмена" : "Записать комбинацию") {
                            if isRecordingShortcut {
                                stopRecordingShortcut()
                            } else {
                                startRecordingShortcut()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    HStack(spacing: 8) {
                        Text("Пресеты:")
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
                
                Picker("Язык распознавания:", selection: $preferences.language) {
                    Text("Русский (RU) — рекомендуется").tag("ru")
                    Text("English (EN)").tag("en")
                    Text("Автоопределение языка").tag("auto")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Управление и запуск").font(.headline)
            }
            
            Section {
                Toggle("Автоматически вставлять текст в активное окно (⌘V)", isOn: $preferences.autoPaste)
                    .help("Если выключено, текст только копируется в буфер обмена")
                
                Toggle("Восстанавливать исходный буфер обмена после вставки", isOn: $preferences.restoreClipboard)
                    .help("Сохраняет ваши скопированные файлы, пароли и код")
                
                Toggle("Звуковой сигнал при нажатии хоткея", isOn: $preferences.soundFeedback)
            } header: {
                Text("Поведение").font(.headline)
            }
            
            Section {
                HStack {
                    Text("Статус готовности к работе:")
                    Spacer()
                    if appState.isEngineReady {
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 8, height: 8)
                            Text("Готов к работе (\(preferences.customShortcutDisplay))")
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
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Audio Tab (Liquid Smooth VU Meter at 120 FPS)
    private var audioTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Тест микрофона (говорите для проверки):")
                            .font(.subheadline)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(appState.audioCapture.isMonitoring ? Color.green : Color.secondary)
                                .frame(width: 7, height: 7)
                            Text(appState.audioCapture.isMonitoring ? "Слушаю" : "Ожидание")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // 120 FPS Smooth VU-meter line
                    VStack(spacing: 8) {
                        TimelineView(.animation) { _ in
                            let target = CGFloat(appState.audioCapture.rmsLevel)
                            let glided = smoothedMicRMS * 0.80 + target * 0.20
                            
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.18))
                                    
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            LinearGradient(
                                                colors: [.cyan, .blue],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geo.size.width * min(max(glided * 1.8, 0.04), 1.0))
                                }
                            }
                            .frame(height: 16)
                            .onAppear { smoothedMicRMS = glided }
                            .onChange(of: glided) { _, newVal in smoothedMicRMS = newVal }
                        }
                        .frame(height: 16)
                        
                        HStack {
                            Text("Уровень чувствительности: \(Int(smoothedMicRMS * 100))%")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    
                    Text("Шкала плавно реагирует на громкость голоса без задержек.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Индикатор микрофона").font(.headline)
            }
            
            Section {
                HStack {
                    Text("Доступ к микрофону:")
                    Spacer()
                    let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                    if micStatus == .authorized {
                        HStack(spacing: 5) {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                            Text("Разрешён")
                                .font(.system(size: 12, weight: .medium))
                        }
                    } else {
                        Button("Запросить доступ") {
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
                            Text("Универсальный доступ:")
                                .font(.system(size: 13))
                            Text("Необходим для авто-вставки текста в активное окно")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if appState.isAccessibilityGranted {
                            HStack(spacing: 5) {
                                Circle().fill(Color.green).frame(width: 7, height: 7)
                                Text("Разрешён")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        } else {
                            Button("Открыть Системные настройки") {
                                _ = AutoPasteService.checkAccessibilityPermissions(prompt: true)
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    
                    if !appState.isAccessibilityGranted {
                        Text("Совет: если тумблер в Настройках уже включен, выключите и включите его снова один раз, чтобы система привязала разрешение к новому сертификату разработчика.")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                    }
                }
            } header: {
                Text("Системные разрешения").font(.headline)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .authorized {
                appState.audioCapture.startMonitoring()
            } else if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.appState.audioCapture.startMonitoring()
                        }
                    }
                }
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
                // Network and Engine Status Card
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
                        Text("Движок транскрипции речи")
                            .font(.headline)
                        Text(networkMonitor.isConnected ? "🟢 Интернет активен • Облако DeepInfra доступно" : "🟡 Офлайн режим • Активен локальный WhisperKit")
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
                    Text("Режим обработки:").font(.headline)
                    
                    Picker("Режим", selection: $preferences.transcriptionMode) {
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
                
                // DeepInfra Settings (shown unless local-only is forced)
                if preferences.transcriptionMode != .localOnly {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Облачный сервис DeepInfra").font(.headline)
                            Spacer()
                            Link("deepinfra.com ↗", destination: URL(string: "https://deepinfra.com")!)
                                .font(.caption)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Ключ DeepInfra:")
                                .font(.system(size: 12, weight: .medium))
                            
                            HStack(spacing: 8) {
                                if showApiKey {
                                    TextField("DeepInfra API Key", text: $preferences.deepInfraApiKey)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField("DeepInfra API Key", text: $preferences.deepInfraApiKey)
                                        .textFieldStyle(.roundedBorder)
                                }
                                
                                Button(action: { showApiKey.toggle() }) {
                                    Image(systemName: showApiKey ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.borderless)
                                .help(showApiKey ? "Скрыть ключ" : "Показать ключ")
                                
                                Button("Ключ Storello") {
                                    preferences.deepInfraApiKey = Preferences.defaultDeepInfraKey
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Восстановить рабочий ключ из Storello")
                            }
                        }
                        
                        HStack {
                            Text("Модель:")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Picker("", selection: $preferences.deepInfraModel) {
                                Text("Whisper Large-v3-Turbo (быстрая)").tag("openai/whisper-large-v3-turbo")
                                Text("Whisper Large-v3 (макс. точность)").tag("openai/whisper-large-v3")
                            }
                            .frame(width: 280)
                        }
                        
                        Text("⚡️ Скорость: 2-4 минуты речи распознаются за ~1.2 секунды!")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(12)
                }
                
                // Local Engine Details
                VStack(alignment: .leading, spacing: 10) {
                    Text("Локальный движок (WhisperKit on Apple Silicon)").font(.headline)
                    
                    VStack(spacing: 8) {
                        infoRow(label: "Модель:", value: "Whisper Large-v3-Turbo (CoreML)")
                        infoRow(label: "Аппаратный чип:", value: "Apple Silicon GPU (Metal) + CPU")
                        infoRow(label: "Локальный статус:", value: appState.isEngineReady ? "Готов к автономной работе" : "Инициализация...")
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
                
                // Testing Section
                HStack(spacing: 12) {
                    Button(isTestingModel ? "Тестирование..." : "Проверить инференс") {
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
            
            Text("Версия 1.0.0 (Native Apple Silicon)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Персональная умная диктовка с интерфейсом Liquid Glass и локальной нейросетью Whisper Large-v3-Turbo.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 30)
            
            Button("GitHub репозиторий") {
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
            
            let formattedTitle = displayParts.joined(separator: " ")
            preferences.setCustomShortcut(
                keyCode: keyCode,
                modifiers: carbonMods,
                display: formattedTitle
            )
            
            stopRecordingShortcut()
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
}
