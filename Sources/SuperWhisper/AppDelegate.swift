import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private let appState = AppState.shared
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 [AppDelegate] SuperWhisper launching...")
        
        // Hide dock icon to run smoothly as a menu bar / background utility
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize Menu Bar UI
        menuBarController = MenuBarController(appState: appState)
        
        // Register Global Hotkey (Option + Space)
        HotkeyService.shared.registerGlobalHotkey { [weak self] in
            Task { @MainActor in
                self?.appState.toggleRecording()
            }
        }
        
        // Start background prewarm of WhisperKit model
        appState.startEnginePrewarm()
        
        print("✅ [AppDelegate] SuperWhisper ready. Press Option + Space to dictate.")
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        HotkeyService.shared.unregister()
        print("🛑 [AppDelegate] SuperWhisper terminated.")
    }
}
