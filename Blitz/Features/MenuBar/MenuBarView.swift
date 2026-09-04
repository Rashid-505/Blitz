import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Environment(ScenarioStore.self) private var scenarioStore
    @Environment(\.openSettings) private var openSettings
    @Environment(ProviderStore.self) private var providerStore
    @Environment(TransformationOrchestrator.self) private var orchestrator

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
            Text("Running \(name)...")
                .foregroundStyle(.secondary)
            Button("Cancel") { orchestrator.cancel() }
            Divider()
        case .failed(let error):
            Text(error.localizedDescription)
                .lineLimit(3)
                .foregroundStyle(.red)
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
}
