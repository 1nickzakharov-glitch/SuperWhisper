import SwiftUI

public struct JarvisSiriHUDView: View {
    @ObservedObject var appState: AppState
    
    @State private var rotationAngle: Double = 0
    
    // Pure Electric Cyan & Deep Neon Blue palette (NO purple/magenta)
    private let jarvisBlueColors: [Color] = [
        Color(red: 0.0, green: 0.95, blue: 1.0),    // Electric Cyan
        Color(red: 0.0, green: 0.65, blue: 1.0),    // Vibrant Azure
        Color(red: 0.05, green: 0.35, blue: 0.95),  // Tech Blue
        Color(red: 0.0, green: 0.75, blue: 1.0),    // Bright Cyan
        Color(red: 0.0, green: 0.95, blue: 1.0)     // Loop to Cyan
    ]
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        Group {
            if appState.hudState == .idle {
                Color.clear.frame(width: 280, height: 80)
            } else {
                activeHUDContent
            }
        }
    }
    
    private var activeHUDContent: some View {
        ZStack {
            // 1. Ambient Electric Blue Glow
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: jarvisBlueColors,
                        center: .center,
                        angle: .degrees(rotationAngle)
                    ),
                    lineWidth: glowLineWidth
                )
                .blur(radius: glowBlurRadius)
                .opacity(glowOpacity)
                .scaleEffect(pillScale)
            
            // 2. Compact Glassmorphic Capsule (Height: 42pt, Width: 230pt)
            HStack(spacing: 12) {
                jarvisReactorNode
                statusContentView
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(width: 232, height: 42)
            .background(
                ZStack {
                    // Deep space blue glass
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(Color(red: 0.03, green: 0.06, blue: 0.11).opacity(0.92))
                    
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.85)
                    
                    // Razor-thin sharp electric blue border
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: jarvisBlueColors,
                                center: .center,
                                angle: .degrees(rotationAngle)
                            ),
                            lineWidth: 1.2
                        )
                        .opacity(0.90)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .shadow(color: Color.black.opacity(0.40), radius: 14, x: 0, y: 6)
        }
        .padding(18)
        .onAppear {
            withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
    
    @ViewBuilder
    private var jarvisReactorNode: some View {
        ZStack {
            switch appState.hudState {
            case .listening:
                // Outer tech ring
                Circle()
                    .stroke(Color.cyan.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                
                // Rotating segment
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(
                        Color.cyan,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotationAngle * 2.5))
                    .frame(width: 22, height: 22)
                
                // Pulsing voice core
                Circle()
                    .fill(Color.cyan)
                    .frame(
                        width: 7 + CGFloat(appState.audioCapture.rmsLevel * 10),
                        height: 7 + CGFloat(appState.audioCapture.rmsLevel * 10)
                    )
                    .shadow(color: Color.cyan, radius: 4)
                    .animation(.spring(response: 0.12, dampingFraction: 0.5), value: appState.audioCapture.rmsLevel)
                
            case .processing:
                // Fast spinning blue scanner ring
                Circle()
                    .stroke(Color.cyan.opacity(0.2), lineWidth: 2)
                    .frame(width: 22, height: 22)
                
                Circle()
                    .trim(from: 0.0, to: 0.6)
                    .stroke(
                        LinearGradient(colors: [Color.cyan, Color.blue], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotationAngle * 4.5))
                    .frame(width: 22, height: 22)
                
            case .success:
                Circle()
                    .fill(Color.cyan.opacity(0.2))
                    .frame(width: 22, height: 22)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.cyan)
                
            case .error:
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 22, height: 22)
                
                Image(systemName: "exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
                
            case .idle:
                EmptyView()
            }
        }
        .frame(width: 24, height: 24)
    }
    
    @ViewBuilder
    private var statusContentView: some View {
        switch appState.hudState {
        case .listening(let duration):
            HStack(spacing: 8) {
                // High-detail 11-bar electric equalizer
                HStack(spacing: 2.5) {
                    ForEach(0..<7, id: \.self) { i in
                        let level = CGFloat(appState.audioCapture.audioLevels[i])
                        let barHeight = max(4, level * 20)
                        
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.0, green: 0.50, blue: 1.0),
                                        Color(red: 0.0, green: 0.95, blue: 1.0)
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 2.5, height: barHeight)
                            .animation(.spring(response: 0.10, dampingFraction: 0.5), value: barHeight)
                    }
                }
                .frame(height: 20)
                
                Spacer()
                
                // Clean duration timer
                Text(formatDuration(duration))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.9))
            }
            
        case .processing:
            HStack(spacing: 6) {
                Text("Распознавание...")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.cyan.opacity(0.9))
                Spacer()
            }
            
        case .success:
            HStack(spacing: 6) {
                Text("Вставлено!")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.cyan)
                Spacer()
            }
            
        case .error(let msg):
            HStack {
                Text(msg)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.red.opacity(0.9))
                    .lineLimit(1)
                Spacer()
            }
            
        case .idle:
            EmptyView()
        }
    }
    
    private var glowLineWidth: CGFloat {
        switch appState.hudState {
        case .listening:
            return 3 + CGFloat(appState.audioCapture.rmsLevel * 5)
        case .processing:
            return 2.5
        case .success, .error:
            return 2
        case .idle:
            return 0
        }
    }
    
    private var glowBlurRadius: CGFloat {
        switch appState.hudState {
        case .listening:
            return 6 + CGFloat(appState.audioCapture.rmsLevel * 8)
        case .processing:
            return 8
        case .success, .error:
            return 5
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
            return 1.0 + CGFloat(appState.audioCapture.rmsLevel * 0.02)
        default:
            return 1.0
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
