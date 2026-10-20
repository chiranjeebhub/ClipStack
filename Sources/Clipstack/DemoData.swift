import AppKit
import ClipboardCore

/// Sample history for App Store screenshots. Launch with `-ScreenshotDemo` to use it: the app then
/// works from a separate, freshly seeded folder, doesn't record the clipboard and doesn't sync,
/// so the real history is never shown or changed.
enum DemoData {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-ScreenshotDemo")

    static var directory: URL {
        HistoryPersistence.defaultDirectory().deletingLastPathComponent()
            .appendingPathComponent("Clipstack Screenshot Demo", isDirectory: true)
    }

    /// Empties the demo folder, so every demo launch starts from the same sample items.
    static func resetDirectory() {
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor
    static func seed(_ store: HistoryStore) {
        let now = Date()
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func text(_ kind: ClipKind, _ value: String, _ app: (String, String), _ minutes: Double, pinned: Bool = false) -> ClipItem {
            ClipItem(
                kind: kind, text: value, sourceBundleID: app.0, sourceAppName: app.1,
                createdAt: ago(minutes), modifiedAt: ago(minutes), isPinned: pinned, contentHash: "text:" + value
            )
        }

        let safari = ("com.apple.Safari", "Safari")
        let notes = ("com.apple.Notes", "Notes")
        let mail = ("com.apple.mail", "Mail")
        let xcode = ("com.apple.dt.Xcode", "Xcode")
        let terminal = ("com.apple.Terminal", "Terminal")
        let messages = ("com.apple.MobileSMS", "Messages")
        let finder = ("com.apple.finder", "Finder")
        let preview = ("com.apple.Preview", "Preview")

        var items: [ClipItem] = [
            text(.text, "Thanks for the update! Let’s move the design review to Thursday at 3 pm so the whole team can join.", mail, 1),
            text(.link, "https://developer.apple.com/design/human-interface-guidelines/menus", safari, 4),
            text(.code, "func greet(_ name: String) -> String {\n    \"Hello, \\(name)!\"\n}", xcode, 9),
            text(.color, "#0A84FF", preview, 15),
            text(.text, "Flight BA 287 · Gate 23 · Boarding 14:10 · Seat 31A", messages, 22),
            text(.text, "Q4 launch checklist\n• Final copy review\n• Press kit to partners\n• App Store screenshots", notes, 38),
            text(.code, "git log --oneline --graph --decorate -20", terminal, 55),
            text(.link, "https://www.apple.com/macbook-pro/", safari, 70),
            text(.text, "1 Infinite Loop, Cupertino, CA 95014", notes, 120, pinned: true),
            text(.text, "Kind regards,\nAlex Morgan\nProduct Designer", mail, 300, pinned: true),
            text(.text, "+1 (555) 014-2290", messages, 600, pinned: true),
            text(.color, "#FF9F0A", preview, 900),
        ]

        let fileURL = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
        items.append(ClipItem(
            kind: .file, fileURLs: [fileURL], sourceBundleID: finder.0, sourceAppName: finder.1,
            createdAt: ago(46), modifiedAt: ago(46), contentHash: "file:" + fileURL.path
        ))

        if let png = sampleImagePNG(), let name = store.persistence?.storeImage(png) {
            items.append(ClipItem(
                kind: .image, imageFile: name, imageWidth: 1600, imageHeight: 1000,
                sourceBundleID: preview.0, sourceAppName: preview.1,
                createdAt: ago(30), modifiedAt: ago(30), contentHash: "image:demo"
            ))
        }

        store.applyRemote(items, deletedIDs: [])
    }

    /// A soft landscape gradient with the app icon, standing in for a copied photo.
    private static func sampleImagePNG() -> Data? {
        let width = 1600, height = 1000
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        NSGradient(colors: [
            NSColor(srgbRed: 0.98, green: 0.62, blue: 0.40, alpha: 1),
            NSColor(srgbRed: 0.86, green: 0.36, blue: 0.62, alpha: 1),
            NSColor(srgbRed: 0.30, green: 0.32, blue: 0.78, alpha: 1),
        ])?.draw(in: bounds, angle: -60)
        NSColor(white: 0, alpha: 0.18).setFill()
        let hills = NSBezierPath()
        hills.move(to: NSPoint(x: 0, y: 0))
        hills.line(to: NSPoint(x: 0, y: 320))
        hills.curve(to: NSPoint(x: 1600, y: 260), controlPoint1: NSPoint(x: 500, y: 520), controlPoint2: NSPoint(x: 1100, y: 120))
        hills.line(to: NSPoint(x: 1600, y: 0))
        hills.close()
        hills.fill()
        NSColor(white: 1, alpha: 0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: 1180, y: 640, width: 160, height: 160)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
