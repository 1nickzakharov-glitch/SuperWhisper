import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let appState = AppState.shared
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 [AppDelegate] SuperWhisper launching...")
        
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController(appState: appState)
        
        // Start Global Hotkey Listener
        HotkeyService.shared.startListening { [weak self] in
            Task { @MainActor in
                self?.appState.toggleRecording()
            }
        }
        
        // Distributed notification for automated testing and CLI inspection
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.nickzakharov.superwhisper.toggle"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.appState.toggleRecording()
            }
        }
        
        // Start background prewarm of WhisperKit model
        appState.startEnginePrewarm()
        
        // First run onboarding
        if !Preferences.shared.hasCompletedOnboarding {
            Preferences.shared.hasCompletedOnboarding = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                SettingsWindowController.shared.showSettings()
            }
        }
        
        print("✅ [AppDelegate] SuperWhisper ready. Hotkey: \(Preferences.shared.customShortcutDisplay).")
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyService.shared.unregister()
        print("🛑 [AppDelegate] SuperWhisper terminated.")
    }
}
