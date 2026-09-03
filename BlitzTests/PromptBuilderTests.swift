import Testing
@testable import Blitz

@Suite("PromptBuilder")
struct PromptBuilderTests {

    @Test("System prompt contains the instruction")
    func systemContainsInstruction() {
        let prompt = PromptBuilder.build(instruction: "Fix grammar.", text: "Hello world")
        #expect(prompt.system.contains("Fix grammar."))
    }

    @Test("User message is exactly the input text")
    func userMessageIsInputText() {
        let text = "The quick brown fox"
        let prompt = PromptBuilder.build(instruction: "Anything", text: text)
        #expect(prompt.user == text)
    }

    @Test("System prompt contains directive to return only transformed text")
    func systemContainsOnlyDirective() {
        let prompt = PromptBuilder.build(instruction: "Something", text: "Text")
        #expect(prompt.system.contains("ONLY"))
    }

    @Test("Instruction appears in system, not in user; text appears in user, not in system")
    func instructionAndTextAreSeparate() {
        let instruction = "UNIQUE_INSTRUCTION_MARKER"
        let text = "UNIQUE_TEXT_MARKER"
        let prompt = PromptBuilder.build(instruction: instruction, text: text)
        #expect(prompt.system.contains(instruction))
        #expect(!prompt.system.contains(text))
        #expect(prompt.user == text)
        #expect(!prompt.user.contains(instruction))
    }

    @Test("System prompt instructs not to add commentary or metadata")
    func systemExcludesCommentaryDirective() {
        let prompt = PromptBuilder.build(instruction: "Translate", text: "Bonjour")
        let lower = prompt.system.lowercased()
        #expect(lower.contains("explanations") || lower.contains("commentary"))
    }

    @Test("Empty instruction produces non-empty system prompt")
    func emptyInstruction() {
        let prompt = PromptBuilder.build(instruction: "", text: "Some text")
        #expect(!prompt.system.isEmpty)
        #expect(prompt.user == "Some text")
    }

    @Test("Empty text is preserved unchanged in user field")
    func emptyTextPreserved() {
        let prompt = PromptBuilder.build(instruction: "Do something", text: "")
        #expect(prompt.user == "")
    }
}
