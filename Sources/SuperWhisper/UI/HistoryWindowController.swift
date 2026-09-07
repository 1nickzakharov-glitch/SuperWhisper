import AppKit
import SwiftUI

@MainActor
public final class HistoryWindowController: NSWindowController {
    public static let shared = HistoryWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("SuperWhisper History", "История диктовок SuperWhisper")
        window.isReleasedWhenClosed = false
        window.center()
        
        let hostingView = NSHostingView(rootView: HistoryView())
        window.contentView = hostingView
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func showHistory() {
        guard let window = self.window else { return }
        window.contentView = NSHostingView(rootView: HistoryView())
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
