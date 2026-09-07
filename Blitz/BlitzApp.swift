import SwiftUI
import SwiftData

@main
struct BlitzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let sharedContainer: ModelContainer
    private let scenarioStore: ScenarioStore
    private let providerStore: ProviderStore
    private let previewSettings: PreviewSettings
    private let textService: AccessibilityTextService
    private let orchestrator: TransformationOrchestrator
    private let shortcutManager: GlobalShortcutManager
    private let overlayPresenter: BlitzOverlayPresenter

    init() {
        do {
            sharedContainer = try ModelContainer(for: Scenario.self)
        } catch {
            fatalError("SwiftData container failed to initialize: \(error)")
        }

        scenarioStore = ScenarioStore(modelContext: sharedContainer.mainContext)
        providerStore = ProviderStore()

        let settings = PreviewSettings()
        previewSettings = settings

        let service = AccessibilityTextService()
        textService = service
        orchestrator = TransformationOrchestrator(
            textSelectionService: service,
            textReplacementService: service,
            preferences: settings
        )

        shortcutManager = GlobalShortcutManager()

        let presenter = BlitzOverlayPresenter(
            orchestrator: orchestrator,
            providerStore: providerStore,
            scenarioStore: scenarioStore,
            modelContainer: sharedContainer
        )
        overlayPresenter = presenter

        // Open Settings from the overlay without SwiftUI's openSettings environment.
        presenter.setOpenSettings {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            BlitzApp.bringSettingsToFront()
        }

        // Give the AppDelegate access to the provider store so NSServices
        // handlers can reach the active provider without duplicating state.
        appDelegate.providerStore = providerStore

        // Wire the global shortcut → overlay. Capturing strongly is intentional;
        // both objects live for the app's lifetime and there is no retain cycle.
        shortcutManager.onActivate = {
            Task { @MainActor in
                // Capture the selection while the target app still holds keyboard
                // focus. Skip when the overlay is already visible — re-reading would
                // briefly activate the target app with no benefit.
                if !presenter.isVisible {
                    await service.preReadSelection()
                }
                let rect = service.getSelectionScreenRect()
                presenter.show(near: rect)
            }
        }
        shortcutManager.register()
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
            SettingsView(shortcutManager: shortcutManager)
                .environment(scenarioStore)
                .environment(providerStore)
                .environment(previewSettings)
        }
        .modelContainer(sharedContainer)
    }

    /// Activates Blitz and brings the Settings window to the front.
    ///
    /// Blitz runs as an accessory app (no Dock icon), so its windows open behind
    /// the frontmost application by default. The 50 ms delay gives SwiftUI time
    /// to create the window before we order it front.
    static func bringSettingsToFront() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.windows
                .filter { !($0 is NSPanel) && $0.canBecomeKey }
                .forEach {
                    $0.makeKeyAndOrderFront(nil)
                    $0.orderFrontRegardless()
                }
        }
    }
}
