import AppKit
import Carbon

@MainActor
public final class HotkeyService {
    public static let shared = HotkeyService()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onHotkeyPressed: (@Sendable () -> Void)?
    private let hotKeySignature: OSType = 0x53505753 // 'SPWS'
    private let hotKeyIDValue: UInt32 = 1
    
    private init() {}
    
    @discardableResult
    public func registerGlobalHotkey(
        keyCode: UInt32 = UInt32(kVK_Space),
        modifiers: UInt32 = UInt32(optionKey),
        onPressed: @escaping @Sendable () -> Void
    ) -> Bool {
        self.onHotkeyPressed = onPressed
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                guard let userData = userData, let theEvent = theEvent else {
                    return OSStatus(eventNotHandledErr)
                }
                let hotkeyService = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    theEvent,
                    OSType(kEventParamDirectObject),
                    OSType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                // Only swallow our specific hotkey! Let all others pass through to nextHandler.
                if status == noErr && hotKeyID.signature == hotkeyService.hotKeySignature && hotKeyID.id == hotkeyService.hotKeyIDValue {
                    hotkeyService.onHotkeyPressed?()
                    return noErr
                }
                
                return CallNextEventHandler(nextHandler, theEvent)
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
        
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyIDValue)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if registerStatus == noErr {
            print("⌨️ [HotkeyService] Global hotkey registered successfully (⌥ Space).")
            return true
        } else {
            print("⚠️ [HotkeyService] Failed to register global hotkey, status: \(registerStatus)")
            return false
        }
    }
    
    public func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
