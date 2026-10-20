# Clipboard

A native macOS clipboard manager, built with SwiftUI and AppKit. It keeps everything you copy and lets you search it and paste it back from the keyboard.

## Features

- **Quick panel (⇧⌘V).** Opens a floating panel over whatever app you're in, without taking focus from it. Search as you type, filter by Text, Links, Images, Files or Pinned, and paste with ↩. ⌥↩ pastes as plain text, and ⌘1–9 pastes one of the top nine items straight away.
- **Source apps.** Every item records the app it was copied from, and the list shows that app's icon and name.
- **Rich previews.** Text, code (monospaced), links, images, files and colors each get their own preview. You can edit text items in place with ⌘E.
- **Pinning.** ⌘P pins an item. Pinned items are never removed by the history limits, and they appear at the top of the menu bar menu with ⌥1–9 shortcuts.
- **Menu bar menu.** Pinned and recent items, Pause Recording, Clear History and Settings.
- **Privacy.** Items that password managers mark as concealed or transient are skipped, and you can list apps whose copies are never saved. History stays on your Mac in `~/Library/Application Support/Clipboard`.
- **Settings.** Launch at login, a custom global shortcut, paste behaviour, panel position, how long history is kept and the maximum number of items.

## Requirements

macOS 14 Sonoma or later. Building needs Xcode 15 or later.

## Build and run

```sh
scripts/build-app.sh
open build/Clipboard.app
```

To try changes quickly without bundling, run `swift run Clipboard`. Launch at login and the app icon only work in the bundled app.

Run the tests with `swift test`.

On first launch, the app asks for Accessibility access. macOS requires this before an app can type ⌘V into other apps. Without it, choosing an item copies it to the clipboard and you paste it yourself.

## Project layout

| Path | What's there |
| --- | --- |
| `Sources/ClipboardCore` | History model, storage, search and filters, content detection, and the drawn app icon. Covered by tests. |
| `Sources/Clipboard` | The app: pasteboard monitor, global shortcut, paste service, quick panel, menu bar menu, Settings and onboarding. |
| `Sources/MakeIcon` | Renders the app icon to an `.iconset` during the build. |
| `scripts/build-app.sh` | Builds and assembles `Clipboard.app`. |
