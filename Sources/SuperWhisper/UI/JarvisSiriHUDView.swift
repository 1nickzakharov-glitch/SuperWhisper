import SwiftUI

public struct JarvisSiriHUDView: View {
    @ObservedObject var appState: AppState
    @State private var isHovered = false
    
    // Flat modern electric cyan
    private let flatCyan = Color(red: 0.0, green: 0.88, blue: 1.0)
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        Group {
            if appState.hudState == .idle {
                Color.clear.frame(width: 240, height: 60)
            } else {
                capsuleContent
            }
        }
    }
    
    private var capsuleContent: some View {
        ZStack {
            // Dark glass capsule background
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.05, green: 0.07, blue: 0.11).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(flatCyan.opacity(0.40), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
            
            // Inside Content
            Group {
                switch appState.hudState {
                case .listening:
                    if isHovered {
                        hoverControls
                    } else {
                        equalizerAnimation
                    }
                    
                case .processing:
                    processingSpinner
                    
                case .success:
                    successCheckmark
                    
                case .error(let msg):
                    Text(msg)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.red.opacity(0.9))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                    
                case .idle:
                    EmptyView()
                }
            }
        }
        .frame(width: capsuleWidth, height: 36)
        .padding(12)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                self.isHovered = hovering
            }
        }
    }
    
    // MARK: - Equalizer (Live, Flat Cyan, Reactive to voice)
    private var equalizerAnimation: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<9, id: \.self) { i in
                let level = CGFloat(appState.audioCapture.audioLevels[i])
                let height = max(4, level * 22)
                
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(flatCyan)
                    .frame(width: 3.0, height: height)
                    .animation(.spring(response: 0.08, dampingFraction: 0.5), value: height)
            }
        }
        .frame(height: 24)
    }
    
    // MARK: - Hover Controls (Cancel ✕, Pause/Resume ⏸/▶, Done ✓)
    private var hoverControls: some View {
        HStack(spacing: 14) {
            // Cancel button
            Button(action: {
                appState.cancelCurrentRecording()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.red.opacity(0.9))
            }
            .buttonStyle(.plain)
            .help("Отменить запись")
            
            // Pause / Resume button
            Button(action: {
                appState.togglePauseCurrentRecording()
            }) {
                Image(systemName: appState.audioCapture.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(flatCyan)
            }
            .buttonStyle(.plain)
            .help(appState.audioCapture.isPaused ? "Продолжить запись" : "Поставить на паузу")
            
            // Done / Transcribe button
            Button(action: {
                appState.stopRecordingAndTranscribe()
            }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green.opacity(0.9))
            }
            .buttonStyle(.plain)
            .help("Готово (распознать и вставить)")
        }
    }
    
    // MARK: - Processing Spinner (TimelineView guaranteed continuous spin)
    private var processingSpinner: some View {
        TimelineView(.animation) { timeline in
            let date = timeline.date.timeIntervalSinceReferenceDate
            let angle = (date * 360.0).truncatingRemainder(dividingBy: 360.0)
            
            HStack(spacing: 8) {
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(flatCyan, style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(angle))
                
                Text("Распознавание...")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(flatCyan)
            }
        }
    }
    
    // MARK: - Success Checkmark
    private var successCheckmark: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(flatCyan)
            
            Text("Вставлено")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(flatCyan)
        }
    }
    
    private var capsuleWidth: CGFloat {
        switch appState.hudState {
        case .listening:
            return isHovered ? 140 : 100
        case .processing:
            return 140
        case .success:
            return 110
        case .error:
            return 160
        case .idle:
            return 80
        }
    }
}
