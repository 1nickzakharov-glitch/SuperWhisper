import AppKit
import Carbon

@MainActor
public final class AutoPasteService {
    public static let shared = AutoPasteService()
    
    private var lastPasteTimestamp: Date = .distantPast
    
    private init() {}
    
    @discardableResult
    public func paste(text: String, targetApp: NSRunningApplication?) -> Bool {
        guard !text.isEmpty else { return false }
        
        let now = Date()
        guard now.timeIntervalSince(lastPasteTimestamp) > 0.4 else {
            print("⚠️ [AutoPasteService] Debounced duplicate paste call within \(now.timeIntervalSince(lastPasteTimestamp))s")
            return false
        }
        lastPasteTimestamp = now
        
        // 1. Set text on system clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("📋 [AutoPasteService] Set text in pasteboard (\(text.count) chars)")
        
        // 2. Reactivate target application so it regains keyboard focus
        if let target = targetApp, target.processIdentifier != NSRunningApplication.current.processIdentifier {
            target.activate(options: .activateIgnoringOtherApps)
        }
        
        // 3. Post simulated Cmd+V with crisp 80ms settling delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.dispatchCmdVKeystroke()
        }
        
        return true
    }
    
    private func dispatchCmdVKeystroke() {
        let vKeyCode: CGKeyCode = 0x09 // Virtual keycode for 'V'
        let source = CGEventSource(stateID: .combinedSessionState)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            print("⚠️ [AutoPasteService] Failed to create CGEvents")
            return
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        // Post ONLY to .cghidEventTap to prevent duplicate keystroke delivery in Electron / Chromium apps
        keyDown.post(tap: .cghidEventTap)
        
        // 25ms key-down hold time
        usleep(25_000)
        
        keyUp.post(tap: .cghidEventTap)
        
        print("✅ [AutoPasteService] Single Cmd+V keystroke dispatched to active app.")
    }
    
    public static func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
