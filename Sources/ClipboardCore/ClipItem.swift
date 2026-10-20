import Foundation

/// What a clipboard entry holds. Drives the row icon, the preview and how it is pasted back.
public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text, link, code, image, file, color

    public var label: String {
        switch self {
        case .text: return "Text"
        case .link: return "Link"
        case .code: return "Code"
        case .image: return "Image"
        case .file: return "File"
        case .color: return "Color"
        }
    }
}

public struct ClipItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var kind: ClipKind
    /// Plain text for text, code, link and color items.
    public var text: String?
    /// Rich text copied alongside the plain text, pasted back unless plain text is requested.
    public var rtf: Data?
    /// File name of the stored PNG inside the history's image folder.
    public var imageFile: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var fileURLs: [URL]?
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var createdAt: Date
    /// Last time the item was copied again, pinned, unpinned or edited. Sync keeps the newest version.
    /// Optional so history saved before sync existed still decodes.
    public var modifiedAt: Date?
    public var isPinned: Bool
    /// Stable fingerprint of the content, used to collapse repeated copies into one entry.
    public var contentHash: String

    public init(
        id: UUID = UUID(),
        kind: ClipKind,
        text: String? = nil,
        rtf: Data? = nil,
        imageFile: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        fileURLs: [URL]? = nil,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil,
        isPinned: Bool = false,
        contentHash: String
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.rtf = rtf
        self.imageFile = imageFile
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.fileURLs = fileURLs
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isPinned = isPinned
        self.contentHash = contentHash
    }

    public var lastModified: Date { modifiedAt ?? createdAt }

    /// One-line summary shown in lists and menus.
    public var title: String {
        switch kind {
        case .image:
            if let w = imageWidth, let h = imageHeight { return "Image · \(w) × \(h)" }
            return "Image"
        case .file:
            let names = (fileURLs ?? []).map(\.lastPathComponent)
            if names.count > 1 { return "\(names[0]) and \(names.count - 1) more" }
            return names.first ?? "File"
        default:
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
            return String(firstLine ?? "").trimmingCharacters(in: .whitespaces)
        }
    }

    /// Short description of the content's size for the preview pane.
    public var sizeDescription: String {
        switch kind {
        case .image:
            if let w = imageWidth, let h = imageHeight { return "\(w) × \(h) pixels" }
            return "Image"
        case .file:
            let count = fileURLs?.count ?? 0
            return count == 1 ? "1 file" : "\(count) files"
        default:
            let value = text ?? ""
            let lines = value.split(separator: "\n", omittingEmptySubsequences: false).count
            let chars = value.count
            return lines > 1 ? "\(lines) lines · \(chars) characters" : "\(chars) characters"
        }
    }

    /// Text the search field matches against.
    var searchableText: String {
        var parts: [String] = [text ?? "", sourceAppName ?? ""]
        parts.append(contentsOf: (fileURLs ?? []).map(\.path))
        return parts.joined(separator: "\n")
    }
}
