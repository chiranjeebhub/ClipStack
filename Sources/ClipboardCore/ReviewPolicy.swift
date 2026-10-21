import Foundation

/// Decides when to ask for an App Store rating: only after someone has used the app for a while,
/// and at most once per app version (macOS also caps how often the prompt actually appears).
public struct ReviewPolicy: Sendable {
    public var minimumDays: Int
    public var minimumUses: Int

    public init(minimumDays: Int = 7, minimumUses: Int = 20) {
        self.minimumDays = minimumDays
        self.minimumUses = minimumUses
    }

    public func shouldRequest(
        firstLaunch: Date,
        uses: Int,
        lastPromptedVersion: String?,
        currentVersion: String,
        now: Date = Date()
    ) -> Bool {
        guard lastPromptedVersion != currentVersion, uses >= minimumUses else { return false }
        return now.timeIntervalSince(firstLaunch) >= TimeInterval(minimumDays) * 86_400
    }
}
