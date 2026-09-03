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
    
    private init() {
        NotificationCenter.default.addObserver(
            forName: .hotkeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadCurrentHotkey()
            }
        }
    }
    
    public func startListening(onPressed: @escaping @Sendable () -> Void) {
        self.onHotkeyPressed = onPressed
        reloadCurrentHotkey()
    }
    
    public func reloadCurrentHotkey() {
        let preset = Preferences.shared.hotkeyPreset
        registerGlobalHotkey(keyCode: preset.keyCode, modifiers: preset.modifiers)
    }
    
    @discardableResult
    public func registerGlobalHotkey(
        keyCode: UInt32,
        modifiers: UInt32
    ) -> Bool {
        // Unregister previous hotkey if any
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            self.hotKeyRef = nil
        }
        
        if eventHandler == nil {
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
        }
        
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
            print("⌨️ [HotkeyService] Global hotkey registered successfully (preset: \(Preferences.shared.hotkeyPreset.title)).")
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
