import AppKit
#if DIRECT_DISTRIBUTION
import Sparkle
#endif

/// Self-updating through Sparkle, in the direct download build only. The App Store build is
/// updated by the App Store, so there this does nothing and its menu items are hidden.
@MainActor
enum AppUpdates {
    #if DIRECT_DISTRIBUTION
    static let isAvailable = true
    private static var controller: SPUStandardUpdaterController?
    #else
    static let isAvailable = false
    #endif

    /// Starts Sparkle's scheduled checks. Sparkle asks for permission before the first automatic check.
    static func start() {
        #if DIRECT_DISTRIBUTION
        guard controller == nil, !DemoData.isEnabled else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
    }

    static func checkForUpdates() {
        #if DIRECT_DISTRIBUTION
        start()
        NSApp.activate()
        controller?.checkForUpdates(nil)
        #endif
    }
}
