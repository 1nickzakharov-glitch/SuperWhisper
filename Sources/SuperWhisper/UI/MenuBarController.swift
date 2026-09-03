import AppKit
import SwiftUI

@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let appState: AppState
    private var statusMenu: NSMenu!
    
    public init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "SuperWhisper")
            button.imagePosition = .imageLeft
        }
        
        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
    }
    
    public func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
    
    private func rebuildMenu() {
        statusMenu.removeAllItems()
        
        // 1. Title & Model Info
        let headerItem = NSMenuItem(title: "SuperWhisper", action: nil, keyEquivalent: "")
        headerItem.attributedTitle = NSAttributedString(
            string: "SuperWhisper • Large-v3-Turbo",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        statusMenu.addItem(headerItem)
        
        // 2. Engine Status
        let statusText = appState.isEngineReady ? "🟢 Модель готова" : "🟡 \(appState.engineStatusMessage)"
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        statusMenu.addItem(statusItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // 3. Hotkey Toggle Action
        let shortcutTitle = Preferences.shared.hotkeyPreset.shortTitle
        let toggleTitle: String
        switch appState.hudState {
        case .listening:
            toggleTitle = "🛑 Остановить диктовку"
        case .processing:
            toggleTitle = "⏳ Идёт распознавание..."
        default:
            toggleTitle = "🎙️ Начать диктовку (\(shortcutTitle))"
        }
        
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleDictation), keyEquivalent: "")
        toggleItem.target = self
        statusMenu.addItem(toggleItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // 4. Settings
        let settingsItem = NSMenuItem(title: "Настройки...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        statusMenu.addItem(settingsItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // 5. Permissions check
        let isAxGranted = AutoPasteService.checkAccessibilityPermissions(prompt: false)
        let axTitle = isAxGranted ? "✓ Универсальный доступ: разрешён" : "⚠️ Универсальный доступ: требуется для вставки"
        let axItem = NSMenuItem(title: axTitle, action: #selector(requestAccessibilityPermission), keyEquivalent: "")
        axItem.target = self
        statusMenu.addItem(axItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // 6. Quit
        let quitItem = NSMenuItem(title: "Завершить SuperWhisper", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }
    
    @objc private func toggleDictation() {
        appState.toggleRecording()
    }
    
    @objc private func openSettings() {
        SettingsWindowController.shared.showSettings()
    }
    
    @objc private func requestAccessibilityPermission() {
        _ = AutoPasteService.checkAccessibilityPermissions(prompt: true)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
