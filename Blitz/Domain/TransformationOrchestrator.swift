import Foundation

enum TransformationState {
    case idle
    case transforming(scenarioName: String)
    case failed(Error)

    var isTransforming: Bool {
        if case .transforming = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let error) = self {
            return error.localizedDescription
        }
        return nil
    }
}

enum TransformationError: Error, LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        "The AI returned an empty response. Please try again."
    }
}

@Observable
final class TransformationOrchestrator {
    private(set) var state: TransformationState = .idle

    // Internal access lets tests await task completion.
    var currentTask: Task<Void, Never>?

    private let textSelectionService: any TextSelectionService
    private let textReplacementService: any TextReplacementService

    init(
        textSelectionService: any TextSelectionService,
        textReplacementService: any TextReplacementService
    ) {
        self.textSelectionService = textSelectionService
        self.textReplacementService = textReplacementService
    }

    func transform(with scenario: Scenario, provider: any AIProvider) {
        // Extract values synchronously to avoid SwiftData threading concerns.
        let name = scenario.name
        let instruction = scenario.instruction
        currentTask?.cancel()
        currentTask = Task {
            await perform(scenarioName: name, instruction: instruction, provider: provider)
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
    }

    private func perform(scenarioName: String, instruction: String, provider: any AIProvider) async {
        state = .transforming(scenarioName: scenarioName)
        do {
            let selectedText = try await textSelectionService.readSelectedText()
            try Task.checkCancellation()

            let transformed = try await provider.transform(text: selectedText, instruction: instruction)
            try Task.checkCancellation()

            guard !transformed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TransformationError.emptyResponse
            }

            try await textReplacementService.replaceSelectedText(with: transformed)
            state = .idle
        } catch TextServiceError.accessibilityPermissionDenied {
            textSelectionService.requestAccessibilityPermission()
            state = .failed(TextServiceError.accessibilityPermissionDenied)
        } catch AIError.cancelled, is CancellationError {
            // URLSession cancellation (AIError.cancelled) and Swift task cancellation
            // (CancellationError) both mean the user dismissed the operation — return to idle.
            state = .idle
        } catch {
            state = .failed(error)
        }
    }
}
