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
        window.title = "Clipboard Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("ClipboardSettings")
        window.center()
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
