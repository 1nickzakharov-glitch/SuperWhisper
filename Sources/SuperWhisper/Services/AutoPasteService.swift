import AppKit
import Carbon

@MainActor
public final class AutoPasteService {
    public static let shared = AutoPasteService()
    
    private init() {}
    
    @discardableResult
    public func paste(text: String, targetApp: NSRunningApplication?) -> Bool {
        guard !text.isEmpty else { return false }
        
        // 1. Put text on clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("📋 [AutoPasteService] Set \(text.count) chars on pasteboard: '\(text)'")
        
        // 2. Reactivate target application if specified
        if let target = targetApp, target.processIdentifier != NSRunningApplication.current.processIdentifier {
            target.activate(options: .activateAllWindows)
        }
        
        // 3. Dispatch simulated paste with settling delay
        let targetPid = targetApp?.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            self.simulatePasteKeystroke(targetPid: targetPid)
        }
        
        return true
    }
    
    private func simulatePasteKeystroke(targetPid: pid_t?) {
        let source = CGEventSource(stateID: .hidSystemState)
        let commandKey: CGKeyCode = 0x37 // Virtual keycode for Command
        let vKey: CGKeyCode = 0x09       // Virtual keycode for V (layout-independent)
        
        // Post full 4-event sequence (Command Down -> V Down -> V Up -> Command Up)
        if let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: true),
           let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
           let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false),
           let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: commandKey, keyDown: false) {
            
            vDown.flags = .maskCommand
            vUp.flags = .maskCommand
            
            cmdDown.post(tap: .cghidEventTap)
            vDown.post(tap: .cghidEventTap)
            vUp.post(tap: .cghidEventTap)
            cmdUp.post(tap: .cghidEventTap)
            print("🚀 [AutoPasteService] CGEvent 4-step Cmd+V dispatched.")
        }
        
        // AppleScript fallback after brief tick for Electron / web apps
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            let scriptSource = "tell application \"System Events\" to keystroke \"v\" using command down"
            if let script = NSAppleScript(source: scriptSource) {
                var err: NSDictionary?
                script.executeAndReturnError(&err)
                if err == nil {
                    print("🚀 [AutoPasteService] AppleScript System Events keystroke dispatched.")
                }
            }
        }
    }
    
    public static func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
