import Foundation

@Observable
final class ProviderStore {
    private(set) var activeProviderID: ProviderID
    private(set) var storedProviderIDs: Set<ProviderID> = []

    init() {
        let raw = UserDefaults.standard.string(forKey: Keys.activeProvider)
        activeProviderID = ProviderID(rawValue: raw ?? "") ?? .openAI
        refreshStoredKeys()
    }

    func setActiveProvider(_ id: ProviderID) {
        activeProviderID = id
        UserDefaults.standard.set(id.rawValue, forKey: Keys.activeProvider)
    }

    func hasAPIKey(for id: ProviderID) -> Bool {
        storedProviderIDs.contains(id)
    }

    func storeAPIKey(_ key: String, for id: ProviderID) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try KeychainStore.delete(forKey: id.keychainKey)
        } else {
            try KeychainStore.store(trimmed, forKey: id.keychainKey)
        }
        refreshStoredKeys()
    }

    func clearAPIKey(for id: ProviderID) throws {
        try KeychainStore.delete(forKey: id.keychainKey)
        refreshStoredKeys()
    }

    func makeProvider(for id: ProviderID) -> (any AIProvider)? {
        guard let key = storedKey(for: id), !key.isEmpty else { return nil }
        switch id {
        case .openAI: return OpenAIProvider(apiKey: key)
        case .gemini: return GeminiProvider(apiKey: key)
        }
    }

    func makeActiveProvider() -> (any AIProvider)? {
        makeProvider(for: activeProviderID)
    }

    private func refreshStoredKeys() {
        storedProviderIDs = Set(ProviderID.allCases.filter { id in
            guard let key = storedKey(for: id) else { return false }
            return !key.isEmpty
        })
    }

    // Flattens the double-optional produced by `try?` on a throwing `String?`-returning function.
    private func storedKey(for id: ProviderID) -> String? {
        (try? KeychainStore.retrieve(forKey: id.keychainKey)).flatMap { $0 }
    }

    private enum Keys {
        static let activeProvider = "activeProviderID"
    }
}
