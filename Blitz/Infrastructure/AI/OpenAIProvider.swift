import Foundation

final class OpenAIProvider: AIProvider {
    let id = ProviderID.openAI
    let displayName = "OpenAI"

    static let defaultModel = "gpt-4o-mini"

    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(apiKey: String, model: String = defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func transform(text: String, instruction: String) async throws -> String {
        let prompt = PromptBuilder.build(instruction: instruction, text: text)
        let request = try buildRequest(prompt: prompt)
        let (data, response) = try await fetch(request: request)
        return try parse(data: data, response: response)
    }

    private func buildRequest(prompt: PromptBuilder.Prompt) throws -> URLRequest {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": prompt.system],
                ["role": "user",   "content": prompt.user]
            ],
            "temperature": 0.3,
            "max_tokens": 4096
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func fetch(request: URLRequest) async throws -> (Data, URLResponse) {
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

    private func parse(data: Data, response: URLResponse) throws -> String {
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse("Non-HTTP response")
        }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw AIError.invalidAPIKey
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw AIError.rateLimited(retryAfter: retry)
        default:
            throw AIError.serviceError(statusCode: http.statusCode, message: errorMessage(in: data))
        }
        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first   = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw AIError.invalidResponse("Unexpected JSON structure") }

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw AIError.invalidResponse("Empty content") }
        return result
    }

    private func errorMessage(in data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }
            .flatMap { $0["message"] as? String }
    }
}
