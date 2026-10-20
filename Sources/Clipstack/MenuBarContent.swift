import ClipboardCore
import SwiftUI

/// The dropdown under the menu bar icon: pinned items, recent items and app commands.
@MainActor
struct MenuBarContent: View {
    let environment: AppEnvironment

    private var allPinned: [ClipItem] { environment.store.items.filter(\.isPinned) }
    private var pinned: [ClipItem] { Array(allPinned.prefix(9)) }
    private var recent: [ClipItem] { Array(environment.store.items.filter { !$0.isPinned }.prefix(9)) }

    var body: some View {
        if !pinned.isEmpty {
            let total = allPinned.count
            Section(total > pinned.count ? "Pinned · \(total)" : "Pinned") {
                ForEach(Array(pinned.enumerated()), id: \.element.id) { index, item in
                    itemButton(item)
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)
                }
                // The menu shows the first nine; the rest live in the panel, where they can be searched.
                if total > pinned.count {
                    Button("Show All \(total) Pinned…") { environment.panel.showPinned() }
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                }
            }
        }

        Section("Recent") {
            if recent.isEmpty {
                Text("Nothing copied yet")
            }
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, item in
                itemButton(item)
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }

        Divider()

        Button { environment.panel.show() } label: {
            Label("Open Clipstack…", systemImage: "list.clipboard")
        }
        .keyboardShortcut(Preferences.hotKey.keyEquivalent, modifiers: Preferences.hotKey.eventModifiers)
        Button { environment.isPaused.toggle() } label: {
            Label(
                environment.isPaused ? "Resume Recording" : "Pause Recording",
                systemImage: environment.isPaused ? "play.circle" : "pause.circle"
            )
        }
        Button { environment.confirmClearHistory() } label: {
            Label("Clear History…", systemImage: "trash")
        }
        .disabled(environment.store.items.allSatisfy(\.isPinned))

        Divider()

        Button { environment.showSettings() } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)
        Button { ReviewPrompt.openWriteReview() } label: {
            Label("Rate Clipstack…", systemImage: "star")
        }
        Button { NSApp.terminate(nil) } label: {
            Label("Quit Clipstack", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func itemButton(_ item: ClipItem) -> some View {
        Button {
            environment.paste(item)
        } label: {
            Label {
                Text(Self.menuTitle(for: item))
            } icon: {
                Image(nsImage: MenuIcons.icon(for: item, store: environment.store))
            }
        }
    }

    private static func menuTitle(for item: ClipItem) -> String {
        let title = item.title
        return title.count > 48 ? String(title.prefix(47)) + "…" : title
    }
}

/// 16-pt images for menu rows: an image clip's thumbnail, a color's swatch, otherwise the source
/// app's icon (or the kind's symbol when the app is unknown). Menus draw images at their own size,
/// so each one is redrawn into a 16 × 16 image.
@MainActor
enum MenuIcons {
    private static let side: CGFloat = 16
    private static var appCache: [String: NSImage] = [:]

    static func icon(for item: ClipItem, store: HistoryStore) -> NSImage {
        switch item.kind {
        case .image:
            if let name = item.imageFile, let url = store.persistence?.imageURL(for: name), let image = Thumbnails.image(at: url) {
                return draw { rect in
                    NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).addClip()
                    image.draw(in: aspectFill(image.size, in: rect))
                }
            }
        case .color:
            if let color = NSColor(hex: item.text ?? "") {
                return draw { rect in
                    let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3.5, yRadius: 3.5)
                    color.setFill()
                    path.fill()
                    NSColor.white.withAlphaComponent(0.35).setStroke()
                    path.lineWidth = 0.5
                    path.stroke()
                }
            }
        default:
            break
        }
        if let bundleID = item.sourceBundleID {
            if let cached = appCache[bundleID] { return cached }
            if let app = AppIcons.icon(for: bundleID) {
                let icon = draw { rect in app.draw(in: rect) }
                appCache[bundleID] = icon
                return icon
            }
        }
        let symbol = NSImage(systemSymbolName: item.kind.symbolName, accessibilityDescription: nil) ?? NSImage()
        symbol.isTemplate = true
        return symbol
    }

    private static func draw(_ body: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            body(rect)
            return true
        }
    }

    private static func aspectFill(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }
}

extension KeyCombo {
    /// Best-effort conversion for showing the shortcut in a SwiftUI menu.
    var keyEquivalent: KeyEquivalent {
        let name = Self.keyName(for: keyCode)
        if name.count == 1, let character = name.lowercased().first { return KeyEquivalent(character) }
        if name == "Space" { return .space }
        return KeyEquivalent("v")
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}
