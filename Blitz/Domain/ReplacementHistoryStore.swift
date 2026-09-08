import SwiftData
import Foundation

/// Owns the "save replacement history" preference and all write operations against
/// `ReplacementEntry`. Views read entries directly via `@Query`; this store is
/// injected wherever writes are needed (orchestrator, settings view).
@Observable
final class ReplacementHistoryStore {
    var isHistoryEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isHistoryEnabled, forKey: Keys.historyEnabled)
        }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        if let stored = UserDefaults.standard.object(forKey: Keys.historyEnabled) as? Bool {
            isHistoryEnabled = stored
        } else {
            isHistoryEnabled = true
        }
        self.modelContext = modelContext
    }

    // MARK: - Write operations

    func record(scenarioName: String, original: String, result: String) {
        guard isHistoryEnabled else { return }
        let entry = ReplacementEntry(scenarioName: scenarioName, originalText: original, resultText: result)
        modelContext.insert(entry)
        try? modelContext.save()
    }

    func delete(_ entry: ReplacementEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
    }

    func clearAll() {
        try? modelContext.delete(model: ReplacementEntry.self)
        try? modelContext.save()
    }

    private enum Keys {
        static let historyEnabled = "blitz.history.enabled"
    }
}
