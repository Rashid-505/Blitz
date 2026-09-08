import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Environment(ScenarioStore.self) private var scenarioStore
    @Environment(\.openSettings) private var openSettings
    @Environment(ProviderStore.self) private var providerStore
    @Environment(TransformationOrchestrator.self) private var orchestrator
    @Environment(UpdateChecker.self) private var updateChecker

    var body: some View {
        statusSection
        scenariosSection

        Divider()

        Button("Settings...") {
            openSettings()
            BlitzApp.bringSettingsToFront()
        }
        .keyboardShortcut(",")

        Button("About Blitz") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        }

        updateSection

        Divider()

        Button("Quit Blitz") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var statusSection: some View {
        switch orchestrator.state {
        case .idle:
            EmptyView()
        case .transforming(let name):
            Text("Running \(name)…")
                .foregroundStyle(.secondary)
            Button("Cancel") { orchestrator.cancel() }
            Divider()
        case .preview(let name, _, let result):
            // Revisions are overlay-only (a text field inside NSMenu is awkward).
            // The menu bar offers Replace / Retry / Cancel on the current result.
            let depthLabel = orchestrator.revisionDepth > 0
                ? "\(name) — Revision \(orchestrator.revisionDepth)"
                : "\(name) — Preview"
            Text(depthLabel)
                .foregroundStyle(.secondary)
            Text(result)
                .lineLimit(5)
                .font(.caption)
                .foregroundStyle(.primary)
            Button("Replace") { orchestrator.commit() }
            if orchestrator.canGoBack {
                Button("Undo Revision") { orchestrator.back() }
            }
            Button("Discard") { orchestrator.cancel() }
            Divider()
        case .failed(let error):
            Text(error.localizedDescription)
                .lineLimit(3)
                .foregroundStyle(.red)
            if orchestrator.state.isRetryable {
                Button("Retry") { orchestrator.retryLast() }
            }
            Button("Dismiss") { orchestrator.cancel() }
            Divider()
        }
    }

    @ViewBuilder
    private var scenariosSection: some View {
        let enabled = scenarioStore.enabledScenarios
        if enabled.isEmpty {
            Text("No scenarios enabled")
                .foregroundStyle(.secondary)
        } else {
            ForEach(enabled) { scenario in
                Button(scenario.name) {
                    triggerTransformation(for: scenario)
                }
                .disabled(orchestrator.state.isTransforming)
            }
        }
    }

    private func triggerTransformation(for scenario: Scenario) {
        guard let provider = providerStore.makeActiveProvider() else {
            openSettings()
            return
        }
        orchestrator.transform(with: scenario, provider: provider)
    }

    // MARK: - Update section

    @ViewBuilder
    private var updateSection: some View {
        switch updateChecker.state {
        case .idle, .upToDate:
            Button("Check for Updates…") {
                Task { await updateChecker.checkForUpdates() }
            }
        case .checking:
            Text("Checking for updates…")
                .foregroundStyle(.secondary)
        case .available(let release):
            Text("Blitz \(release.version) is available")
                .foregroundStyle(.secondary)
            Button("Download & Install") {
                Task { await updateChecker.downloadAndInstall(release) }
            }
            Button("View Release Notes…") {
                updateChecker.openReleasePage(release)
            }
        case .downloading(let progress):
            Text(progress < 1 ? "Downloading… \(Int(progress * 100))%" : "Installing…")
                .foregroundStyle(.secondary)
        case .error:
            Button("Check for Updates…") {
                Task { await updateChecker.checkForUpdates() }
            }
        }
    }
}
