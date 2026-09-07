import AppKit
import Carbon
import ApplicationServices

@MainActor
public final class AutoPasteService {
    public static let shared = AutoPasteService()
    
    private var lastPasteTimestamp: Date = .distantPast
    
    private init() {}
    
    @discardableResult
    public func paste(text: String, targetApp: NSRunningApplication?) -> Bool {
        guard !text.isEmpty else { return false }
        
        let now = Date()
        guard now.timeIntervalSince(lastPasteTimestamp) > 0.3 else {
            print("⚠️ [AutoPasteService] Debounced duplicate paste call within \(now.timeIntervalSince(lastPasteTimestamp))s")
            return false
        }
        lastPasteTimestamp = now
        
        // 1. Always set text on system clipboard as guaranteed fallback
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("📋 [AutoPasteService] Set text in pasteboard (\(text.count) chars)")
        
        // 2. Resolve active target application
        let frontApp = NSWorkspace.shared.frontmostApplication
        let resolvedTarget: NSRunningApplication?
        if let front = frontApp, front.processIdentifier != NSRunningApplication.current.processIdentifier {
            resolvedTarget = front
        } else if let target = targetApp, target.processIdentifier != NSRunningApplication.current.processIdentifier {
            resolvedTarget = target
        } else {
            resolvedTarget = nil
        }
        
        // 3. Reactivate target application if it is currently in background
        let needsActivation = (resolvedTarget != nil && resolvedTarget?.isActive == false)
        if let target = resolvedTarget, needsActivation {
            target.activate()
        }
        
        // 4. Try direct Accessibility insertion first (instant 0ms, doesn't depend on key simulation)
        if tryDirectAccessibilityInsert(text: text) {
            return true
        }
        
        // 5. Fallback: Post simulated Cmd+V with settling delay
        let delay = needsActivation ? 0.16 : 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.dispatchCmdVKeystroke(targetApp: resolvedTarget)
        }
        
        return true
    }
    
    @discardableResult
    private func tryDirectAccessibilityInsert(text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElem: AnyObject?
        let copyStatus = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElem)
        guard copyStatus == .success, let element = focusedElem else {
            return false
        }
        // Direct replacement of selected text (standard insertion point in native & web views)
        let axElem = element as! AXUIElement
        let setStatus = AXUIElementSetAttributeValue(axElem, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        if setStatus == .success {
            print("✅ [AutoPasteService] Inserted directly via Accessibility API (0ms)")
            return true
        }
        return false
    }
    
    private func dispatchCmdVKeystroke(targetApp: NSRunningApplication?) {
        let vKeyCode: CGKeyCode = 0x09 // Virtual keycode for 'V'
        let source = CGEventSource(stateID: .combinedSessionState)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            print("⚠️ [AutoPasteService] Failed to create CGEvents")
            return
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        // 1. Post directly to target application PID if available
        if let pid = targetApp?.processIdentifier, pid != NSRunningApplication.current.processIdentifier {
            keyDown.postToPid(pid)
            usleep(20_000)
            keyUp.postToPid(pid)
            print("✅ [AutoPasteService] Cmd+V keystroke dispatched to PID \(pid) (\(targetApp?.localizedName ?? "Unknown")).")
        }
        
        // 2. Also post to .cghidEventTap to cover sub-windows and multi-process renderers (Electron/Chromium)
        keyDown.post(tap: .cghidEventTap)
        usleep(25_000)
        keyUp.post(tap: .cghidEventTap)
        
        print("✅ [AutoPasteService] Cmd+V keystroke dispatched via HID tap.")
    }
    
    public static func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
