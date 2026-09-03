import AppKit
import SwiftUI

@MainActor
public final class OverlayPanel: NSPanel {
    private var hostingView: NSHostingView<JarvisSiriHUDView>?
    
    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.statusWindow)))
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = false // Allows hover buttons and cancel/pause clicks!
        self.alphaValue = 0.0
    }
    
    public override var canBecomeKey: Bool { return false }
    public override var canBecomeMain: Bool { return false }
    
    public func setupHUD(appState: AppState) {
        let view = JarvisSiriHUDView(appState: appState)
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        self.contentView = hosting
        self.hostingView = hosting
    }
    
    public func showHUD() {
        repositionOnScreen()
        self.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }
    
    public func hideHUD(completion: (@Sendable @MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            MainActor.assumeIsolated {
                self.orderOut(nil)
                completion?()
            }
        })
    }
    
    public func repositionOnScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSPointInRect(mouseLocation, $0.frame) }) ?? NSScreen.main
        guard let screen = targetScreen else { return }
        
        let screenRect = screen.visibleFrame
        let width: CGFloat = 260
        let height: CGFloat = 70
        
        let x = screenRect.origin.x + (screenRect.width - width) / 2.0
        let y = screenRect.origin.y + 65.0
        
        self.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}
