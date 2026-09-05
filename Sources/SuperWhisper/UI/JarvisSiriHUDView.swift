import SwiftUI

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
                    .fill(isHovered ? Color.white.opacity(0.32) : Color.white.opacity(0.10))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(isHovered ? activeColor : Color.clear, lineWidth: 1.4)
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isHovered ? activeColor : baseColor)
            }
            .scaleEffect(isHovered ? 1.16 : 1.0)
            .shadow(color: isHovered ? activeColor.opacity(0.45) : Color.clear, radius: 6)
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.62), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help(helpText)
    }
}

public struct JarvisSiriHUDView: View {
    @ObservedObject var appState: AppState
    @State private var isPillHovered = false
    
    // Flat modern electric cyan
    private let flatCyan = Color(red: 0.0, green: 0.88, blue: 1.0)
    // Multi-crested acoustic envelope: strong central dome with lively wing crests on bars 1 & 7
    private let domeEnvelope: [CGFloat] = [0.38, 0.78, 0.62, 0.92, 1.00, 0.92, 0.62, 0.78, 0.38]
    
    // Alternating contrast multipliers: ensures neighboring bars alternate in height
    // so it never looks like a flat, uniform wall of bars
    private let alternatingSteps: [CGFloat] = [0.90, 1.15, 0.82, 1.08, 1.00, 1.08, 0.82, 1.15, 0.90]
    
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
            // 1. Frosted Liquid Glass Base (translucent and adaptive to dark & light backgrounds)
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.10, green: 0.14, blue: 0.22).opacity(0.25),
                                    Color(red: 0.04, green: 0.06, blue: 0.10).opacity(0.40)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                // Specular Glass Rim (crisp top light reflection)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.60),
                                    Color.white.opacity(0.18),
                                    flatCyan.opacity(0.30)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                )
                // Diffused soft floating shadow (no bottom clipping, elegant on light and dark)
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
                .shadow(color: flatCyan.opacity(0.12), radius: 4, x: 0, y: 1)
            
            // 2. Interactive Content Inside Glass
            Group {
                switch appState.hudState {
                case .listening:
                    if isPillHovered {
                        hoverControls
                            .transition(.opacity.combined(with: .scale(scale: 0.90)))
                    } else {
                        centeredEqualizerView
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
    
    // MARK: - Symmetrical Centered 60 FPS Liquid Equalizer
    private var centeredEqualizerView: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let volume = CGFloat(appState.audioCapture.rmsLevel)
            
            HStack(spacing: 3.6) {
                ForEach(0..<9, id: \.self) { i in
                    let dist = abs(CGFloat(i) - 4.0)
                    
                    // 1. Idle breathing wave: gentle undulating ripple in silence
                    let idleWave = 3.8 + sin(time * 2.2 + Double(i) * 0.75) * 1.1
                    
                    // 2. Dynamic voice wave:
                    // - Traveling wave moving outward from center
                    // - Secondary vocal texture harmonic
                    let waveTravel = sin(time * 5.2 - Double(dist) * 0.95)
                    let waveTexture = cos(time * 8.5 + Double(i) * 1.4)
                    let dynamicMod = 0.68 + 0.32 * (waveTravel * 0.70 + waveTexture * 0.30)
                    
                    // 3. Voice height with dome shape and alternating step contrast
                    let voiceHeight = volume * 19.5 * domeEnvelope[i] * alternatingSteps[i] * CGFloat(dynamicMod)
                    
                    // 4. Final bar height (between 3.8px and 24.5px)
                    let barHeight = min(24.5, max(CGFloat(idleWave), 3.8 + voiceHeight))
                    
                    RoundedRectangle(cornerRadius: 1.6)
                        .fill(flatCyan)
                        .frame(width: 3.2, height: barHeight)
                }
            }
            .frame(height: 26)
        }
    }
    
    // MARK: - Hover Controls
    private var hoverControls: some View {
        HStack(spacing: 14) {
            // Cancel Button (✕)
            HoverActionButton(
                icon: "xmark",
                baseColor: .red.opacity(0.85),
                activeColor: .red,
                helpText: L10n.tr("Cancel recording", "Отменить запись")
            ) {
                appState.cancelCurrentRecording()
            }
            
            // Pause / Resume Button (⏸ / ▶)
            HoverActionButton(
                icon: appState.audioCapture.isPaused ? "play.fill" : "pause.fill",
                baseColor: flatCyan.opacity(0.9),
                activeColor: flatCyan,
                helpText: appState.audioCapture.isPaused ? L10n.tr("Resume", "Продолжить") : L10n.tr("Pause", "Пауза")
            ) {
                appState.togglePauseCurrentRecording()
            }
            
            // Done Button (✓)
            HoverActionButton(
                icon: "checkmark",
                baseColor: .green.opacity(0.85),
                activeColor: .green,
                helpText: L10n.tr("Done (paste)", "Готово (вставить)")
            ) {
                appState.stopRecordingAndTranscribe()
            }
        }
        .padding(.horizontal, 6)
    }
    
    // MARK: - Processing Spinner (Smooth 60fps rotation)
    private var processingSpinner: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let angle = (time * 360.0).truncatingRemainder(dividingBy: 360.0)
            
            HStack(spacing: 8) {
                Circle()
                    .trim(from: 0.12, to: 0.88)
                    .stroke(flatCyan, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .frame(width: 17, height: 17)
                    .rotationEffect(.degrees(angle))
                
                Text(appState.processingStatusText)
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
            
            Text(L10n.tr("Pasted", "Вставлено"))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(flatCyan)
        }
    }
    
    private var capsuleWidth: CGFloat {
        switch appState.hudState {
        case .listening:
            return isPillHovered ? 152 : 98
        case .processing:
            return max(160, CGFloat(appState.processingStatusText.count * 8 + 48))
        case .success:
            return 118
        case .error:
            return 164
        case .idle:
            return 80
        }
    }
}
