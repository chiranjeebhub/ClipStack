import AppKit
import ClipboardCore
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, shortcuts, privacy, ignoredApps, storage, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .privacy: return "Privacy"
        case .ignoredApps: return "Ignored Apps"
        case .storage: return "Storage"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .shortcuts: return "keyboard.fill"
        case .privacy: return "lock.fill"
        case .ignoredApps: return "nosign"
        case .storage: return "internaldrive.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .shortcuts: return .indigo
        case .privacy: return .blue
        case .ignoredApps: return .orange
        case .storage: return .green
        case .about: return Color(white: 0.45)
        }
    }
}

@MainActor
struct SettingsView: View {
    let environment: AppEnvironment
    @State private var pane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5).fill(pane.tint))
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle((pane ?? .general).title)
        }
        .frame(width: 720, height: 500)
        .onAppear { NSApp.activate() }
    }

    @ViewBuilder private var detail: some View {
        switch pane ?? .general {
        case .general: GeneralPane(environment: environment)
        case .shortcuts: ShortcutsPane(environment: environment)
        case .privacy: PrivacyPane(environment: environment)
        case .ignoredApps: IgnoredAppsPane()
        case .storage: StoragePane(environment: environment)
        case .about: AboutPane()
        }
    }
}

@MainActor
private struct GeneralPane: View {
    let environment: AppEnvironment
    @AppStorage(PrefKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(PrefKey.pasteDirectly) private var pasteDirectly = true
    @AppStorage(PrefKey.alwaysPlainText) private var alwaysPlainText = false
    @AppStorage(PrefKey.panelPosition) private var panelPosition = PanelPosition.center.rawValue
    @AppStorage(PrefKey.retentionDays) private var retentionDays = Retention.month.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show icon in menu bar", isOn: $showMenuBarIcon)
                if !showMenuBarIcon {
                    Text("Open the app again from Finder or Spotlight to get back to Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Open clipboard panel") {
                    HotKeyRecorder(environment: environment)
                }
            }
            Section {
                Toggle(isOn: $pasteDirectly) {
                    Text("Paste directly into the active app")
                    Text("Otherwise the item is only copied to the clipboard")
                }
                Toggle("Always paste as plain text", isOn: $alwaysPlainText)
                Picker("Panel position", selection: $panelPosition) {
                    ForEach(PanelPosition.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section {
                Picker("Keep history for", selection: $retentionDays) {
                    ForEach(Retention.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } footer: {
                Text("Pinned items are always kept.")
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn’t change the login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

@MainActor
private struct ShortcutsPane: View {
    let environment: AppEnvironment

    private let panelShortcuts: [(String, String)] = [
        ("Move selection", "↑ ↓"),
        ("Paste selected item", "↩"),
        ("Paste as plain text", "⌥ ↩"),
        ("Quick paste item 1–9", "⌘ 1–9"),
        ("Pin or unpin", "⌘ P"),
        ("Edit text", "⌘ E"),
        ("Copy without pasting", "⌘ C"),
        ("Delete item", "⌘ ⌫"),
        ("Next / previous filter", "⇥ / ⇧ ⇥"),
        ("Close panel", "⎋"),
    ]

    var body: some View {
        Form {
            Section("Global") {
                LabeledContent("Open clipboard panel") {
                    HotKeyRecorder(environment: environment)
                }
            }
            Section("In the clipboard panel") {
                ForEach(panelShortcuts, id: \.0) { name, keys in
                    LabeledContent(name) {
                        Text(keys).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
private struct PrivacyPane: View {
    let environment: AppEnvironment
    @AppStorage(PrefKey.ignoreConcealed) private var ignoreConcealed = true
    @AppStorage(PrefKey.ignoreTransient) private var ignoreTransient = true
    @State private var trusted = PasteService.hasAccessibilityAccess
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var environment = environment
        Form {
            Section {
                Toggle(isOn: $ignoreConcealed) {
                    Text("Ignore passwords and concealed items")
                    Text("Skips anything password managers mark as private")
                }
                Toggle(isOn: $ignoreTransient) {
                    Text("Ignore temporary items")
                    Text("Skips content apps mark as transient or auto-generated")
                }
                Toggle("Pause recording", isOn: $environment.isPaused)
            }
            Section {
                LabeledContent {
                    if trusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            PasteService.requestAccessibilityAccess()
                            PasteService.openAccessibilitySettings()
                        }
                    }
                } label: {
                    Text("Accessibility access")
                    Text("Needed to paste directly into other apps")
                }
            } footer: {
                Text("Your clipboard history is stored only on this Mac and never leaves it.")
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted = PasteService.hasAccessibilityAccess }
    }
}

@MainActor
private struct IgnoredAppsPane: View {
    @State private var apps: [String] = Preferences.ignoredApps
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                List(selection: $selection) {
                    ForEach(apps, id: \.self) { bundleID in
                        HStack(spacing: 8) {
                            SourceAppIcon(bundleID: bundleID, name: bundleID, size: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(AppIcons.name(for: bundleID))
                                Text(bundleID).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(bundleID)
                    }
                }
                .frame(minHeight: 220)
                HStack {
                    Button { addApp() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add app")
                    Button { removeSelected() } label: { Image(systemName: "minus") }
                        .accessibilityLabel("Remove app")
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Nothing copied in these apps is saved")
            }
        }
        .formStyle(.grouped)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        for id in ids where !apps.contains(id) { apps.append(id) }
        Preferences.ignoredApps = apps
    }

    private func removeSelected() {
        guard let selection else { return }
        apps.removeAll { $0 == selection }
        Preferences.ignoredApps = apps
        self.selection = nil
    }
}

@MainActor
private struct StoragePane: View {
    let environment: AppEnvironment
    @AppStorage(PrefKey.maxItems) private var maxItems = 1000
    @AppStorage(PrefKey.iCloudSync) private var iCloudSync = true
    @State private var diskUsage: Int64 = 0

    var body: some View {
        let store = environment.store
        Form {
            Section {
                LabeledContent("Items", value: store.items.count.formatted())
                LabeledContent("Pinned", value: store.pinnedCount.formatted())
                LabeledContent("Space used", value: ByteCountFormatter.string(fromByteCount: diskUsage, countStyle: .file))
                Stepper(value: $maxItems, in: 100...10_000, step: 100) {
                    LabeledContent("Keep at most", value: "\(maxItems.formatted()) items")
                }
            } footer: {
                Text("Pinned items don’t count towards the limit.")
            }
            Section {
                Toggle(isOn: $iCloudSync) {
                    Text("Sync with iCloud")
                    Text("Your history and pinned items come back after a reinstall and appear on your other Macs.")
                }
                if iCloudSync {
                    LabeledContent("Status") {
                        HStack(spacing: 8) {
                            SyncStatusLabel(state: environment.syncStatus.state)
                            Button("Sync Now") { environment.syncNow() }
                                .disabled(environment.syncStatus.state == .syncing)
                        }
                    }
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text("Uses the Apple Account this Mac is signed into and stays in your private iCloud database. Passwords and items from ignored apps are never saved.")
            }
            Section {
                HStack {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([HistoryPersistence.defaultDirectory()])
                    }
                    Spacer()
                    Button("Clear History…", role: .destructive) {
                        environment.confirmClearHistory()
                        refresh()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onChange(of: store.items.count) { refresh() }
    }

    private func refresh() {
        environment.store.persistence?.flush()
        diskUsage = environment.store.persistence?.diskUsage() ?? 0
    }
}

@MainActor
private struct SyncStatusLabel: View {
    let state: CloudSyncStatus.State

    var body: some View {
        switch state {
        case .off:
            Text("Off").foregroundStyle(.secondary)
        case .unavailable(let reason):
            Label(reason, systemImage: "exclamationmark.icloud")
                .foregroundStyle(.orange)
                .lineLimit(2)
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Syncing…")
            }
        case .upToDate(let date):
            Label {
                Text("Up to date · \(date.formatted(date: .omitted, time: .shortened))")
            } icon: {
                Image(systemName: "checkmark.icloud")
            }
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "xmark.icloud")
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}

@MainActor
private struct AboutPane: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: StackIcon.appIcon(size: 128))
            Text("Clipstack").font(.title.bold())
            Text(version).foregroundStyle(.secondary)
            Text("Everything you copy, kept and searchable.")
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
