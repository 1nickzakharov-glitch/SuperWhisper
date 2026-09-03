import AppKit
import SwiftUI
import Combine

public enum HUDState: Equatable, Sendable {
    case idle
    case listening(duration: TimeInterval)
    case processing
    case success(text: String, autoPasted: Bool)
    case error(message: String)
}

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()
    
    @Published public var hudState: HUDState = .idle
    @Published public var isEngineReady: Bool = false
    @Published public var engineStatusMessage: String = "Инициализация Whisper..."
    @Published public var isAccessibilityGranted: Bool = false
    @Published public var isMicPermissionGranted: Bool = true
    
    public let audioCapture = AudioCaptureService()
    public let transcriptionEngine = TranscriptionEngine()
    public let overlayPanel = OverlayPanel()
    
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var accumulatedDuration: TimeInterval = 0
    private var targetApplication: NSRunningApplication?
    private var dismissalWorkItem: DispatchWorkItem?
    
    private init() {
        overlayPanel.setupHUD(appState: self)
        refreshPermissions()
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissions()
            }
        }
    }
    
    public func refreshPermissions() {
        self.isAccessibilityGranted = AutoPasteService.checkAccessibilityPermissions(prompt: false)
    }
    
    public func startEnginePrewarm() {
        Task.detached(priority: .userInitiated) {
            do {
                try await self.transcriptionEngine.initialize()
                await MainActor.run {
                    self.isEngineReady = true
                    self.engineStatusMessage = "Готов к работе (\(Preferences.shared.customShortcutDisplay))"
                    print("✨ [AppState] Engine prewarmed and ready.")
                }
            } catch {
                await MainActor.run {
                    self.engineStatusMessage = "Ошибка инициализации: \(error.localizedDescription)"
                    print("❌ [AppState] Prewarm failed: \(error)")
                }
            }
        }
    }
    
    public func toggleRecording() {
        cancelPendingDismissal()
        switch hudState {
        case .idle, .success, .error:
            startRecording()
        case .listening:
            stopRecordingAndTranscribe()
        case .processing:
            print("⏳ [AppState] Already processing speech, please wait.")
        }
    }
    
    public func startRecording() {
        cancelPendingDismissal()
        
        // Capture active application BEFORE showing overlay
        self.targetApplication = NSWorkspace.shared.frontmostApplication
        print("🎯 [AppState] Target application captured: \(self.targetApplication?.localizedName ?? "Unknown")")
        
        if Preferences.shared.soundFeedback {
            NSSound(named: "Pop")?.play()
        }
        
        Task {
            let hasMicPermission = await audioCapture.requestPermission()
            self.isMicPermissionGranted = hasMicPermission
            guard hasMicPermission else {
                self.hudState = .error(message: "Нет доступа к микрофону")
                self.overlayPanel.showHUD()
                self.scheduleHUDDismissal(after: 3.0)
                return
            }
            
            do {
                try self.audioCapture.startRecording()
                self.recordingStartTime = Date()
                self.accumulatedDuration = 0
                self.hudState = .listening(duration: 0.0)
                self.overlayPanel.showHUD()
                self.startDurationTimer()
            } catch {
                self.hudState = .error(message: "Ошибка записи: \(error.localizedDescription)")
                self.overlayPanel.showHUD()
                self.scheduleHUDDismissal(after: 2.5)
            }
        }
    }
    
    public func cancelCurrentRecording() {
        stopDurationTimer()
        audioCapture.cancelRecording()
        self.hudState = .idle
        self.overlayPanel.hideHUD()
        print("🚫 [AppState] Recording cancelled by user.")
    }
    
    public func togglePauseCurrentRecording() {
        audioCapture.togglePause()
    }
    
    public func stopRecordingAndTranscribe() {
        stopDurationTimer()
        let audioSamples = audioCapture.stopRecording()
        
        guard !audioSamples.isEmpty else {
            self.hudState = .idle
            self.overlayPanel.hideHUD()
            return
        }
        
        if Preferences.shared.soundFeedback {
            NSSound(named: "Blow")?.play()
        }
        
        self.hudState = .processing
        
        Task {
            do {
                let preferredLang = Preferences.shared.language == "auto" ? nil : Preferences.shared.language
                let text = try await self.transcriptionEngine.transcribe(audioSamples: audioSamples, language: preferredLang)
                
                if text.isEmpty {
                    self.hudState = .error(message: "Речь не распознана")
                    self.scheduleHUDDismissal(after: 2.0)
                    return
                }
                
                // Show success confirmation on the HUD for 0.4s
                self.hudState = .success(text: text, autoPasted: true)
                
                // Hide HUD first so target application gains full window & cursor focus!
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                    self.overlayPanel.hideHUD {
                        Task { @MainActor in
                            self.hudState = .idle
                            // Paste text directly into the now-active target text field
                            AutoPasteService.shared.paste(text: text, targetApp: self.targetApplication)
                        }
                    }
                }
            } catch {
                self.hudState = .error(message: "Ошибка распознавания: \(error.localizedDescription)")
                self.scheduleHUDDismissal(after: 3.0)
            }
        }
    }
    
    public func runSampleModelTest() async -> String {
        do {
            let sampleRate = 16000
            var testBuffer = [Float](repeating: 0.0, count: Int(Double(sampleRate) * 1.5))
            for i in 0..<testBuffer.count {
                testBuffer[i] = sin(Float(i) * 0.05) * 0.1
            }
            _ = try await self.transcriptionEngine.transcribe(audioSamples: testBuffer, language: "ru")
            return "✅ Модель успешно отвечает на запросы (инференс активен)!"
        } catch {
            return "❌ Ошибка теста: \(error.localizedDescription)"
        }
    }
    
    private func startDurationTimer() {
        stopDurationTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.recordingStartTime else { return }
                if !self.audioCapture.isPaused {
                    let elapsed = Date().timeIntervalSince(start)
                    if case .listening = self.hudState {
                        self.hudState = .listening(duration: elapsed)
                    }
                }
            }
        }
    }
    
    private func stopDurationTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    private func cancelPendingDismissal() {
        dismissalWorkItem?.cancel()
        dismissalWorkItem = nil
    }
    
    private func scheduleHUDDismissal(after delay: TimeInterval) {
        cancelPendingDismissal()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.overlayPanel.hideHUD {
                Task { @MainActor in
                    self.hudState = .idle
                }
            }
        }
        
        self.dismissalWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
