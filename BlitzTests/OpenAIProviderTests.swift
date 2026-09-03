import Testing
import Foundation
@testable import Blitz

@Suite("OpenAIProvider")
struct OpenAIProviderTests {

    private func makeProvider() -> OpenAIProvider {
        OpenAIProvider(apiKey: "test-key", session: .mock)
    }

    private func stub(statusCode: Int, body: [String: Any], headers: [String: String]? = nil) {
        MockURLProtocol.requestHandler = { _ in
            let url = URL(string: "https://api.openai.com")!
            let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                           httpVersion: nil, headerFields: headers)!
            let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
            return (response, data)
        }
    }

    @Test("Returns trimmed content from a 200 response")
    func successResponse() async throws {
        stub(statusCode: 200, body: [
            "choices": [["message": ["role": "assistant", "content": "  Corrected text.  \n"]]]
        ])
        let result = try await makeProvider().transform(text: "hello", instruction: "Fix it")
        #expect(result == "Corrected text.")
    }

    @Test("Throws invalidAPIKey on 401")
    func invalidKeyOn401() async throws {
        stub(statusCode: 401, body: ["error": ["message": "Unauthorized"]])
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.invalidAPIKey")
        } catch AIError.invalidAPIKey { }
    }

    @Test("Throws invalidAPIKey on 403")
    func invalidKeyOn403() async throws {
        stub(statusCode: 403, body: ["error": ["message": "Forbidden"]])
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.invalidAPIKey")
        } catch AIError.invalidAPIKey { }
    }

    @Test("Throws rateLimited on 429")
    func rateLimitedOn429() async throws {
        stub(statusCode: 429, body: ["error": ["message": "Rate limit exceeded"]])
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.rateLimited")
        } catch AIError.rateLimited { }
    }

    @Test("Parses Retry-After header into rateLimited retryAfter value")
    func retryAfterHeader() async throws {
        stub(statusCode: 429, body: [:], headers: ["Retry-After": "30"])
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.rateLimited")
        } catch AIError.rateLimited(let retryAfter) {
            #expect(retryAfter == 30)
        }
    }

    @Test("Throws serviceError with correct status code on 500")
    func serviceErrorOn500() async throws {
        stub(statusCode: 500, body: ["error": ["message": "Internal server error"]])
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.serviceError")
        } catch AIError.serviceError(let code, _) {
            #expect(code == 500)
        }
    }

    @Test("Throws invalidResponse on malformed JSON body")
    func malformedJSON() async throws {
        MockURLProtocol.requestHandler = { _ in
            let url = URL(string: "https://api.openai.com")!
            let response = HTTPURLResponse(url: url, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data("not json".utf8))
        }
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.invalidResponse")
        } catch AIError.invalidResponse { }
    }

    @Test("Throws invalidResponse when choices array is missing")
    func missingChoices() async throws {
        stub(statusCode: 200, body: ["id": "cmpl-123"])
        do {
            _ = try await makeProvider().transform(text: "x", instruction: "y")
            Issue.record("Expected AIError.invalidResponse")
        } catch AIError.invalidResponse { }
    }

    @Test("Sends POST with Bearer token and Content-Type headers")
    func requestShape() async throws {
        var captured: URLRequest?
        MockURLProtocol.requestHandler = { req in
            captured = req
            let url = URL(string: "https://api.openai.com")!
            let response = HTTPURLResponse(url: url, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            let body = try JSONSerialization.data(withJSONObject: [
                "choices": [["message": ["role": "assistant", "content": "OK"]]]
            ])
            return (response, body)
        }
        _ = try await makeProvider().transform(text: "t", instruction: "i")
        let req = try #require(captured)
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
}
