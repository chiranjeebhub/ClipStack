import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A button that shows the global shortcut and records a new one when clicked.
@MainActor
struct HotKeyRecorder: View {
    let environment: AppEnvironment
    @State private var combo = Preferences.hotKey
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Type shortcut…" : combo.displayString)
                    .frame(minWidth: 90)
            }
            if combo != .default && !isRecording {
                Button {
                    save(.default)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset to ⇧ ⌘ V")
                .accessibilityLabel("Reset shortcut")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        environment.suspendHotKey(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
                return nil
            }
            let candidate = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
            // Require a modifier other than Shift so ordinary typing can't become the shortcut.
            guard !candidate.modifiers.subtracting(.shift).isEmpty, !Self.isReserved(candidate) else {
                NSSound.beep()
                return nil
            }
            save(candidate)
            return nil
        }
    }

    /// Standard editing shortcuts. Taking one system-wide would break it in every app, and ⌘V
    /// would also catch the keystroke Clipstack sends to paste.
    private static func isReserved(_ combo: KeyCombo) -> Bool {
        let keys = [kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z, kVK_ANSI_A, kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_S, kVK_Space, kVK_Tab]
        return combo.modifiers == .command && keys.contains(Int(combo.keyCode))
    }

    private func save(_ newCombo: KeyCombo) {
        combo = newCombo
        Preferences.hotKey = newCombo
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            environment.suspendHotKey(false)
        }
    }
}
