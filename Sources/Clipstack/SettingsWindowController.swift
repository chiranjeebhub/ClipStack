import AppKit
import SwiftUI

/// Shows Settings in a window managed directly with AppKit. The SwiftUI `Settings` scene doesn't
/// reliably open from a menu bar app that has no Dock icon, so this replaces it.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let environment: AppEnvironment
    private var window: NSWindow?

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func show() {
        let window = self.window ?? makeWindow()
        // While Settings is open the app behaves like a regular app (Dock icon, ⌘-Tab), so
        // the window can come to the front and take focus. It goes back to the menu bar on close.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(environment: environment))
        hosting.sceneBridgingOptions = [.title, .toolbars]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Clipstack Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("ClipstackSettings")
        window.center()
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.returnToMenuBar(closing: notification.object as? NSWindow)
        ReviewPrompt.requestIfAppropriate()
    }
}

extension NSApplication {
    /// Drops the Dock icon again once the last of the app's ordinary windows (Settings, the welcome
    /// window) closes. Closing one while the other is open would otherwise leave that one without
    /// a Dock icon or ⌘-Tab entry.
    func returnToMenuBar(closing window: NSWindow?) {
        let othersOpen = windows.contains {
            $0 !== window && ($0.isVisible || $0.isMiniaturized) && !($0 is NSPanel) && $0.styleMask.contains(.titled)
        }
        if !othersOpen { setActivationPolicy(.accessory) }
    }
}
