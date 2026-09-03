import SwiftUI

public struct JarvisSiriHUDView: View {
    @ObservedObject var appState: AppState
    @State private var isHovered = false
    
    // Flat electric cyan color
    private let flatCyan = Color(red: 0.0, green: 0.86, blue: 1.0)
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        Group {
            if appState.hudState == .idle {
                Color.clear.frame(width: 260, height: 70)
            } else {
                liquidGlassCapsule
            }
        }
    }
    
    // MARK: - Liquid Glass Capsule
    private var liquidGlassCapsule: some View {
        ZStack {
            // 1. Frosted Liquid Glass Base
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(red: 0.08, green: 0.12, blue: 0.18).opacity(0.65))
                )
                // Specular Glass Rim (inner top light reflection)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.40),
                                    Color.white.opacity(0.10),
                                    Color.cyan.opacity(0.20)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                )
                // Liquid diffused floating shadow
                .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 7)
                .shadow(color: flatCyan.opacity(0.12), radius: 8, x: 0, y: 2)
            
            // 2. Interactive Content Inside Glass
            Group {
                switch appState.hudState {
                case .listening:
                    if isHovered {
                        hoverControls
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    } else {
                        equalizerView
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    
                case .processing:
                    processingSpinner
                    
                case .success:
                    successView
                    
                case .error(let msg):
                    Text(msg)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.red.opacity(0.9))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                    
                case .idle:
                    EmptyView()
                }
            }
        }
        .frame(width: capsuleWidth, height: 40)
        .padding(14)
        // Liquid organic spring animation for smooth expansion/contraction
        .animation(.interactiveSpring(response: 0.36, dampingFraction: 0.74, blendDuration: 0.15), value: isHovered)
        .animation(.interactiveSpring(response: 0.36, dampingFraction: 0.74, blendDuration: 0.15), value: appState.hudState)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
    
    // MARK: - Equalizer (Sensitive, Flat Cyan, No text)
    private var equalizerView: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<9, id: \.self) { i in
                let level = CGFloat(appState.audioCapture.audioLevels[i])
                let height = max(4.0, level * 24.0)
                
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(flatCyan)
                    .frame(width: 3.2, height: height)
                    .animation(.spring(response: 0.08, dampingFraction: 0.52), value: height)
            }
        }
        .frame(height: 26)
    }
    
    // MARK: - Hover Controls (Larger icons with touch targets)
    private var hoverControls: some View {
        HStack(spacing: 12) {
            // Cancel Button (✕)
            Button(action: {
                appState.cancelCurrentRecording()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 26, height: 26)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red.opacity(0.9))
                }
            }
            .buttonStyle(.plain)
            .help("Отменить запись")
            
            // Pause / Resume Button (⏸ / ▶)
            Button(action: {
                appState.togglePauseCurrentRecording()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 26, height: 26)
                    
                    Image(systemName: appState.audioCapture.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(flatCyan)
                }
            }
            .buttonStyle(.plain)
            .help(appState.audioCapture.isPaused ? "Продолжить запись" : "Пауза")
            
            // Done Button (✓)
            Button(action: {
                appState.stopRecordingAndTranscribe()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 26, height: 26)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green.opacity(0.95))
                }
            }
            .buttonStyle(.plain)
            .help("Готово (вставить)")
        }
        .padding(.horizontal, 6)
    }
    
    // MARK: - Processing Spinner (Guaranteed continuous 60-120fps rotation)
    private var processingSpinner: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let angle = (time * 420.0).truncatingRemainder(dividingBy: 360.0)
            
            HStack(spacing: 8) {
                Circle()
                    .trim(from: 0.12, to: 0.88)
                    .stroke(flatCyan, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 17, height: 17)
                    .rotationEffect(.degrees(angle))
                
                Text("Распознавание...")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(flatCyan)
            }
        }
    }
    
    // MARK: - Success View
    private var successView: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(flatCyan)
            
            Text("Вставлено")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(flatCyan)
        }
    }
    
    private var capsuleWidth: CGFloat {
        switch appState.hudState {
        case .listening:
            return isHovered ? 144 : 96
        case .processing:
            return 146
        case .success:
            return 116
        case .error:
            return 164
        case .idle:
            return 80
        }
    }
}
