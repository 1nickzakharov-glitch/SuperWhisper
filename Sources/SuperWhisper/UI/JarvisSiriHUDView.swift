import SwiftUI

// Dedicated interactive button with explicit hover feedback (lighting up & scaling)
struct HoverActionButton: View {
    let icon: String
    let baseColor: Color
    let activeColor: Color
    let helpText: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovered ? Color.white.opacity(0.24) : Color.white.opacity(0.08))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(isHovered ? activeColor.opacity(0.85) : Color.clear, lineWidth: 1.2)
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isHovered ? activeColor : baseColor)
            }
            .scaleEffect(isHovered ? 1.14 : 1.0)
            .shadow(color: isHovered ? activeColor.opacity(0.4) : Color.clear, radius: 6)
            .animation(.interactiveSpring(response: 0.20, dampingFraction: 0.65), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { h in self.isHovered = h }
        .help(helpText)
    }
}

public struct JarvisSiriHUDView: View {
    @ObservedObject var appState: AppState
    @State private var isPillHovered = false
    
    // Flat electric cyan color
    private let flatCyan = Color(red: 0.0, green: 0.88, blue: 1.0)
    
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
                        .fill(Color(red: 0.06, green: 0.09, blue: 0.15).opacity(0.68))
                )
                // Specular Glass Rim (inner top light reflection)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.42),
                                    Color.white.opacity(0.12),
                                    flatCyan.opacity(0.20)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                )
                // Soft diffused floating shadow
                .shadow(color: Color.black.opacity(0.25), radius: 14, x: 0, y: 7)
                .shadow(color: flatCyan.opacity(0.10), radius: 6, x: 0, y: 2)
            
            // 2. Interactive Content Inside Glass
            Group {
                switch appState.hudState {
                case .listening:
                    if isPillHovered {
                        hoverControls
                            .transition(.opacity.combined(with: .scale(scale: 0.90)))
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
                        .foregroundColor(.red.opacity(0.95))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                    
                case .idle:
                    EmptyView()
                }
            }
        }
        .frame(width: capsuleWidth, height: 40)
        .padding(14)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.72, blendDuration: 0.15), value: isPillHovered)
        .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.72, blendDuration: 0.15), value: appState.hudState)
        .onHover { hovering in
            self.isPillHovered = hovering
        }
    }
    
    // MARK: - 120 FPS Fluid FFT Equalizer (Real frequency bands, organic breathing)
    private var equalizerView: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            
            HStack(spacing: 3.5) {
                ForEach(0..<9, id: \.self) { i in
                    let fftLevel = CGFloat(appState.audioCapture.audioLevels[i])
                    // Subtle organic breathing wave in silence so it never looks dead
                    let idleBreath = 4.0 + sin(time * 3.2 + Double(i) * 0.6) * 1.5
                    let activeHeight = fftLevel * 25.0
                    let barHeight = max(idleBreath, activeHeight)
                    
                    RoundedRectangle(cornerRadius: 1.6)
                        .fill(flatCyan)
                        .frame(width: 3.2, height: barHeight)
                }
            }
            .frame(height: 26)
        }
    }
    
    // MARK: - Hover Controls (Cancel ✕, Pause/Resume ⏸/▶, Done ✓ with hover states)
    private var hoverControls: some View {
        HStack(spacing: 12) {
            // Cancel Button
            HoverActionButton(
                icon: "xmark",
                baseColor: .red.opacity(0.85),
                activeColor: .red,
                helpText: "Отменить запись"
            ) {
                appState.cancelCurrentRecording()
            }
            
            // Pause / Resume Button
            HoverActionButton(
                icon: appState.audioCapture.isPaused ? "play.fill" : "pause.fill",
                baseColor: flatCyan.opacity(0.9),
                activeColor: flatCyan,
                helpText: appState.audioCapture.isPaused ? "Продолжить" : "Пауза"
            ) {
                appState.togglePauseCurrentRecording()
            }
            
            // Done Button
            HoverActionButton(
                icon: "checkmark",
                baseColor: .green.opacity(0.85),
                activeColor: .green,
                helpText: "Готово (вставить)"
            ) {
                appState.stopRecordingAndTranscribe()
            }
        }
        .padding(.horizontal, 6)
    }
    
    // MARK: - Processing Spinner (Continuous 120fps rotation)
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
            return isPillHovered ? 148 : 98
        case .processing:
            return 148
        case .success:
            return 118
        case .error:
            return 164
        case .idle:
            return 80
        }
    }
}
