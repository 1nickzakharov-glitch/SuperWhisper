import SwiftUI

public struct JarvisSiriHUDView: View {
    @ObservedObject var appState: AppState
    
    @State private var rotationAngle: Double = 0
    
    // Iridescent Siri & Jarvis color palette
    private let siriColors: [Color] = [
        Color(red: 0.0, green: 0.95, blue: 1.0),   // Cyan / Jarvis Neon
        Color(red: 0.3, green: 0.4, blue: 1.0),    // Electric Cobalt
        Color(red: 0.7, green: 0.2, blue: 1.0),    // Purple / Siri Vivid
        Color(red: 1.0, green: 0.2, blue: 0.6),    // Magenta Accent
        Color(red: 0.0, green: 0.95, blue: 1.0)    // Loop to Cyan
    ]
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ZStack {
            // 1. Ambient Siri Glow (outside capsule)
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: siriColors,
                        center: .center,
                        angle: .degrees(rotationAngle)
                    ),
                    lineWidth: glowLineWidth
                )
                .blur(radius: glowBlurRadius)
                .opacity(glowOpacity)
                .scaleEffect(pillScale)
            
            // 2. Glassmorphic Capsule Body
            HStack(spacing: 16) {
                // Jarvis Core Indicator
                jarvisCoreNode
                
                // Status content & waveforms
                statusContentView
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minWidth: 280, maxWidth: 390, minHeight: 64, maxHeight: 64)
            .background(
                ZStack {
                    // Deep dark glass
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color.black.opacity(0.80))
                    
                    // Ultra thin material
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.85)
                    
                    // Inner sharp iridescent border
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: siriColors,
                                center: .center,
                                angle: .degrees(rotationAngle)
                            ),
                            lineWidth: 1.2
                        )
                        .opacity(0.85)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: Color.black.opacity(0.45), radius: 22, x: 0, y: 10)
        }
        .padding(24) // room for glow
        .onAppear {
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var jarvisCoreNode: some View {
        ZStack {
            switch appState.hudState {
            case .listening:
                // Jarvis Arc Reactor pulsing ring
                Circle()
                    .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
                    .frame(width: 32, height: 32)
                
                Circle()
                    .trim(from: 0.1, to: 0.9)
                    .stroke(
                        AngularGradient(colors: [Color.cyan, Color.purple, Color.cyan], center: .center),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotationAngle * 2.5))
                    .frame(width: 32, height: 32)
                
                // Reactive core pulsing with RMS level
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cyan, Color.blue.opacity(0.2)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 16
                        )
                    )
                    .frame(
                        width: 14 + CGFloat(appState.audioCapture.rmsLevel * 16),
                        height: 14 + CGFloat(appState.audioCapture.rmsLevel * 16)
                    )
                    .animation(.spring(response: 0.12, dampingFraction: 0.5), value: appState.audioCapture.rmsLevel)
                
            case .processing:
                // Fast spinning Jarvis processing ring
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                    .frame(width: 32, height: 32)
                
                Circle()
                    .trim(from: 0.0, to: 0.6)
                    .stroke(
                        AngularGradient(colors: [Color.cyan, Color.blue, Color.purple], center: .center),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotationAngle * 4))
                    .frame(width: 32, height: 32)
                
            case .success:
                Circle()
                    .fill(Color.green.opacity(0.25))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.green)
                
            case .error:
                Circle()
                    .fill(Color.red.opacity(0.25))
                    .frame(width: 32, height: 32)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.red)
                
            case .idle:
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 32, height: 32)
            }
        }
        .frame(width: 34, height: 34)
    }
    
    @ViewBuilder
    private var statusContentView: some View {
        switch appState.hudState {
        case .listening(let duration):
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Слушаю...")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(formatDuration(duration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                // Reactive Equalizer Waveform Bars (Jarvis visualizer)
                HStack(spacing: 3) {
                    ForEach(0..<appState.audioCapture.audioLevels.count, id: \.self) { index in
                        let level = index < appState.audioCapture.audioLevels.count ? CGFloat(appState.audioCapture.audioLevels[index]) : 0.1
                        let barHeight = max(6, level * 28)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.0, green: 0.9, blue: 1.0),
                                        Color(red: 0.7, green: 0.3, blue: 1.0)
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 3.5, height: barHeight)
                            .animation(.spring(response: 0.12, dampingFraction: 0.6), value: barHeight)
                    }
                }
                .frame(height: 28)
            }
            
        case .processing:
            HStack(spacing: 8) {
                Text("Расшифровка...")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("Large-v3-Turbo")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(6)
            }
            
        case .success(let text, let autoPasted):
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(autoPasted ? "Вставлено!" : "Скопировано в буфер (⌘V)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(autoPasted ? .green : .cyan)
                    
                    Text(text.prefix(32) + (text.count > 32 ? "..." : ""))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer()
            }
            
        case .error(let msg):
            HStack {
                Text(msg)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.red.opacity(0.9))
                    .lineLimit(1)
                Spacer()
            }
            
        case .idle:
            EmptyView()
        }
    }
    
    // MARK: - Helpers
    
    private var glowLineWidth: CGFloat {
        switch appState.hudState {
        case .listening:
            return 4 + CGFloat(appState.audioCapture.rmsLevel * 8)
        case .processing:
            return 3
        case .success, .error:
            return 2
        case .idle:
            return 0
        }
    }
    
    private var glowBlurRadius: CGFloat {
        switch appState.hudState {
        case .listening:
            return 8 + CGFloat(appState.audioCapture.rmsLevel * 14)
        case .processing:
            return 10
        case .success, .error:
            return 6
        case .idle:
            return 0
        }
    }
    
    private var glowOpacity: Double {
        switch appState.hudState {
        case .listening:
            return 0.75 + Double(appState.audioCapture.rmsLevel * 0.25)
        case .processing:
            return 0.85
        case .success, .error:
            return 0.6
        case .idle:
            return 0
        }
    }
    
    private var pillScale: CGFloat {
        switch appState.hudState {
        case .listening:
            return 1.0 + CGFloat(appState.audioCapture.rmsLevel * 0.04)
        default:
            return 1.0
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", mins, secs, tenths)
    }
}
