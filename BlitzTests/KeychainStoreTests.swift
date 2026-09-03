import Testing
@testable import Blitz

@Suite("KeychainStore")
struct KeychainStoreTests {

    @Test("Store and retrieve a value round-trips correctly")
    func storeAndRetrieve() throws {
        let key = "com.rashidhuseynov.Blitz.test.\(UUID().uuidString)"
        defer { try? KeychainStore.delete(forKey: key) }
        try KeychainStore.store("secret-value", forKey: key)
        let retrieved = try KeychainStore.retrieve(forKey: key)
        #expect(retrieved == "secret-value")
    }

    @Test("Retrieving a key that was never stored returns nil")
    func retrieveMissingKeyReturnsNil() throws {
        let key = "com.rashidhuseynov.Blitz.test.never-stored.\(UUID().uuidString)"
        let result = try KeychainStore.retrieve(forKey: key)
        #expect(result == nil)
    }

    @Test("Storing a second value for the same key overwrites the first")
    func overwriteExistingValue() throws {
        let key = "com.rashidhuseynov.Blitz.test.overwrite.\(UUID().uuidString)"
        defer { try? KeychainStore.delete(forKey: key) }
        try KeychainStore.store("first", forKey: key)
        try KeychainStore.store("second", forKey: key)
        let result = try KeychainStore.retrieve(forKey: key)
        #expect(result == "second")
    }

    @Test("Deleting a key makes it unretrievable")
    func deleteRemovesValue() throws {
        let key = "com.rashidhuseynov.Blitz.test.delete.\(UUID().uuidString)"
        try KeychainStore.store("to-delete", forKey: key)
        try KeychainStore.delete(forKey: key)
        let result = try KeychainStore.retrieve(forKey: key)
        #expect(result == nil)
    }

    @Test("Deleting a key that was never stored does not throw")
    func deleteNonExistentKeyIsNoop() throws {
        let key = "com.rashidhuseynov.Blitz.test.nonexistent.\(UUID().uuidString)"
        try KeychainStore.delete(forKey: key)
    }

    @Test("Stored values survive a round-trip through Data encoding")
    func unicodeValueRoundTrip() throws {
        let key = "com.rashidhuseynov.Blitz.test.unicode.\(UUID().uuidString)"
        defer { try? KeychainStore.delete(forKey: key) }
        let value = "sk-🔑-日本語-тест"
        try KeychainStore.store(value, forKey: key)
        let result = try KeychainStore.retrieve(forKey: key)
        #expect(result == value)
    }
}
