import Foundation

enum TransformationState {
    case idle
    case transforming(scenarioName: String)
    /// AI finished; waiting for the user to confirm or discard.
    case preview(scenarioName: String, original: String, result: String)
    case failed(Error)

    var isTransforming: Bool {
        if case .transforming = self { return true }
        return false
    }

    var isPreview: Bool {
        if case .preview = self { return true }
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
    private let preferences: PreviewSettings

    init(
        textSelectionService: any TextSelectionService,
        textReplacementService: any TextReplacementService,
        preferences: PreviewSettings = PreviewSettings()
    ) {
        self.textSelectionService = textSelectionService
        self.textReplacementService = textReplacementService
        self.preferences = preferences
    }

    // MARK: - Public interface

    func transform(with scenario: Scenario, provider: any AIProvider) {
        // Extract values synchronously to avoid SwiftData threading concerns.
        let name = scenario.name
        let instruction = scenario.instruction
        currentTask?.cancel()
        currentTask = Task {
            await perform(scenarioName: name, instruction: instruction, provider: provider)
        }
    }

    /// Writes the previewed text to the source application and returns to `.idle`.
    ///
    /// No-op when the state is not `.preview`.
    func commit() {
        guard case .preview(_, _, let result) = state else { return }
        currentTask?.cancel()
        currentTask = Task {
            do {
                try await textReplacementService.replaceSelectedText(with: result)
                state = .idle
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error)
            }
        }
    }

    /// Discards any in-progress transformation or pending preview and returns to `.idle`
    /// without writing anything.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
    }

    // MARK: - Private

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

            if preferences.isPreviewEnabled {
                state = .preview(scenarioName: scenarioName, original: selectedText, result: transformed)
            } else {
                try await textReplacementService.replaceSelectedText(with: transformed)
                state = .idle
            }
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
