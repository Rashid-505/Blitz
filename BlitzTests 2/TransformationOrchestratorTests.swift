import Testing
import Foundation
import SwiftData
@testable import Blitz

// MARK: - Mocks

final class MockTextSelectionService: TextSelectionService {
    var textToReturn: String = "Selected text."
    var errorToThrow: Error?
    var permissionGranted = true
    var permissionRequested = false

    func readSelectedText() async throws -> String {
        if let error = errorToThrow { throw error }
        return textToReturn
    }

    func hasAccessibilityPermission() -> Bool { permissionGranted }

    func requestAccessibilityPermission() {
        permissionRequested = true
    }
}

final class MockTextReplacementService: TextReplacementService {
    var replacedWith: String?
    var errorToThrow: Error?

    func replaceSelectedText(with newText: String) async throws {
        if let error = errorToThrow { throw error }
        replacedWith = newText
    }
}

final class MockAIProvider: AIProvider {
    let id = ProviderID.openAI
    let displayName = "Mock"
    var transformedText: String = "Transformed text."
    var errorToThrow: Error?

    func transform(text: String, instruction: String) async throws -> String {
        if let error = errorToThrow { throw error }
        return transformedText
    }
}

// MARK: - Helpers

private func makeOrchestrator(
    selection: MockTextSelectionService = MockTextSelectionService(),
    replacement: MockTextReplacementService = MockTextReplacementService(),
    previewEnabled: Bool = false
) -> TransformationOrchestrator {
    TransformationOrchestrator(
        textSelectionService: selection,
        textReplacementService: replacement,
        preferences: PreviewSettings(isPreviewEnabled: previewEnabled)
    )
}

private func makeScenario() throws -> Scenario {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: Scenario.self, configurations: config)
    let scenario = Scenario(name: "Fix Grammar", instruction: "Fix grammar.", order: 0)
    container.mainContext.insert(scenario)
    return scenario
}

// MARK: - Tests

@Suite("TransformationOrchestrator")
struct TransformationOrchestratorTests {

    // MARK: Existing one-shot tests (preview disabled)

    @Test("Successful transformation replaces text and returns to idle")
    func successPath() async throws {
        let selection = MockTextSelectionService()
        selection.textToReturn = "helo wrold"
        let replacement = MockTextReplacementService()
        let provider = MockAIProvider()
        provider.transformedText = "Hello world."

        let orchestrator = makeOrchestrator(selection: selection, replacement: replacement)
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: provider)
        await orchestrator.currentTask?.value

        if case .idle = orchestrator.state { } else {
            Issue.record("Expected .idle after successful transformation, got \(orchestrator.state)")
        }
        #expect(replacement.replacedWith == "Hello world.")
    }

    @Test("State is .transforming immediately after transform is called")
    func stateIsTransformingImmediately() async throws {
        let orchestrator = makeOrchestrator()
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: MockAIProvider())

        if case .transforming(let name) = orchestrator.state {
            #expect(name == "Fix Grammar")
        } else {
            Issue.record("Expected .transforming immediately after transform call")
        }

        await orchestrator.currentTask?.value
    }

    @Test("No text selected transitions to .failed")
    func noTextSelected() async throws {
        let selection = MockTextSelectionService()
        selection.errorToThrow = TextServiceError.noTextSelected

        let orchestrator = makeOrchestrator(selection: selection)
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: MockAIProvider())
        await orchestrator.currentTask?.value

        guard case .failed = orchestrator.state else {
            Issue.record("Expected .failed after noTextSelected error")
            return
        }
    }

    @Test("Permission denied triggers request and transitions to .failed")
    func permissionDenied() async throws {
        let selection = MockTextSelectionService()
        selection.errorToThrow = TextServiceError.accessibilityPermissionDenied

        let orchestrator = makeOrchestrator(selection: selection)
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: MockAIProvider())
        await orchestrator.currentTask?.value

        #expect(selection.permissionRequested == true)
        guard case .failed = orchestrator.state else {
            Issue.record("Expected .failed after permission denied")
            return
        }
    }

    @Test("AI provider error transitions to .failed")
    func aiProviderError() async throws {
        let provider = MockAIProvider()
        provider.errorToThrow = AIError.invalidAPIKey

        let orchestrator = makeOrchestrator()
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: provider)
        await orchestrator.currentTask?.value

        guard case .failed(let error) = orchestrator.state else {
            Issue.record("Expected .failed after AI error")
            return
        }
        #expect(error is AIError)
    }

    @Test("Empty AI response transitions to .failed with TransformationError")
    func emptyAIResponse() async throws {
        let provider = MockAIProvider()
        provider.transformedText = "   "

        let orchestrator = makeOrchestrator()
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: provider)
        await orchestrator.currentTask?.value

        guard case .failed(let error) = orchestrator.state else {
            Issue.record("Expected .failed for whitespace-only response")
            return
        }
        #expect(error is TransformationError)
    }

    @Test("Replacement service error transitions to .failed")
    func replacementError() async throws {
        let replacement = MockTextReplacementService()
        replacement.errorToThrow = TextServiceError.replacementFailed("test")

        let orchestrator = makeOrchestrator(replacement: replacement)
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: MockAIProvider())
        await orchestrator.currentTask?.value

        guard case .failed = orchestrator.state else {
            Issue.record("Expected .failed after replacement error")
            return
        }
    }

    @Test("Cancellation returns to .idle")
    func cancellation() async throws {
        let orchestrator = makeOrchestrator()
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: MockAIProvider())
        let task = orchestrator.currentTask
        orchestrator.cancel()
        await task?.value

        if case .idle = orchestrator.state { } else {
            Issue.record("Expected .idle after cancellation")
        }
    }

    @Test("Second transform cancels the first task")
    func secondTransformCancelsFirst() async throws {
        let orchestrator = makeOrchestrator()
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: MockAIProvider())
        let firstTask = try #require(orchestrator.currentTask)

        orchestrator.transform(with: scenario, provider: MockAIProvider())
        await orchestrator.currentTask?.value

        #expect(firstTask.isCancelled)
    }

    // MARK: Preview tests

    @Test("Preview enabled: transform enters .preview state without writing")
    func previewEnabled_entersPreviewWithoutWriting() async throws {
        let selection = MockTextSelectionService()
        selection.textToReturn = "helo wrold"
        let replacement = MockTextReplacementService()
        let provider = MockAIProvider()
        provider.transformedText = "Hello world."

        let orchestrator = makeOrchestrator(
            selection: selection,
            replacement: replacement,
            previewEnabled: true
        )
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: provider)
        await orchestrator.currentTask?.value

        guard case .preview(let name, let original, let result) = orchestrator.state else {
            Issue.record("Expected .preview state, got \(orchestrator.state)")
            return
        }
        #expect(name == "Fix Grammar")
        #expect(original == "helo wrold")
        #expect(result == "Hello world.")
        #expect(replacement.replacedWith == nil, "Text must not be written before commit()")
    }

    @Test("Preview enabled: commit() writes the result and returns to .idle")
    func previewEnabled_commitWritesAndReturnsToIdle() async throws {
        let replacement = MockTextReplacementService()
        let provider = MockAIProvider()
        provider.transformedText = "Hello world."

        let orchestrator = makeOrchestrator(
            replacement: replacement,
            previewEnabled: true
        )
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: provider)
        await orchestrator.currentTask?.value

        // Confirm we're in preview before committing.
        guard case .preview = orchestrator.state else {
            Issue.record("Expected .preview state before commit")
            return
        }

        orchestrator.commit()
        await orchestrator.currentTask?.value

        if case .idle = orchestrator.state { } else {
            Issue.record("Expected .idle after commit(), got \(orchestrator.state)")
        }
        #expect(replacement.replacedWith == "Hello world.")
    }

    @Test("Preview enabled: cancel() from preview writes nothing and returns to .idle")
    func previewEnabled_cancelFromPreviewWritesNothing() async throws {
        let replacement = MockTextReplacementService()

        let orchestrator = makeOrchestrator(
            replacement: replacement,
            previewEnabled: true
        )
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: MockAIProvider())
        await orchestrator.currentTask?.value

        guard case .preview = orchestrator.state else {
            Issue.record("Expected .preview state before cancel")
            return
        }

        orchestrator.cancel()

        if case .idle = orchestrator.state { } else {
            Issue.record("Expected .idle after cancel() from preview, got \(orchestrator.state)")
        }
        #expect(replacement.replacedWith == nil, "cancel() from preview must not write anything")
    }

    @Test("Preview disabled: transform writes immediately (one-shot behavior unchanged)")
    func previewDisabled_oneShotBehaviorUnchanged() async throws {
        let replacement = MockTextReplacementService()
        let provider = MockAIProvider()
        provider.transformedText = "Fixed text."

        let orchestrator = makeOrchestrator(
            replacement: replacement,
            previewEnabled: false
        )
        let scenario = try makeScenario()

        orchestrator.transform(with: scenario, provider: provider)
        await orchestrator.currentTask?.value

        if case .idle = orchestrator.state { } else {
            Issue.record("Expected .idle after one-shot transformation, got \(orchestrator.state)")
        }
        #expect(replacement.replacedWith == "Fixed text.")
    }

    @Test("commit() is a no-op when state is not .preview")
    func commitIsNoOpOutsidePreview() async throws {
        let replacement = MockTextReplacementService()
        let orchestrator = makeOrchestrator(replacement: replacement)

        // State is .idle — commit should be a no-op.
        orchestrator.commit()
        await orchestrator.currentTask?.value

        if case .idle = orchestrator.state { } else {
            Issue.record("Expected state to remain .idle after no-op commit()")
        }
        #expect(replacement.replacedWith == nil)
    }
}
