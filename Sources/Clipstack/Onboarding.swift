import AppKit
import ClipboardCore
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: OnboardingView.height),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: OnboardingView { [weak self] in self?.window?.close() })
            window.center()
            self.window = window
        }
        // A menu bar app launched for the first time isn't frontmost, and macOS may decline a polite
        // activation request, so become a regular app while onboarding is open and force the window up.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onFinish()
    }
}

@MainActor
struct OnboardingView: View {
    let close: () -> Void
    @State private var trusted = PasteService.hasAccessibilityAccess
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(PrefKey.iCloudSync) private var iCloudSync = false
    private static let showsSyncStep = CloudSync.isEntitled
    static var height: CGFloat { showsSyncStep ? 590 : 520 }
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: StackIcon.appIcon(size: 112))
                .padding(.top, 24)
            Text("Welcome to Clipstack")
                .font(.system(size: 22, weight: .bold))
            Text("Everything you copy, kept and searchable. Press \(Preferences.hotKey.displayString.replacingOccurrences(of: " ", with: "")) anywhere to bring it back.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            VStack(spacing: 8) {
                StepRow(number: 1, done: true, title: "Record clipboard history", subtitle: "Stored on this Mac") {
                    EmptyView()
                }
                StepRow(number: 2, done: trusted, title: "Allow Accessibility access", subtitle: "Lets Clipstack paste straight into the app you’re using") {
                    if !trusted {
                        Button("Open Settings") {
                            PasteService.requestAccessibilityAccess()
                            PasteService.openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                StepRow(number: 3, done: launchAtLogin, title: "Launch at login", subtitle: "So your history never has gaps") {
                    if !launchAtLogin {
                        Button("Turn On") {
                            try? SMAppService.mainApp.register()
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                        .controlSize(.small)
                    }
                }
                if Self.showsSyncStep {
                    StepRow(number: 4, done: iCloudSync, title: "Sync with iCloud", subtitle: "Restores your history, pins and settings after a reinstall or on another Mac") {
                        if !iCloudSync {
                            Button("Turn On") { iCloudSync = true }
                                .controlSize(.small)
                        }
                    }
                }
            }
            .padding(.top, 6)

            Spacer()

            HStack {
                Spacer()
                Button("Skip", action: close)
                Button("Continue", action: close)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(width: 520, height: Self.height)
        .onReceive(timer) { _ in trusted = PasteService.hasAccessibilityAccess }
    }
}

@MainActor
private struct StepRow<Accessory: View>: View {
    let number: Int
    let done: Bool
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if done {
                    Circle().fill(Color.green)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 24, height: 24)
            .accessibilityLabel(done ? "Done" : "Step \(number)")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
    }
}
