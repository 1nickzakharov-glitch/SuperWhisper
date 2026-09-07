import SwiftUI
import AppKit

public struct HistoryView: View {
    @ObservedObject var historyService = HistoryService.shared
    @State private var copiedId: UUID? = nil
    @State private var retryingId: UUID? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("Dictation History", "История диктовок"))
                        .font(.system(size: 16, weight: .bold))
                    Text(L10n.tr("Stored locally for 24 hours. Nothing is lost.", "Хранится локально 24 часа. Ваши слова защищены."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !historyService.items.isEmpty {
                    Button(action: {
                        historyService.clearAll()
                    }) {
                        Text(L10n.tr("Clear All", "Очистить всё"))
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // List
            if historyService.items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(L10n.tr("No dictations in the last 24 hours", "Нет диктовок за последние 24 часа"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(L10n.tr("Your speech transcriptions and audio backups will appear here.", "Здесь будут сохраняться все ваши тексты и резервные копии звука."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(historyService.items) { item in
                            historyRow(item: item)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(width: 540, height: 420)
    }
    
    @ViewBuilder
    private func historyRow(item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row Header
            HStack(spacing: 8) {
                // Status icon
                switch item.status {
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .processing:
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
                
                Text(item.formattedTime)
                    .font(.system(size: 12, weight: .semibold))
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text(item.formattedDuration)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Actions
                switch item.status {
                case .completed:
                    Button(action: {
                        historyService.copyToClipboard(item: item)
                        copiedId = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedId == item.id { copiedId = nil }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: copiedId == item.id ? "checkmark" : "doc.on.doc")
                            Text(copiedId == item.id ? L10n.tr("Copied!", "Скопировано!") : L10n.tr("Copy", "Скопировать"))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(copiedId == item.id ? .green : .accentColor)
                    }
                    .buttonStyle(.plain)
                    
                case .failed:
                    Button(action: {
                        retryItem(item)
                    }) {
                        HStack(spacing: 4) {
                            if retryingId == item.id {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(L10n.tr("Retry", "Повторить"))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(retryingId == item.id)
                    
                case .processing:
                    Text(L10n.tr("Processing...", "Распознавание..."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Button(action: {
                    historyService.deleteEntry(id: item.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            
            // Text or Error Body
            switch item.status {
            case .completed:
                Text(item.text)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineLimit(6)
            case .failed(let reason):
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundColor(.red.opacity(0.85))
            case .processing:
                Text(L10n.tr("Transcribing audio...", "Идет обработка аудиофайла..."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
    
    private func retryItem(_ item: HistoryItem) {
        guard let samples = historyService.loadAudioSamples(for: item) else {
            historyService.updateEntry(id: item.id, text: "", status: .failed(reason: "Аудиофайл не найден"))
            return
        }
        
        retryingId = item.id
        historyService.updateEntry(id: item.id, text: "", status: .processing)
        
        Task {
            do {
                let preferredLang = Preferences.shared.language == "auto" ? nil : Preferences.shared.language
                let text = try await AppState.shared.transcriptionEngine.transcribe(audioSamples: samples, language: preferredLang)
                await MainActor.run {
                    self.retryingId = nil
                    if text.isEmpty {
                        historyService.updateEntry(id: item.id, text: "", status: .failed(reason: "Речь не распознана"))
                    } else {
                        historyService.updateEntry(id: item.id, text: text, status: .completed)
                        historyService.copyToClipboard(item: HistoryItem(id: item.id, createdAt: item.createdAt, duration: item.duration, text: text, status: .completed))
                    }
                }
            } catch {
                await MainActor.run {
                    self.retryingId = nil
                    historyService.updateEntry(id: item.id, text: "", status: .failed(reason: error.localizedDescription))
                }
            }
        }
    }
}
