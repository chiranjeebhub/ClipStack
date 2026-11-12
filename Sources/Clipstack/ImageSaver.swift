import AppKit
import ClipboardCore
import UniformTypeIdentifiers

/// Saves an image from the history to a file the user picks.
@MainActor
enum ImageSaver {
    static func save(_ item: ClipItem, store: HistoryStore) {
        guard item.kind == .image, let name = item.imageFile,
              let source = store.persistence?.imageURL(for: name) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Clipstack Image \(fileDate.string(from: item.createdAt)).png"
        // Clipstack runs without a Dock icon, so it has to come forward for the save dialog to get focus.
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(contentsOf: source).write(to: url)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private static let fileDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()
}
