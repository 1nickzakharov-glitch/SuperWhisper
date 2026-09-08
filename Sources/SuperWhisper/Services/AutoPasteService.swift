import AppKit
import Carbon
import ApplicationServices

@MainActor
public final class AutoPasteService {
    public static let shared = AutoPasteService()
    
    private var lastPasteTimestamp: Date = .distantPast
    
    private var logFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SuperWhisper/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("paste.log")
    }
    
    private init() {}
    
    public func log(_ message: String) {
        let entry = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        print("📋 [AutoPasteService] \(message)")
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
    }
    
    @discardableResult
    public func paste(text: String, targetApp: NSRunningApplication?) -> Bool {
        guard !text.isEmpty else { return false }
        
        let now = Date()
        guard now.timeIntervalSince(lastPasteTimestamp) > 0.3 else {
            log("⚠️ Debounced duplicate paste call within \(now.timeIntervalSince(lastPasteTimestamp))s")
            return false
        }
        lastPasteTimestamp = now
        
        // 1. Always set text on system clipboard as the rock-solid baseline
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        log("Set text in pasteboard (\(text.count) chars)")
        
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
            log("Activated target app: \(target.localizedName ?? "Unknown") (PID: \(target.processIdentifier))")
        }
        
        // 4. Settling delay: 140ms if application needed activation, 80ms if already frontmost
        let delay = needsActivation ? 0.14 : 0.08
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.executePaste(targetApp: resolvedTarget)
        }
        
        return true
    }
    
    private func executePaste(targetApp: NSRunningApplication?) {
        log("Executing paste for: \(targetApp?.localizedName ?? "Unknown") (PID: \(targetApp?.processIdentifier ?? 0))")
        
        // 1. Primary engine: AppleScript System Events using hardware key code 9 (ANSI V)
        // Hardware key code 9 is 100% layout-independent (works seamlessly on RussianWin, English, etc.)
        // and universally delivered through WindowServer directly to Electron/Chromium renderers and terminals!
        let appleScriptSuccess = dispatchAppleScriptCmdV()
        
        // 2. Fallback engine: Canonical 4-step CGEvent sequence posted to both HID and Session taps
        if !appleScriptSuccess {
            log("AppleScript returned false, dispatching canonical CGEvent fallback...")
            dispatchCanonicalCmdV()
        }
    }
    
    /// Hardware-independent AppleScript System Events paste using physical key code 9 (kVK_ANSI_V).
    /// Unlike layout-dependent `keystroke "v"`, `key code 9` works on ALL keyboard layouts (Russian, English, etc.)
    @discardableResult
    public func dispatchAppleScriptCmdV() -> Bool {
        let scriptSource = "tell application \"System Events\" to key code 9 using command down"
        guard let script = NSAppleScript(source: scriptSource) else {
            log("Failed to create NSAppleScript")
            return false
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let err = errorInfo {
            log("⚠️ AppleScript key code 9 failed: \(err)")
            return false
        }
        log("✅ AppleScript System Events (key code 9 using command down) executed successfully.")
        return result.descriptorType != 0
    }
    
    /// Canonical 4-step CGEvent sequence: Command Down -> V Down -> V Up -> Command Up
    /// Dispatched to both .cghidEventTap and .cgSessionEventTap using clean .hidSystemState.
    @discardableResult
    public func dispatchCanonicalCmdV() -> Bool {
        let cmdKeyCode: CGKeyCode = 0x37 // Left Command
        let vKeyCode: CGKeyCode = 0x09   // 'V'
        
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            log("Failed to create CGEventSource")
            return false
        }
        
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false) else {
            log("Failed to create CGEvents")
            return false
        }
        
        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        cmdUp.flags = []
        
        // Post to both taps for full coverage
        cmdDown.post(tap: .cghidEventTap)
        cmdDown.post(tap: .cgSessionEventTap)
        usleep(15_000)
        
        vDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cgSessionEventTap)
        usleep(25_000)
        
        vUp.post(tap: .cghidEventTap)
        vUp.post(tap: .cgSessionEventTap)
        usleep(15_000)
        
        cmdUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cgSessionEventTap)
        
        log("✅ Canonical 4-step CGEvent Cmd+V dispatched to HID & Session taps.")
        return true
    }
    
    public static func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
