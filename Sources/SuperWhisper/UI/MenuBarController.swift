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
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "SuperWhisper")
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
        
        // Header
        let titleItem = NSMenuItem(title: "SuperWhisper", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        statusMenu.addItem(titleItem)
        
        // Status indicator (short, concise, no emoji)
        let statusStr = appState.isEngineReady ? "Готов к работе" : "Загрузка модели..."
        let statusItem = NSMenuItem(title: statusStr, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        statusMenu.addItem(statusItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Action: Start / Stop Dictation
        let actionTitle: String
        switch appState.hudState {
        case .listening:
            actionTitle = "Остановить запись"
        case .processing:
            actionTitle = "Распознавание речи..."
        default:
            actionTitle = "Начать диктовку"
        }
        
        let toggleItem = NSMenuItem(title: actionTitle, action: #selector(toggleDictation), keyEquivalent: "")
        toggleItem.target = self
        statusMenu.addItem(toggleItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(title: "Настройки...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        statusMenu.addItem(settingsItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Завершить", action: #selector(quitApp), keyEquivalent: "q")
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
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
