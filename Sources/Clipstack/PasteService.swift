import AppKit
import ApplicationServices
import ClipboardCore

/// Puts a history item back on the pasteboard and, when allowed, types ⌘V into the frontmost app.
@MainActor
final class PasteService {
    private let store: HistoryStore
    private let monitor: PasteboardMonitor

    init(store: HistoryStore, monitor: PasteboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    private static var didPromptForAccess = false

    // The post-event access check, unlike AXIsProcessTrusted, works inside the App Sandbox.
    // macOS lists it under Privacy & Security › Accessibility.
    nonisolated static var hasAccessibilityAccess: Bool { CGPreflightPostEventAccess() }

    /// macOS ties the permission to the app's signature, so after an update or reinstall the old
    /// entry can still show as switched on without applying to this copy.
    static let staleAccessHint = "Already on? Select Clipstack in the list, click −, then add it again or relaunch Clipstack."

    nonisolated static func requestAccessibilityAccess() {
        _ = CGRequestPostEventAccess()
    }

    nonisolated static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Copies the item to the clipboard.
    func copy(_ item: ClipItem, plainText: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .image:
            if let name = item.imageFile, let url = store.persistence?.imageURL(for: name), let image = NSImage(contentsOf: url) {
                pasteboard.writeObjects([image])
            }
        case .file:
            let urls = (item.fileURLs ?? []) as [NSURL]
            if plainText {
                pasteboard.setString((item.fileURLs ?? []).map(\.path).joined(separator: "\n"), forType: .string)
            } else {
                pasteboard.writeObjects(urls)
            }
        case .link:
            let text = item.text ?? ""
            if !plainText, let url = URL(string: text) {
                pasteboard.writeObjects([url as NSURL])
            }
            pasteboard.setString(text, forType: .string)
        case .text, .code, .color:
            let text = item.text ?? ""
            if !plainText, let rtf = item.rtf {
                pasteboard.declareTypes([.rtf, .string], owner: nil)
                pasteboard.setData(rtf, forType: .rtf)
            }
            pasteboard.setString(text, forType: .string)
        }
        // The monitor ignores this change, so the history keeps its order unless the user asked
        // for pasted items to move to the top.
        monitor.skipCurrentContents()
        if Preferences.moveToTopOnPaste { store.touch(id: item.id) }
        ReviewPrompt.recordUse()
    }

    /// Copies the item and, if the user allowed it, pastes it into `target` (or whichever app is frontmost).
    func paste(_ item: ClipItem, plainText: Bool, into target: NSRunningApplication?) {
        copy(item, plainText: plainText || Preferences.alwaysPlainText)
        guard Preferences.pasteDirectly else { return }
        guard Self.hasAccessibilityAccess else {
            // Without Accessibility access macOS drops the ⌘V keystroke, so the item is only copied.
            // Ask once per launch so a missing permission (e.g. after a reinstall) isn't silent.
            if !Self.didPromptForAccess {
                Self.didPromptForAccess = true
                Self.requestAccessibilityAccess()
            }
            return
        }
        if let target, target != NSRunningApplication.current, !target.isActive {
            target.activate()
        }
        // Give the target app a moment to become key before the keystroke arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.postCommandV()
        }
    }

    nonisolated private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
