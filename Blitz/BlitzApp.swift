import SwiftUI
import SwiftData

@main
struct BlitzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let sharedContainer: ModelContainer
    private let scenarioStore: ScenarioStore
    private let providerStore: ProviderStore
    private let orchestrator: TransformationOrchestrator

    init() {
        do {
            sharedContainer = try ModelContainer(for: Scenario.self)
        } catch {
            fatalError("SwiftData container failed to initialize: \(error)")
        }
        scenarioStore = ScenarioStore(modelContext: sharedContainer.mainContext)
        providerStore = ProviderStore()
        let textService = AccessibilityTextService()
        orchestrator = TransformationOrchestrator(
            textSelectionService: textService,
            textReplacementService: textService
        )
    }

    var body: some Scene {
        MenuBarExtra("Blitz", systemImage: "bolt.fill") {
            MenuBarView()
                .environment(scenarioStore)
                .environment(providerStore)
                .environment(orchestrator)
        }
        .menuBarExtraStyle(.menu)
        .modelContainer(sharedContainer)

        Settings {
            SettingsView()
                .environment(scenarioStore)
                .environment(providerStore)
        }
        .modelContainer(sharedContainer)
    }
}
