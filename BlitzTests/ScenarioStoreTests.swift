import Testing
import SwiftData
@testable import Blitz

@Suite("ScenarioStore")
struct ScenarioStoreTests {

    private func makeStore() throws -> (ScenarioStore, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Scenario.self, configurations: config)
        let context = container.mainContext
        let store = ScenarioStore(modelContext: context)
        return (store, context)
    }

    private func fetchAll(context: ModelContext) throws -> [Scenario] {
        let descriptor = FetchDescriptor<Scenario>(sortBy: [SortDescriptor(\.order)])
        return try context.fetch(descriptor)
    }

    @Test("Seeds built-in scenarios on first launch")
    func seedsBuiltIns() throws {
        let (_, context) = try makeStore()
        let builtIns = try fetchAll(context: context).filter(\.isBuiltIn)
        #expect(builtIns.count == BuiltInScenarios.all.count)
    }

    @Test("Built-in definitions contain exactly 5 entries with non-empty content")
    func builtInDefinitionsAreValid() {
        #expect(BuiltInScenarios.all.count == 5)
        for definition in BuiltInScenarios.all {
            #expect(!definition.name.isEmpty)
            #expect(!definition.instruction.isEmpty)
        }
    }

    @Test("Does not re-seed built-ins on subsequent ScenarioStore init")
    func noDoubleSeed() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Scenario.self, configurations: config)
        let context = container.mainContext
        _ = ScenarioStore(modelContext: context)
        _ = ScenarioStore(modelContext: context)
        let builtIns = try fetchAll(context: context).filter(\.isBuiltIn)
        #expect(builtIns.count == BuiltInScenarios.all.count)
    }

    @Test("Built-in scenarios are enabled by default")
    func builtInsEnabledByDefault() throws {
        let (_, context) = try makeStore()
        let builtIns = try fetchAll(context: context).filter(\.isBuiltIn)
        #expect(builtIns.allSatisfy(\.isEnabled))
    }

    @Test("addScenario appends with next order value and isBuiltIn false")
    func addScenario() throws {
        let (store, context) = try makeStore()
        let before = try fetchAll(context: context)
        store.addScenario(name: "Custom", instruction: "Do something custom.")
        let after = try fetchAll(context: context)
        #expect(after.count == before.count + 1)
        let added = try #require(after.last)
        #expect(added.name == "Custom")
        #expect(added.isBuiltIn == false)
        #expect(added.order == before.map(\.order).max()! + 1)
    }

    @Test("delete removes a custom scenario")
    func deleteCustomScenario() throws {
        let (store, context) = try makeStore()
        store.addScenario(name: "ToDelete", instruction: "Temporary.")
        let before = try fetchAll(context: context)
        let custom = try #require(before.first(where: { $0.name == "ToDelete" }))
        store.delete(custom)
        let after = try fetchAll(context: context)
        #expect(after.first(where: { $0.name == "ToDelete" }) == nil)
    }

    @Test("delete is a no-op for built-in scenarios")
    func deleteBuiltInIsGuarded() throws {
        let (store, context) = try makeStore()
        let all = try fetchAll(context: context)
        let builtIn = try #require(all.first(where: \.isBuiltIn))
        let builtInName = builtIn.name
        store.delete(builtIn)
        let after = try fetchAll(context: context)
        #expect(after.contains(where: { $0.name == builtInName }))
    }

    @Test("move reorders scenarios correctly")
    func moveScenario() throws {
        let (store, context) = try makeStore()
        let before = try fetchAll(context: context)
        let firstBefore = before[0].name
        let secondBefore = before[1].name
        store.move(from: IndexSet(integer: 0), to: 2, in: before)
        let after = try fetchAll(context: context)
        #expect(after[0].name == secondBefore)
        #expect(after[1].name == firstBefore)
    }

    @Test("reindex keeps order values contiguous after delete")
    func reindexAfterDelete() throws {
        let (store, context) = try makeStore()
        store.addScenario(name: "Extra", instruction: "Extra.")
        let before = try fetchAll(context: context)
        let extra = try #require(before.first(where: { $0.name == "Extra" }))
        store.delete(extra)
        let after = try fetchAll(context: context)
        for (index, scenario) in after.enumerated() {
            #expect(scenario.order == index)
        }
    }
}
