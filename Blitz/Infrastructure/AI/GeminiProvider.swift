import Foundation

final class GeminiProvider: AIProvider {
    let id = ProviderID.gemini
    let displayName = "Google Gemini"

    static let defaultModel = "gemini-2.0-flash"

    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(apiKey: String, model: String = defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    nonisolated func transform(text: String, instruction: String) async throws -> String {
        let prompt = PromptBuilder.build(instruction: instruction, text: text)
        let request = try buildRequest(prompt: prompt)
        let (data, response) = try await fetch(request: request)
        return try parse(data: data, response: response)
    }

    nonisolated private func buildRequest(prompt: PromptBuilder.Prompt) throws -> URLRequest {
        // Use URLComponents to safely percent-encode the API key rather than
        // interpolating it directly, which would crash if the key contains
        // URL-unsafe characters.
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw AIError.invalidResponse("Failed to construct request URL")
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw AIError.invalidResponse("Failed to construct request URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": prompt.system]]],
            "contents": [["parts": [["text": prompt.user]]]],
            "generationConfig": ["temperature": 0.3, "maxOutputTokens": 4096]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    nonisolated private func fetch(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:  throw AIError.timeout
            case .cancelled: throw AIError.cancelled
            default:         throw AIError.networkError(underlying: error)
            }
        }
    }

    nonisolated private func parse(data: Data, response: URLResponse) throws -> String {
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse("Non-HTTP response")
        }
        switch http.statusCode {
        case 200: break
        case 400:
            let message = errorMessage(in: data)
            if message?.contains("API_KEY_INVALID") == true { throw AIError.invalidAPIKey }
            throw AIError.serviceError(statusCode: 400, message: message)
        case 429: throw AIError.rateLimited(retryAfter: nil)
        default:
            throw AIError.serviceError(statusCode: http.statusCode, message: errorMessage(in: data))
        }
        guard
            let json       = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let first      = candidates.first,
            let content    = first["content"] as? [String: Any],
            let parts      = content["parts"] as? [[String: Any]],
            let firstPart  = parts.first,
            let text       = firstPart["text"] as? String
        else { throw AIError.invalidResponse("Unexpected JSON structure") }

        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw AIError.invalidResponse("Empty content") }
        return result
    }

    nonisolated private func errorMessage(in data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }
            .flatMap { $0["message"] as? String }
    }
}
