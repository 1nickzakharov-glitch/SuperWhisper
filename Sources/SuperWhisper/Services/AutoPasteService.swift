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
        
        // 1. Always set text on system clipboard as the rock-solid baseline
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
        
        // 4. Settling delay: 150ms if application needed activation, 60ms if already frontmost
        let delay = needsActivation ? 0.15 : 0.06
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.executePaste(targetApp: resolvedTarget)
        }
        
        return true
    }
    
    private func executePaste(targetApp: NSRunningApplication?) {
        let isElectron = isElectronOrChromiumApp(targetApp)
        print("🎯 [AutoPasteService] Executing paste for: \(targetApp?.localizedName ?? "Unknown") (isElectron: \(isElectron))")
        
        if isElectron {
            // For Electron / Chromium apps (Orca, Cursor, VS Code, Chrome, Slack, Telegram):
            // AppleScript System Events is the gold standard because it synthesizes events
            // directly through WindowServer with full routing to child renderer processes.
            let success = dispatchAppleScriptCmdV()
            if !success {
                print("⚠️ [AutoPasteService] AppleScript failed, falling back to canonical CGEvent...")
                dispatchCanonicalCmdV()
            }
        } else {
            // For native AppKit / Cocoa / SwiftUI apps:
            // Canonical 4-step CGEvent sequence is instantaneous and native
            let success = dispatchCanonicalCmdV()
            if !success {
                print("⚠️ [AutoPasteService] CGEvent failed, falling back to AppleScript...")
                dispatchAppleScriptCmdV()
            }
        }
    }
    
    private func isElectronOrChromiumApp(_ app: NSRunningApplication?) -> Bool {
        guard let bundleId = app?.bundleIdentifier?.lowercased() else { return true }
        let electronIdentifiers = [
            "orca", "code", "cursor", "slack", "electron", "chrome", "telegram",
            "discord", "obsidian", "figma", "notion", "brave", "edge", "arc"
        ]
        return electronIdentifiers.contains { bundleId.contains($0) }
    }
    
    /// Canonical 4-step CGEvent sequence: Command Down -> V Down -> V Up -> Command Up
    /// This mirrors authentic physical keyboard hardware events and satisfies Chromium/Electron's
    /// internal modifier state machine.
    @discardableResult
    private func dispatchCanonicalCmdV() -> Bool {
        let cmdKeyCode: CGKeyCode = 0x37 // Left Command
        let vKeyCode: CGKeyCode = 0x09   // 'V'
        
        // Use clean .hidSystemState to avoid contamination with physically held keys
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return false
        }
        
        // 1. Command Down (flagsChanged with .maskCommand)
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true) else {
            return false
        }
        cmdDown.flags = .maskCommand
        
        // 2. 'V' Down (keyDown with .maskCommand)
        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            return false
        }
        vDown.flags = .maskCommand
        
        // 3. 'V' Up (keyUp with .maskCommand)
        guard let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return false
        }
        vUp.flags = .maskCommand
        
        // 4. Command Up (flagsChanged with empty flags)
        guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false) else {
            return false
        }
        cmdUp.flags = []
        
        // Post sequence to .cgSessionEventTap
        cmdDown.post(tap: .cgSessionEventTap)
        usleep(15_000)
        vDown.post(tap: .cgSessionEventTap)
        usleep(25_000)
        vUp.post(tap: .cgSessionEventTap)
        usleep(15_000)
        cmdUp.post(tap: .cgSessionEventTap)
        
        print("✅ [AutoPasteService] Canonical 4-step CGEvent Cmd+V dispatched to session.")
        return true
    }
    
    /// AppleScript System Events keystroke: universal fallback recognized by every macOS framework
    @discardableResult
    public func dispatchAppleScriptCmdV() -> Bool {
        let scriptSource = "tell application \"System Events\" to keystroke \"v\" using command down"
        guard let script = NSAppleScript(source: scriptSource) else { return false }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let err = errorInfo {
            print("⚠️ [AutoPasteService] AppleScript paste failed: \(err)")
            return false
        }
        print("✅ [AutoPasteService] AppleScript System Events Cmd+V executed successfully.")
        return result.descriptorType != 0
    }
    
    public static func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
