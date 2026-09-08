import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {

    let shortcutManager: GlobalShortcutManager
    @Environment(PreviewSettings.self) private var previewSettings
    @Environment(UpdateChecker.self) private var updateChecker

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

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                LabeledContent("Updates") {
                    updateRow
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { stopRecording() }
    }

    // MARK: - Update row

    @ViewBuilder
    private var updateRow: some View {
        switch updateChecker.state {
        case .idle:
            Button("Check for Updates") {
                Task { await updateChecker.checkForUpdates() }
            }
            .controlSize(.small)

        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            }

        case .upToDate:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Up to date")
                    .foregroundStyle(.secondary)
                Button("Check Again") {
                    Task { await updateChecker.checkForUpdates() }
                }
                .controlSize(.small)
            }

        case .available(let release):
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(release.version) available")
                        .fontWeight(.medium)
                }
                Spacer()
                Button("View Notes") {
                    updateChecker.openReleasePage(release)
                }
                .controlSize(.small)
                Button("Install") {
                    Task { await updateChecker.downloadAndInstall(release) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

        case .downloading(let progress):
            HStack(spacing: 6) {
                if progress < 1 {
                    ProgressView(value: progress)
                        .frame(maxWidth: 120)
                    Text("\(Int(progress * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                    Text("Installing…").foregroundStyle(.secondary)
                }
            }

        case .error(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Retry") {
                    Task { await updateChecker.checkForUpdates() }
                }
                .controlSize(.small)
            }
        }
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
