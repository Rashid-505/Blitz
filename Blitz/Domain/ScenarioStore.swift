import SwiftUI
import SwiftData

@Observable
final class ScenarioStore {
    /// Scenarios ordered by `order`, kept in sync with the model context.
    ///
    /// Views read this instead of `@Query`: the menu bar and the overlay are
    /// hosted outside the app's window scene, where a `@Query` does not observe
    /// the context reliably and can render an empty list after launch.
    private(set) var scenarios: [Scenario] = []

    private let modelContext: ModelContext
    private var saveObserver: NSObjectProtocol?

    var enabledScenarios: [Scenario] {
        scenarios.filter(\.isEnabled)
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        seedBuiltInsIfNeeded()
        refresh()

        // Toggling a scenario in Settings saves through the environment's
        // context, so refresh whenever any save lands.
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
        }
    }

    func refresh() {
        scenarios = fetchAll()
    }

    func addScenario(name: String, instruction: String) {
        let maxOrder = fetchAll().map(\.order).max() ?? -1
        let scenario = Scenario(
            name: name,
            instruction: instruction,
            order: maxOrder + 1,
            isBuiltIn: false
        )
        modelContext.insert(scenario)
        save()
    }

    func delete(_ scenario: Scenario) {
        modelContext.delete(scenario)
        save()
        reindexOrders()
    }

    func move(from source: IndexSet, to destination: Int, in scenarios: [Scenario]) {
        var reordered = scenarios
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, scenario) in reordered.enumerated() {
            scenario.order = index
        }
        save()
    }

    func save() {
        try? modelContext.save()
        refresh()
    }

    private func seedBuiltInsIfNeeded() {
        let existing = fetchAll()
        let existingNames = Set(existing.map(\.name))
        var nextOrder = (existing.map(\.order).max() ?? -1) + 1

        var didInsert = false
        for definition in BuiltInScenarios.all where !existingNames.contains(definition.name) {
            modelContext.insert(Scenario(
                name: definition.name,
                instruction: definition.instruction,
                isEnabled: true,
                order: nextOrder,
                isBuiltIn: true
            ))
            nextOrder += 1
            didInsert = true
        }

        if didInsert {
            save()
        }
    }

    private func fetchAll() -> [Scenario] {
        let descriptor = FetchDescriptor<Scenario>(sortBy: [SortDescriptor(\.order)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func reindexOrders() {
        let all = fetchAll()
        for (index, scenario) in all.enumerated() {
            scenario.order = index
        }
        save()
    }
}
