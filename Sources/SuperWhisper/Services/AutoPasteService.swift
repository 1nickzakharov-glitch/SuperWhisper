import AppKit
import Carbon

@MainActor
public final class AutoPasteService {
    public static let shared = AutoPasteService()
    
    private init() {}
    
    public func paste(text: String, targetApp: NSRunningApplication?) -> Bool {
        guard !text.isEmpty else { return false }
        
        let pasteboard = NSPasteboard.general
        
        // 1. Snapshot existing clipboard data to restore later
        let previousItems: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.compactMap { item in
            var dict = [NSPasteboard.PasteboardType: Data]()
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict.isEmpty ? nil : dict
        } ?? []
        
        // 2. Put text on clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("📋 [AutoPasteService] Set \(text.count) chars on pasteboard.")
        
        // 3. Check accessibility permission
        let hasAccessibility = Self.checkAccessibilityPermissions(prompt: false)
        guard hasAccessibility else {
            print("⚠️ [AutoPasteService] Accessibility not granted. Text remains in clipboard for manual paste.")
            return false
        }
        
        // 4. Activate target application
        if let target = targetApp, target.processIdentifier != NSRunningApplication.current.processIdentifier {
            target.activate()
        }
        
        // 5. Post synthetic Cmd+V event
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.simulatePasteKeystroke()
            
            // 6. Restore original clipboard content after application has consumed it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if !previousItems.isEmpty {
                    pasteboard.clearContents()
                    for dict in previousItems {
                        let item = NSPasteboardItem()
                        for (type, data) in dict {
                            item.setData(data, forType: type)
                        }
                        pasteboard.writeObjects([item])
                    }
                    print("🔄 [AutoPasteService] Original clipboard restored.")
                }
            }
        }
        
        return true
    }
    
    private func simulatePasteKeystroke() {
        let vKeyCode: CGKeyCode = 0x09 // Virtual key code for 'V'
        
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("⚠️ [AutoPasteService] Cannot create CGEventSource.")
            return
        }
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            print("⚠️ [AutoPasteService] Cannot create CGEvent for Cmd+V.")
            return
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        print("🚀 [AutoPasteService] Synthesized Cmd+V event dispatched.")
    }
    
    public static func checkAccessibilityPermissions(prompt: Bool = false) -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
