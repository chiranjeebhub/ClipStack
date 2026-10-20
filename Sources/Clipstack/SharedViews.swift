import AppKit
import ClipboardCore
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Looks up and caches app icons by bundle identifier. Used from the main thread only.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// The source app's real icon, or a lettered placeholder when the app is no longer installed.
@MainActor
struct SourceAppIcon: View {
    let bundleID: String?
    let name: String?
    var size: CGFloat = 14

    var body: some View {
        if let icon = AppIcons.icon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(Color.secondary.opacity(0.5))
                .frame(width: size, height: size)
                .overlay(
                    Text(String((name ?? "?").prefix(1)))
                        .font(.system(size: size * 0.6, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
    }
}

/// The small square at the start of each row: kind symbol, color swatch, image thumbnail or file icon.
@MainActor
struct KindBadge: View {
    let item: ClipItem
    let store: HistoryStore
    var selected = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.white.opacity(0.2) : Color.primary.opacity(0.08))
            content
        }
        .frame(width: 28, height: 28)
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .color:
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: NSColor(hex: item.text ?? "") ?? .gray))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.3)))
                .frame(width: 16, height: 16)
        case .image:
            if let name = item.imageFile, let url = store.persistence?.imageURL(for: name), let image = Thumbnails.image(at: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo")
            }
        case .file:
            if let url = item.fileURLs?.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "doc")
            }
        default:
            Image(systemName: item.kind.symbolName)
                .font(.system(size: 13, weight: .medium))
        }
    }
}

enum Thumbnails {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(at url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

extension ClipKind {
    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        }
    }
}

extension ClipItem {
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    func relativeTime(now: Date) -> String {
        if now.timeIntervalSince(createdAt) < 60 { return "just now" }
        return Self.relativeFormatter.localizedString(for: createdAt, relativeTo: now)
    }
}
