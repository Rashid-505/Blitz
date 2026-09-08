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

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let error) = self {
            return error.localizedDescription
        }
        return nil
    }

    /// False for errors the user cannot fix by retrying (permission denied, no selection).
    var isRetryable: Bool {
        guard case .failed(let error) = self else { return false }
        if case TextServiceError.accessibilityPermissionDenied = error { return false }
        if case TextServiceError.noTextSelected = error { return false }
        return true
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

    /// Number of revisions applied on top of the initial result.
    /// 0 = showing the initial result; 1+ = revision count.
    var revisionDepth: Int { max(0, resultStack.count - 2) }

    /// True when there is a previous result to step back to.
    var canGoBack: Bool { resultStack.count >= 3 }

    // Internal access lets tests await task completion.
    var currentTask: Task<Void, Never>?

    private let textSelectionService: any TextSelectionService
    private let textReplacementService: any TextReplacementService
    private let preferences: PreviewSettings
    private let historyStore: ReplacementHistoryStore?

    // resultStack[0] = original selection; resultStack[1+] = each result/revision.
    // Capped at 10 entries.
    private var resultStack: [String] = []

    // Stores the most recent request so retryLast() can replay it after a failure.
    private var lastRequest: LastRequest?

    // Non-nil while a revision is in flight (or failed). Holds the .preview state
    // to restore if the user cancels the revision or cancels after a revision failure.
    private var revisionRestoreState: TransformationState?

    private struct LastRequest {
        let scenarioName: String
        let instruction: String
        let provider: any AIProvider
        /// Non-nil for revisions: use this text directly instead of reading from
        /// the selection service. nil = read from selection (original transform).
        let inputText: String?
    }

    init(
        textSelectionService: any TextSelectionService,
        textReplacementService: any TextReplacementService,
        preferences: PreviewSettings = PreviewSettings(),
        historyStore: ReplacementHistoryStore? = nil
    ) {
        self.textSelectionService = textSelectionService
        self.textReplacementService = textReplacementService
        self.preferences = preferences
        self.historyStore = historyStore
    }

    // MARK: - Public interface

    func transform(with scenario: Scenario, provider: any AIProvider) {
        // Extract values synchronously to avoid SwiftData threading concerns.
        let name = scenario.name
        let instruction = scenario.instruction
        currentTask?.cancel()
        revisionRestoreState = nil
        resultStack = []
        lastRequest = LastRequest(scenarioName: name, instruction: instruction, provider: provider, inputText: nil)
        currentTask = Task {
            await perform(scenarioName: name, instruction: instruction, provider: provider)
        }
    }

    /// Writes the previewed text to the source application and returns to `.idle`.
    ///
    /// No-op when the state is not `.preview`.
    func commit() {
        guard case .preview(let scenarioName, let original, let result) = state else { return }
        revisionRestoreState = nil
        resultStack = []
        lastRequest = nil
        currentTask?.cancel()
        currentTask = Task {
            do {
                try await textReplacementService.replaceSelectedText(with: result)
                historyStore?.record(scenarioName: scenarioName, original: original, result: result)
                state = .idle
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error)
            }
        }
    }

    /// Discards any in-progress operation or pending preview without writing.
    ///
    /// During an in-flight revision (or after a failed revision), cancels and restores
    /// the previous preview result rather than going to `.idle`.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        lastRequest = nil
        if let restoreState = revisionRestoreState {
            revisionRestoreState = nil
            state = restoreState
        } else {
            revisionRestoreState = nil
            resultStack = []
            state = .idle
        }
    }

    /// Replays the most recent request.
    ///
    /// No-op when the state is not `.failed` or when the error is not retryable
    /// (permission denied, no text selected).
    func retryLast() {
        guard state.isRetryable, let req = lastRequest else { return }
        currentTask?.cancel()
        currentTask = Task {
            if let inputText = req.inputText {
                await performWithText(
                    inputText,
                    scenarioName: req.scenarioName,
                    instruction: req.instruction,
                    provider: req.provider
                )
            } else {
                await perform(scenarioName: req.scenarioName, instruction: req.instruction, provider: req.provider)
            }
        }
    }

    /// Sends the current preview result plus a follow-up instruction to the AI.
    ///
    /// Only valid in `.preview` state. Transitions to `.transforming`, then either
    /// a deeper `.preview` or `.failed`. Cancelling a revision restores the preview
    /// to the result that was showing before the revision started.
    func revise(followUp: String, provider: any AIProvider) {
        guard case .preview(let scenarioName, _, let currentResult) = state else { return }
        revisionRestoreState = state
        lastRequest = LastRequest(
            scenarioName: scenarioName,
            instruction: followUp,
            provider: provider,
            inputText: currentResult
        )
        currentTask?.cancel()
        currentTask = Task {
            await performWithText(
                currentResult,
                scenarioName: scenarioName,
                instruction: followUp,
                provider: provider
            )
        }
    }

    /// Removes the most recent revision and restores the previous preview result.
    ///
    /// No-op if there is nothing to undo (only the initial result is showing).
    func back() {
        guard canGoBack, case .preview(let scenarioName, let original, _) = state else { return }
        resultStack.removeLast()
        state = .preview(scenarioName: scenarioName, original: original, result: resultStack[resultStack.count - 1])
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

            lastRequest = nil
            if preferences.isPreviewEnabled {
                resultStack = [selectedText, transformed]
                state = .preview(scenarioName: scenarioName, original: selectedText, result: transformed)
            } else {
                try await textReplacementService.replaceSelectedText(with: transformed)
                historyStore?.record(scenarioName: scenarioName, original: selectedText, result: transformed)
                resultStack = []
                state = .idle
            }
        } catch TextServiceError.accessibilityPermissionDenied {
            textSelectionService.requestAccessibilityPermission()
            state = .failed(TextServiceError.accessibilityPermissionDenied)
        } catch AIError.cancelled, is CancellationError {
            state = .idle
        } catch {
            state = .failed(error)
        }
    }

    /// Transforms `text` directly without going through the text selection service.
    /// Used for revisions (input is the previous result) and revision retries.
    private func performWithText(
        _ text: String,
        scenarioName: String,
        instruction: String,
        provider: any AIProvider
    ) async {
        // Guard against cancellation that happened before this task started running.
        // cancel() already set the correct restore state synchronously; touching
        // state here would overwrite it.
        guard !Task.isCancelled else { return }
        state = .transforming(scenarioName: scenarioName)
        do {
            let transformed = try await provider.transform(text: text, instruction: instruction)
            try Task.checkCancellation()

            guard !transformed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TransformationError.emptyResponse
            }

            let original = resultStack.first ?? text
            if resultStack.count < 10 {
                resultStack.append(transformed)
            } else {
                // Stack is full; replace the oldest revision (keep original + first result).
                resultStack[resultStack.count - 1] = transformed
            }
            revisionRestoreState = nil
            lastRequest = nil
            state = .preview(scenarioName: scenarioName, original: original, result: transformed)
        } catch AIError.cancelled, is CancellationError {
            // cancel() was called and already set state correctly. Nothing to do.
            return
        } catch {
            // Keep revisionRestoreState set — cancel() from .failed can still restore preview.
            state = .failed(error)
        }
    }
}
