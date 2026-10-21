import AppKit
import ClipboardCore
import SwiftUI

/// A floating panel that takes keyboard focus without activating the app,
/// so the app you were typing in stays frontmost and receives the paste.
final class QuickPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 560),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        minSize = NSSize(width: 720, height: 420)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
final class QuickPanelController {
    private unowned let environment: AppEnvironment
    let model: QuickPanelModel
    private var panel: QuickPanel?
    private var keyMonitor: Any?
    /// The app that was frontmost when the panel opened; the paste goes there.
    private var targetApp: NSRunningApplication?
    /// Set when the panel closes because an item was pasted or copied, so the rating prompt
    /// doesn't appear over the app the user is pasting into.
    private var closingAfterUse = false

    init(environment: AppEnvironment) {
        self.environment = environment
        model = QuickPanelModel(store: environment.store)
        model.onPaste = { [weak self] item, plainText in self?.paste(item, plainText: plainText) }
        model.onCopy = { [weak self] item in
            self?.environment.pasteService.copy(item, plainText: false)
            self?.closingAfterUse = true
            self?.hide()
        }
        model.onClose = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        targetApp = NSWorkspace.shared.frontmostApplication
        let panel = self.panel ?? makePanel()
        model.prepareForShowing()
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        environment.refreshFromCloud()
    }

    /// Opens the panel with only pinned items showing.
    func showPinned() {
        show()
        model.pinnedOnly = true
    }

    func hide() {
        removeKeyMonitor()
        guard isVisible else { return }
        // Read the flag first: ordering out resigns key, which calls back into `hide()`.
        let afterUse = closingAfterUse
        closingAfterUse = false
        panel?.orderOut(nil)
        if !afterUse { ReviewPrompt.requestIfAppropriate() }
    }

    private func makePanel() -> QuickPanel {
        let panel = QuickPanel()
        panel.contentView = NSHostingView(rootView: QuickPanelView(model: model))
        panel.onResignKey = { [weak self] in self?.hide() }
        self.panel = panel
        return panel
    }

    private func position(_ panel: QuickPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var frame = panel.frame
        switch Preferences.panelPosition {
        case .center:
            frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2 + visible.height * 0.08)
        case .mouse:
            frame.origin = NSPoint(x: mouse.x - frame.width / 2, y: mouse.y - frame.height - 12)
        }
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        panel.setFrame(frame, display: false)
    }

    private func paste(_ item: ClipItem, plainText: Bool) {
        closingAfterUse = true
        hide()
        environment.pasteService.paste(item, plainText: plainText, into: targetApp)
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.model.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
