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
    @Published public var engineStatusMessage: String = "Загрузка модели Whisper..."
    
    public let audioCapture = AudioCaptureService()
    public let transcriptionEngine = TranscriptionEngine()
    public let overlayPanel = OverlayPanel()
    
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var targetApplication: NSRunningApplication?
    private var dismissalWorkItem: DispatchWorkItem?
    
    private init() {
        overlayPanel.setupHUD(appState: self)
    }
    
    public func startEnginePrewarm() {
        Task.detached(priority: .userInitiated) {
            do {
                try await self.transcriptionEngine.initialize()
                await MainActor.run {
                    self.isEngineReady = true
                    self.engineStatusMessage = "Готов к диктовке (⌥ Space)"
                    print("✨ [AppState] Engine prewarmed and ready.")
                }
            } catch {
                await MainActor.run {
                    self.engineStatusMessage = "Ошибка инициализации модели: \(error.localizedDescription)"
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
        
        // Capture currently active app before anything else
        self.targetApplication = NSWorkspace.shared.frontmostApplication
        print("🎯 [AppState] Target application captured: \(self.targetApplication?.localizedName ?? "Unknown")")
        
        Task {
            let hasMicPermission = await audioCapture.requestPermission()
            guard hasMicPermission else {
                self.hudState = .error(message: "Нет доступа к микрофону")
                self.overlayPanel.showHUD()
                self.scheduleHUDDismissal(after: 3.0)
                return
            }
            
            do {
                try self.audioCapture.startRecording()
                self.recordingStartTime = Date()
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
    
    public func stopRecordingAndTranscribe() {
        stopDurationTimer()
        let audioSamples = audioCapture.stopRecording()
        
        guard !audioSamples.isEmpty else {
            self.hudState = .idle
            self.overlayPanel.hideHUD()
            return
        }
        
        self.hudState = .processing
        
        Task {
            do {
                // Runs purely on the background actor, zero UI lag
                let text = try await self.transcriptionEngine.transcribe(audioSamples: audioSamples)
                
                if text.isEmpty {
                    self.hudState = .error(message: "Речь не распознана")
                    self.scheduleHUDDismissal(after: 2.0)
                    return
                }
                
                // Perform automatic paste or fallback to clipboard
                let didAutoPaste = AutoPasteService.shared.paste(text: text, targetApp: self.targetApplication)
                self.hudState = .success(text: text, autoPasted: didAutoPaste)
                
                self.scheduleHUDDismissal(after: didAutoPaste ? 1.6 : 2.5)
            } catch {
                self.hudState = .error(message: "Ошибка распознавания: \(error.localizedDescription)")
                self.scheduleHUDDismissal(after: 3.0)
            }
        }
    }
    
    private func startDurationTimer() {
        stopDurationTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.recordingStartTime else { return }
                let elapsed = Date().timeIntervalSince(start)
                if case .listening = self.hudState {
                    self.hudState = .listening(duration: elapsed)
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
