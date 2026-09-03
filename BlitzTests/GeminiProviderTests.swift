import Testing
import Foundation
@testable import Blitz

@Suite("GeminiProvider")
struct GeminiProviderTests {

    private func makeProvider() -> GeminiProvider {
        GeminiProvider(apiKey: "test-key", session: .mock)
    }

    private func stub(statusCode: Int, body: [String: Any]) {
        MockURLProtocol.requestHandler = { _ in
            let url = URL(string: "https://generativelanguage.googleapis.com")!
            let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                           httpVersion: nil, headerFields: nil)!
            let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
            return (response, data)
        }
    }

    private func successBody(text: String) -> [String: Any] {
        ["candidates": [["content": ["parts": [["text": text]]]]]]
    }

    @Test("Returns trimmed text from a 200 response")
    func successResponse() async throws {
        stub(statusCode: 200, body: successBody(text: "  Translated text.  \n"))
        let result = try await makeProvider().transform(text: "Hola", instruction: "Translate to English")
        #expect(result == "Translated text.")
    }

    @Test("Throws invalidAPIKey on 400 with API_KEY_INVALID in message")
    func invalidKeyOn400() async throws {
        stub(statusCode: 400, body: [
            "error": ["message": "API_KEY_INVALID: The provided API key is invalid."]
        ])
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.invalidAPIKey")
        } catch AIError.invalidAPIKey { }
    }

    @Test("Throws serviceError on 400 for non-key errors")
    func serviceErrorOn400() async throws {
        stub(statusCode: 400, body: ["error": ["message": "Bad request"]])
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.serviceError")
        } catch AIError.serviceError(let code, _) {
            #expect(code == 400)
        }
    }

    @Test("Throws rateLimited on 429")
    func rateLimitedOn429() async throws {
        stub(statusCode: 429, body: [:])
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.rateLimited")
        } catch AIError.rateLimited { }
    }

    @Test("Throws serviceError on 500")
    func serviceErrorOn500() async throws {
        stub(statusCode: 500, body: ["error": ["message": "Server error"]])
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.serviceError")
        } catch AIError.serviceError(let code, _) {
            #expect(code == 500)
        }
    }

    @Test("Throws invalidResponse on malformed JSON")
    func malformedJSON() async throws {
        MockURLProtocol.requestHandler = { _ in
            let url = URL(string: "https://generativelanguage.googleapis.com")!
            let response = HTTPURLResponse(url: url, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data("not json".utf8))
        }
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.invalidResponse")
        } catch AIError.invalidResponse { }
    }

    @Test("Throws invalidResponse when candidates array is missing")
    func missingCandidates() async throws {
        stub(statusCode: 200, body: ["promptFeedback": [:]])
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.invalidResponse")
        } catch AIError.invalidResponse { }
    }

    @Test("Includes API key as URL query parameter, not Authorization header")
    func apiKeyInQueryParameter() async throws {
        var captured: URLRequest?
        MockURLProtocol.requestHandler = { req in
            captured = req
            let url = URL(string: "https://generativelanguage.googleapis.com")!
            let response = HTTPURLResponse(url: url, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            let body = try JSONSerialization.data(withJSONObject: self.successBody(text: "OK"))
            return (response, body)
        }
        _ = try await makeProvider().transform(text: "t", instruction: "i")
        let req = try #require(captured)
        let urlString = try #require(req.url?.absoluteString)
        #expect(urlString.contains("key=test-key"))
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
