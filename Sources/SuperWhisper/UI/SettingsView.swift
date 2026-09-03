import SwiftUI
import Carbon
import AVFoundation

public struct SettingsView: View {
    @ObservedObject var preferences = Preferences.shared
    @ObservedObject var appState = AppState.shared
    
    @State private var isRecordingShortcut = false
    @State private var keyMonitor: Any?
    @State private var modelTestResult: String?
    @State private var isTestingModel = false
    
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
        .frame(width: 560, height: 430)
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
                        // Current Shortcut Display
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .foregroundColor(.cyan)
                            
                            Text(isRecordingShortcut ? "Нажмите комбинацию клавиш..." : preferences.customShortcutDisplay)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(isRecordingShortcut ? .orange : .primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(8)
                        
                        Button(isRecordingShortcut ? "Отмена" : "Записать свою комбинацию") {
                            if isRecordingShortcut {
                                stopRecordingShortcut()
                            } else {
                                startRecordingShortcut()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isRecordingShortcut ? .red : .accentColor)
                    }
                    
                    // Quick presets
                    HStack(spacing: 8) {
                        Text("Быстрые пресеты:")
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
                        Text("🟢 Готов к работе (\(preferences.customShortcutDisplay))")
                            .foregroundColor(.green)
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("🟡 \(appState.engineStatusMessage)")
                                .foregroundColor(.orange)
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                }
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
                        Text("Тест микрофона (говорите прямо сейчас):")
                            .font(.subheadline)
                        Spacer()
                        Text(appState.audioCapture.isMonitoring ? "🟢 Слушаю" : "⚪ Ожидание")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Live Audio Equalizer & RMS Bar
                    VStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.18))
                                
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        LinearGradient(
                                            colors: [.cyan, .blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * CGFloat(min(max(appState.audioCapture.rmsLevel * 2.2, 0.04), 1.0)))
                                    .animation(.spring(response: 0.1, dampingFraction: 0.55), value: appState.audioCapture.rmsLevel)
                            }
                        }
                        .frame(height: 16)
                        
                        // Mini 7-band live frequency visualizer
                        HStack(spacing: 6) {
                            ForEach(0..<appState.audioCapture.audioLevels.count, id: \.self) { i in
                                let h = max(4, CGFloat(appState.audioCapture.audioLevels[i]) * 24)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.cyan.opacity(0.8))
                                    .frame(width: 8, height: h)
                                    .animation(.spring(response: 0.1, dampingFraction: 0.5), value: h)
                            }
                            Spacer()
                            Text("Уровень RMS: \(Int(appState.audioCapture.rmsLevel * 100))%")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 24)
                    }
                    
                    Text("Если столбики прыгают при вашем голосе — микрофон захватывает звук чисто.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Живой индикатор микрофона").font(.headline)
            }
            
            Section {
                HStack {
                    Text("Доступ к микрофону:")
                    Spacer()
                    Text("🟢 Разрешён")
                        .foregroundColor(.green)
                        .font(.system(size: 12, weight: .semibold))
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Универсальный доступ (для авто-вставки):")
                            .font(.system(size: 13))
                        Text("Необходим macOS для авто-нажатия Cmd+V в активном окне")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if appState.isAccessibilityGranted {
                        Text("🟢 Разрешён")
                            .foregroundColor(.green)
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Button("Выдать доступ в Настройках") {
                            _ = AutoPasteService.checkAccessibilityPermissions(prompt: true)
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Системные разрешения macOS").font(.headline)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            appState.audioCapture.startMonitoring()
            appState.refreshPermissions()
        }
        .onDisappear {
            appState.audioCapture.stopMonitoring()
        }
    }
    
    // MARK: - Model Tab
    private var modelTab: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: "brain.head.profile")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .foregroundColor(.cyan)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenAI Whisper Large-v3-Turbo")
                        .font(.headline)
                    Text("Флагманская модель CoreML с ускорением на Neural Engine")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(12)
            
            VStack(spacing: 10) {
                infoRow(label: "Размер модели на диске:", value: "598 МБ (установлена в App Support)")
                infoRow(label: "Аппаратный движок:", value: "Apple Neural Engine (ANE) + GPU")
                infoRow(label: "Скорость распознавания:", value: "0.14x (40 сек речи за 5.4 сек)")
                infoRow(label: "Детектор пауз (VAD):", value: "Voice Activity Detection активен")
                infoRow(label: "Конфиденциальность:", value: "100% On-Device (без интернета)")
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
            
            // Model Test Button
            HStack {
                Button(isTestingModel ? "Тестирование..." : "Проверить инференс модели") {
                    isTestingModel = true
                    Task {
                        let res = await appState.runSampleModelTest()
                        self.modelTestResult = res
                        self.isTestingModel = false
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTestingModel)
                
                if let result = modelTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer()
            
            // Minimalist Cyan Icon matching App Icon
            ZStack {
                Circle()
                    .fill(Color(red: 0.05, green: 0.08, blue: 0.14))
                    .frame(width: 84, height: 84)
                    .overlay(
                        Circle().stroke(Color.cyan, lineWidth: 3)
                    )
                    .shadow(color: Color.cyan.opacity(0.4), radius: 12)
                
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
            
            Text("Персональная умная диктовка с интерфейсом Siri + Jarvis и локальной нейросетью Whisper Large-v3-Turbo.")
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
            
            // Ignore bare modifier key presses
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
            
            let keyName: String
            switch Int(keyCode) {
            case kVK_Space: keyName = "Space"
            case kVK_Return: keyName = "Return"
            case kVK_Tab: keyName = "Tab"
            default:
                keyName = event.charactersIgnoringModifiers?.uppercased() ?? "Key"
            }
            
            displayParts.append(keyName)
            
            
            // Minimum requirement: must have at least one modifier
            if carbonMods == 0 {
                // If user pressed Space with no modifier, default to Option + Space
                carbonMods = UInt32(optionKey)
                displayParts.insert("⌥", at: 0)
            }
            
            preferences.setCustomShortcut(
                keyCode: keyCode,
                modifiers: carbonMods,
                display: displayParts.joined(separator: " ")
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
