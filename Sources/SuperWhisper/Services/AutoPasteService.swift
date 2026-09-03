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
        print("📋 [AutoPasteService] Set \(text.count) chars on pasteboard.")
        
        // 2. Check accessibility permissions
        let hasAccessibility = Self.checkAccessibilityPermissions(prompt: false)
        guard hasAccessibility else {
            print("⚠️ [AutoPasteService] Accessibility not granted. Text is in clipboard for manual paste.")
            return false
        }
        
        // 3. Reactivate target application
        if let target = targetApp, target.processIdentifier != NSRunningApplication.current.processIdentifier {
            target.activate(options: [])
        }
        
        // 4. Dispatch synthetic Cmd+V with settling delay
        let targetPid = targetApp?.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.simulatePasteKeystroke(targetPid: targetPid)
        }
        
        return true
    }
    
    private func simulatePasteKeystroke(targetPid: pid_t?) {
        let vKeyCode: CGKeyCode = 0x09 // Virtual key code for 'V'
        
        // Try CGEvent first
        if let source = CGEventSource(stateID: .combinedSessionState),
           let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            
            if let pid = targetPid {
                keyDown.postToPid(pid)
                keyUp.postToPid(pid)
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            print("🚀 [AutoPasteService] CGEvent Cmd+V dispatched.")
        }
        
        // Secondary fallback via AppleScript System Events for apps that block raw CGEvent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let scriptSource = "tell application \"System Events\" to keystroke \"v\" using command down"
            if let script = NSAppleScript(source: scriptSource) {
                var err: NSDictionary?
                script.executeAndReturnError(&err)
                if err == nil {
                    print("🚀 [AutoPasteService] AppleScript Cmd+V dispatched successfully.")
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
