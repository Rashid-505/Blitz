import Foundation

enum AIError: Error, LocalizedError {
    case invalidAPIKey
    case networkError(underlying: any Error)
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    case cancelled
    case invalidResponse(String)
    case serviceError(statusCode: Int, message: String?)
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key. Check your provider settings."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Try again in \(Int(seconds)) seconds."
            }
            return "Rate limited. Please try again later."
        case .timeout:
            return "Request timed out."
        case .cancelled:
            return "Request was cancelled."
        case .invalidResponse(let detail):
            return "Unexpected response: \(detail)"
        case .serviceError(let code, let message):
            return "Service error (\(code)): \(message ?? "Unknown error")"
        case .modelUnavailable(let reason):
            return reason
        }
    }
}
