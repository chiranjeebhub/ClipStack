import ClipboardCore
import SwiftUI

/// The dropdown under the menu bar icon: pinned items, recent items and app commands.
@MainActor
struct MenuBarContent: View {
    let environment: AppEnvironment

    private var pinned: [ClipItem] { Array(environment.store.items.filter(\.isPinned).prefix(9)) }
    private var recent: [ClipItem] { Array(environment.store.items.filter { !$0.isPinned }.prefix(9)) }

    var body: some View {
        if !pinned.isEmpty {
            Section("Pinned") {
                ForEach(Array(pinned.enumerated()), id: \.element.id) { index, item in
                    itemButton(item)
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)
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

        Button("Open Clipboard…") { environment.panel.show() }
            .keyboardShortcut(Preferences.hotKey.keyEquivalent, modifiers: Preferences.hotKey.eventModifiers)
        Button(environment.isPaused ? "Resume Recording" : "Pause Recording") {
            environment.isPaused.toggle()
        }
        Button("Clear History…") { environment.confirmClearHistory() }
            .disabled(environment.store.items.allSatisfy(\.isPinned))

        Divider()

        Button("Settings…") { AppDelegate.openSettings() }
            .keyboardShortcut(",", modifiers: .command)
        Button("Quit Clipboard") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private func itemButton(_ item: ClipItem) -> some View {
        Button {
            environment.paste(item)
        } label: {
            Text(Self.menuTitle(for: item))
        }
    }

    private static func menuTitle(for item: ClipItem) -> String {
        let title = item.title
        return title.count > 48 ? String(title.prefix(47)) + "…" : title
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
