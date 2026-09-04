import Foundation
import FoundationModels

struct AppleFoundationModelProvider: AIProvider {
    let id = ProviderID.apple
    let displayName = "Apple Intelligence"

    nonisolated func transform(text: String, instruction: String) async throws -> String {
        guard AppleIntelligenceCapability.isAvailable else {
            throw AIError.modelUnavailable(AppleIntelligenceCapability.status.description)
        }
        let session = LanguageModelSession(instructions: instruction)
        do {
            let response = try await session.respond(to: text)
            return response.content
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let error as LanguageModelSession.GenerationError {
            throw map(error)
        } catch {
            throw AIError.invalidResponse(error.localizedDescription)
        }
    }

    private nonisolated func map(_ error: LanguageModelSession.GenerationError) -> AIError {
        switch error {
        case .assetsUnavailable:
            return .modelUnavailable("Apple Intelligence assets are unavailable on this device.")
        case .rateLimited:
            return .rateLimited(retryAfter: nil)
        case .guardrailViolation:
            return .serviceError(statusCode: 400, message: "Content blocked by safety guardrails.")
        case .exceededContextWindowSize:
            return .serviceError(statusCode: 413, message: "Text is too long for the on-device model.")
        case .unsupportedLanguageOrLocale:
            return .serviceError(statusCode: 400, message: "Language not supported by Apple Intelligence.")
        case .concurrentRequests:
            return .serviceError(statusCode: 429, message: "Apple Intelligence is busy. Please try again.")
        case .refusal(_, _):
            return .serviceError(statusCode: 400, message: "Request refused by the on-device model.")
        default:
            return .invalidResponse(error.localizedDescription)
        }
    }
}
