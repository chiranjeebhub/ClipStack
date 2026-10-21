import AppKit
import ClipboardCore
import StoreKit

/// Asks for an App Store rating with Apple's own prompt, once someone has relied on Clipstack for a
/// week (see `ReviewPolicy`). It's only tried when the user has just finished with Clipstack, such
/// as closing the panel without pasting or closing Settings, never mid-paste or at launch.
@MainActor
enum ReviewPrompt {
    /// Only App Store copies can be rated, so the direct download build never asks.
    static let isAvailable = !AppUpdates.isAvailable
    static let appStoreID = "6824931139"
    static let writeReviewURL = URL(string: "macappstore://apps.apple.com/app/id\(appStoreID)?action=write-review")!

    private static var defaults: UserDefaults { .standard }
    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Starts the one-week clock on the first launch.
    static func recordLaunch() {
        if defaults.object(forKey: PrefKey.firstLaunchDate) == nil {
            defaults.set(Date(), forKey: PrefKey.firstLaunchDate)
        }
    }

    /// Counts a paste or copy from history.
    static func recordUse() {
        defaults.set(defaults.integer(forKey: PrefKey.reviewUseCount) + 1, forKey: PrefKey.reviewUseCount)
    }

    static func requestIfAppropriate() {
        guard isAvailable, !DemoData.isEnabled, let firstLaunch = defaults.object(forKey: PrefKey.firstLaunchDate) as? Date else { return }
        let eligible = ReviewPolicy().shouldRequest(
            firstLaunch: firstLaunch,
            uses: defaults.integer(forKey: PrefKey.reviewUseCount),
            lastPromptedVersion: defaults.string(forKey: PrefKey.lastReviewPromptVersion),
            currentVersion: currentVersion
        )
        guard eligible else { return }
        defaults.set(currentVersion, forKey: PrefKey.lastReviewPromptVersion)
        // A short delay lets the panel or window finish closing first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            SKStoreReviewController.requestReview()
        }
    }

    /// Opens the app's App Store page on the "Write a Review" sheet.
    static func openWriteReview() {
        NSWorkspace.shared.open(writeReviewURL)
    }
}
