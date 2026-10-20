import Foundation

/// The type filters shown at the top of the quick panel. Pinned is a separate toggle, so it
/// combines with any type ("pinned links").
public enum HistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all, text, links, images, files

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .links: return "Links"
        case .images: return "Images"
        case .files: return "Files"
        }
    }

    public func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return [.text, .code, .color].contains(item.kind)
        case .links: return item.kind == .link
        case .images: return item.kind == .image
        case .files: return item.kind == .file
        }
    }
}

/// How long unpinned items are kept. Pinned items are never removed automatically.
public enum Retention: Int, CaseIterable, Identifiable, Sendable {
    case day = 1
    case week = 7
    case month = 30
    case quarter = 90
    case forever = 0

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .day: return "1 day"
        case .week: return "7 days"
        case .month: return "30 days"
        case .quarter: return "90 days"
        case .forever: return "Forever"
        }
    }
}

public struct HistorySection: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public var title: String
    public var items: [ClipItem]

    /// Groups newest-first items into Today, Yesterday and Earlier.
    public static func group(_ items: [ClipItem], now: Date = Date(), calendar: Calendar = .current) -> [HistorySection] {
        var today: [ClipItem] = [], yesterday: [ClipItem] = [], earlier: [ClipItem] = []
        for item in items {
            if calendar.isDate(item.createdAt, inSameDayAs: now) {
                today.append(item)
            } else if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(item.createdAt, inSameDayAs: y) {
                yesterday.append(item)
            } else {
                earlier.append(item)
            }
        }
        return [("Today", today), ("Yesterday", yesterday), ("Earlier", earlier)]
            .filter { !$0.1.isEmpty }
            .map { HistorySection(title: $0.0, items: $0.1) }
    }
}
