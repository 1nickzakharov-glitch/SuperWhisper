import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let appState = AppState.shared
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 [AppDelegate] SuperWhisper launching...")
        
        // Run smoothly as a menu bar utility
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize Menu Bar UI
        menuBarController = MenuBarController(appState: appState)
        
        // Start Hotkey Listener
        HotkeyService.shared.startListening { [weak self] in
            Task { @MainActor in
                self?.appState.toggleRecording()
            }
        }
        
        // Start background prewarm of WhisperKit model
        appState.startEnginePrewarm()
        
        // On first run, open settings to welcome the user
        if !Preferences.shared.hasCompletedOnboarding {
            Preferences.shared.hasCompletedOnboarding = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                SettingsWindowController.shared.showSettings()
            }
        }
        
        print("✅ [AppDelegate] SuperWhisper ready. Hotkey: \(Preferences.shared.hotkeyPreset.title).")
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyService.shared.unregister()
        print("🛑 [AppDelegate] SuperWhisper terminated.")
    }
}
