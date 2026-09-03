import AppKit
import Carbon

@MainActor
public final class AutoPasteService {
    public static let shared = AutoPasteService()
    
    private init() {}
    
    @discardableResult
    public func paste(text: String, targetApp: NSRunningApplication?) -> Bool {
        guard !text.isEmpty else { return false }
        
        // 1. Set text on system clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("📋 [AutoPasteService] Set text in pasteboard (\(text.count) chars)")
        
        // 2. Reactivate target application so it regains keyboard focus
        if let target = targetApp, target.processIdentifier != NSRunningApplication.current.processIdentifier {
            target.activate(options: .activateIgnoringOtherApps)
        }
        
        // 3. Post simulated Cmd+V with settling delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.dispatchCmdVKeystroke()
        }
        
        return true
    }
    
    private func dispatchCmdVKeystroke() {
        let vKeyCode: CGKeyCode = 0x09 // Virtual keycode for 'V' (layout-independent)
        let source = CGEventSource(stateID: .combinedSessionState)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            print("⚠️ [AutoPasteService] Failed to create CGEvents")
            return
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        // Post key down
        keyDown.post(tap: .cgSessionEventTap)
        keyDown.post(tap: .cghidEventTap)
        
        // 25ms delay before key up
        usleep(25_000)
        
        // Post key up
        keyUp.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cghidEventTap)
        
        print("🚀 [AutoPasteService] Pure Cmd+V keystroke dispatched to active app.")
    }
    
    public static func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
