import SwiftUI
import SwiftData

@Observable
final class ScenarioStore {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        seedBuiltInsIfNeeded()
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
        guard !scenario.isBuiltIn else { return }
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
    }

    private func seedBuiltInsIfNeeded() {
        let descriptor = FetchDescriptor<Scenario>(predicate: #Predicate { $0.isBuiltIn })
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        guard count == 0 else { return }

        for (index, definition) in BuiltInScenarios.all.enumerated() {
            modelContext.insert(Scenario(
                name: definition.name,
                instruction: definition.instruction,
                isEnabled: true,
                order: index,
                isBuiltIn: true
            ))
        }
        save()
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
