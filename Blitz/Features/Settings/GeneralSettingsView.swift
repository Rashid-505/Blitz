import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {

    let shortcutManager: GlobalShortcutManager
    @Environment(PreviewSettings.self) private var previewSettings

    @State private var isRecording = false
    @State private var keyMonitor: Any?
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        Form {
            Section {
                LabeledContent("Activation shortcut") {
                    shortcutRow
                }

                LabeledContent("Launch at login") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                // Revert the toggle if registration fails.
                                launchAtLogin = !enabled
                            }
                        }
                }

                LabeledContent("Preview before replacing") {
                    @Bindable var settings = previewSettings
                    Toggle("", isOn: $settings.isPreviewEnabled)
                        .labelsHidden()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { stopRecording() }
    }

    // MARK: - Shortcut row

    @ViewBuilder
    private var shortcutRow: some View {
        HStack(spacing: 8) {
            if isRecording {
                Text("Press shortcut…")
                    .foregroundStyle(.blue)
                    .font(.callout)
                Spacer()
                Button("Cancel") { stopRecording() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Text(shortcutManager.currentShortcut.displayString)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Change") { startRecording() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(minWidth: 180)
    }

    // MARK: - Recording

    private func startRecording() {
        isRecording = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels without changing the shortcut.
            if event.keyCode == 53 { // kVK_Escape
                stopRecording()
                return nil
            }
            if let shortcut = GlobalShortcutManager.Shortcut.from(event: event) {
                shortcutManager.update(shortcut: shortcut)
                stopRecording()
                return nil  // consume the event
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}

#Preview {
    GeneralSettingsView(shortcutManager: GlobalShortcutManager())
        .environment(PreviewSettings())
        .frame(width: 500, height: 320)
}
