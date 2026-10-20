import AppKit
import ClipboardCore
import SwiftUI

@main
struct ClipstackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(PrefKey.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarContent(environment: appDelegate.environment)
                // macOS menus drop label icons unless asked to show them.
                .labelStyle(.titleAndIcon)
        } label: {
            Image(nsImage: StackIcon.menuBarGlyph())
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()
    private var onboarding: OnboardingWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Runs as a menu bar app with no Dock icon (also when started with `swift run`).
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = StackIcon.appIcon(size: 512)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.start()
        if CloudSync.isEntitled {
            // Lets CloudKit tell this Mac when another one changed the history.
            NSApp.registerForRemoteNotifications()
        }
        // Also show it again when auto-paste is on but Accessibility access is missing, which happens
        // after a reinstall or re-sign because macOS ties the permission to the app's signature.
        let firstLaunch = !UserDefaults.standard.bool(forKey: PrefKey.hasCompletedOnboarding)
        if firstLaunch || (Preferences.pasteDirectly && !PasteService.hasAccessibilityAccess) {
            showOnboarding()
        }
    }

    /// Launching the app again while it runs opens Settings, the way back if the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment.showSettings()
        return false
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController { [weak self] in
                UserDefaults.standard.set(true, forKey: PrefKey.hasCompletedOnboarding)
                self?.onboarding = nil
            }
        }
        onboarding?.show()
    }
}
