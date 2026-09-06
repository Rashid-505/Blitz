import Foundation

protocol AIProvider {
    var id: ProviderID { get }
    var displayName: String { get }
    // nonisolated so callers outside the main actor (e.g. NSServices handler) can
    // call this without hopping to the main actor, which would deadlock when the
    // main thread is synchronously waiting for the result.
    nonisolated func transform(text: String, instruction: String) async throws -> String
}

struct ModelOption: Identifiable, Hashable {
    let id: String          // API-facing model identifier
    let displayName: String
}

enum ProviderID: String, CaseIterable, Hashable {
    case openAI = "openai"
    case gemini = "gemini"
    case apple  = "apple"

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .apple:  "Apple Intelligence"
        }
    }

    /// Whether this provider requires a user-supplied API key.
    var requiresAPIKey: Bool {
        switch self {
        case .openAI, .gemini: return true
        case .apple:           return false
        }
    }

    var keychainKey: String {
        "com.rashidhuseynov.Blitz.apiKey.\(rawValue)"
    }

    var defaultModelID: String {
        switch self {
        case .openAI: "gpt-4o-mini"
        case .gemini: "gemini-3.6-flash"
        case .apple:  "on-device"
        }
    }

    var availableModels: [ModelOption] {
        switch self {
        case .openAI:
            return [
                ModelOption(id: "gpt-4o-mini",  displayName: "GPT-4o mini"),
                ModelOption(id: "gpt-4o",        displayName: "GPT-4o"),
                ModelOption(id: "gpt-4.1-nano",  displayName: "GPT-4.1 nano"),
                ModelOption(id: "gpt-4.1-mini",  displayName: "GPT-4.1 mini"),
                ModelOption(id: "gpt-4.1",       displayName: "GPT-4.1"),
                ModelOption(id: "o4-mini",        displayName: "o4-mini"),
            ]
        case .gemini:
            return [
                ModelOption(id: "gemini-3.8-flash",       displayName: "Gemini 3.8 Flash (newest)"),
                ModelOption(id: "gemini-3.6-flash",       displayName: "Gemini 3.6 Flash"),
                ModelOption(id: "gemini-3.5-flash",       displayName: "Gemini 3.5 Flash"),
                ModelOption(id: "gemini-3.5-flash-lite",  displayName: "Gemini 3.5 Flash Lite"),
                ModelOption(id: "gemini-3.1-flash-lite",  displayName: "Gemini 3.1 Flash Lite (fastest)"),
            ]
        case .apple:
            return []
        }
    }
}
