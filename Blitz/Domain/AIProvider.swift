import Foundation

protocol AIProvider {
    var id: ProviderID { get }
    var displayName: String { get }
    func transform(text: String, instruction: String) async throws -> String
}

enum ProviderID: String, CaseIterable, Hashable {
    case openAI = "openai"
    case gemini = "gemini"

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        }
    }

    var keychainKey: String {
        "com.rashidhuseynov.Blitz.apiKey.\(rawValue)"
    }
}
