import SwiftUI
import AVFoundation

public struct SettingsView: View {
    @ObservedObject var preferences = Preferences.shared
    @ObservedObject var appState = AppState.shared
    
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
        .frame(width: 540, height: 400)
        .padding(16)
    }
    
    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            Section {
                Picker("Горячая клавиша:", selection: $preferences.hotkeyPreset) {
                    ForEach(HotkeyPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .help("Клавиша для старта и остановки надиктовки текста")
                
                Picker("Язык распознавания:", selection: $preferences.language) {
                    Text("Русский (RU)").tag("ru")
                    Text("English (EN)").tag("en")
                    Text("Автоопределение языка").tag("auto")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Управление и язык").font(.headline)
            }
            
            Section {
                Toggle("Автоматически вставлять текст в активное окно (⌘V)", isOn: $preferences.autoPaste)
                    .help("Если выключено, текст будет только копироваться в буфер обмена")
                
                Toggle("Восстанавливать исходный буфер обмена после вставки", isOn: $preferences.restoreClipboard)
                    .help("После успешной вставки надиктованного текста вернёт ваши ранее скопированные файлы или текст")
                
                Toggle("Звуковой сигнал при нажатии хоткея", isOn: $preferences.soundFeedback)
            } header: {
                Text("Поведение").font(.headline)
            }
            
            Section {
                HStack {
                    Text("Текущий статус:")
                    Spacer()
                    Text(appState.isEngineReady ? "🟢 Готов к работе" : "🟡 \(appState.engineStatusMessage)")
                        .foregroundColor(appState.isEngineReady ? .green : .orange)
                        .font(.system(size: 12, weight: .medium))
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
                    Text("Тест входного сигнала:")
                        .font(.subheadline)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.cyan)
                        
                        // Live Audio Level Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.2))
                                
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        LinearGradient(
                                            colors: [.cyan, .blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * CGFloat(min(max(appState.audioCapture.rmsLevel * 2.5, 0.05), 1.0)))
                                    .animation(.spring(response: 0.1, dampingFraction: 0.6), value: appState.audioCapture.rmsLevel)
                            }
                        }
                        .frame(height: 14)
                    }
                    
                    Text("Говорите в микрофон, чтобы увидеть реакцию уровня звука.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Чувствительность микрофона").font(.headline)
            }
            
            Section {
                HStack {
                    Text("Доступ к микрофону:")
                    Spacer()
                    Text("Разрешён")
                        .foregroundColor(.green)
                        .font(.system(size: 12, weight: .semibold))
                }
                
                HStack {
                    Text("Универсальный доступ (для авто-вставки):")
                    Spacer()
                    let isAx = AutoPasteService.checkAccessibilityPermissions(prompt: false)
                    if isAx {
                        Text("Разрешён")
                            .foregroundColor(.green)
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Button("Запросить доступ") {
                            _ = AutoPasteService.checkAccessibilityPermissions(prompt: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Системные разрешения").font(.headline)
            }
        }
        .formStyle(.grouped)
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
                    Text("Флагманская модель распознавания речи Apple Silicon CoreML")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(12)
            
            VStack(spacing: 10) {
                infoRow(label: "Размер модели на диске:", value: "598 МБ (локально)")
                infoRow(label: "Архитектура ускорителя:", value: "Apple Neural Engine (ANE) + GPU")
                infoRow(label: "Скорость распознавания:", value: "0.14x (в 7 раз быстрее речи)")
                infoRow(label: "Детектор пауз:", value: "Voice Activity Detection (VAD)")
                infoRow(label: "Конфиденциальность:", value: "100% On-Device (без интернета)")
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(spacing: 14) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "waveform.circle.fill")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .foregroundColor(.cyan)
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
            
            HStack(spacing: 12) {
                Button("GitHub репозиторий") {
                    if let url = URL(string: "https://github.com/1nickzakharov-glitch/SuperWhisper") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 6)
            
            Spacer()
        }
        .padding()
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
