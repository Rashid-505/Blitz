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
        guard let key = (try? KeychainStore.retrieve(forKey: id.keychainKey)) ?? nil,
              !key.isEmpty else { return nil }
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
            let key = (try? KeychainStore.retrieve(forKey: id.keychainKey)) ?? nil
            return !(key?.isEmpty ?? true)
        })
    }

    private enum Keys {
        static let activeProvider = "activeProviderID"
    }
}
