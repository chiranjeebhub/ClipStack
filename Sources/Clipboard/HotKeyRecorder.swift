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
            guard !candidate.modifiers.subtracting(.shift).isEmpty else {
                NSSound.beep()
                return nil
            }
            save(candidate)
            return nil
        }
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
