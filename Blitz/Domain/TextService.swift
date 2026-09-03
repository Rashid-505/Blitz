import Foundation

protocol TextSelectionService {
    func readSelectedText() async throws -> String
    func hasAccessibilityPermission() -> Bool
    func requestAccessibilityPermission()
}

protocol TextReplacementService {
    func replaceSelectedText(with newText: String) async throws
}

enum TextServiceError: Error, LocalizedError {
    case noTextSelected
    case accessibilityPermissionDenied
    case replacementFailed(String)

    var errorDescription: String? {
        switch self {
        case .noTextSelected:
            return "No text selected. Select some text in another app first."
        case .accessibilityPermissionDenied:
            return "Accessibility permission required. Open System Settings > Privacy & Security > Accessibility and enable Blitz."
        case .replacementFailed(let detail):
            return "Failed to replace text: \(detail)"
        }
    }
}
