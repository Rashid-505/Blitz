import Foundation

enum PromptBuilder {
    struct Prompt {
        let system: String
        let user: String
    }

    static func build(instruction: String, text: String) -> Prompt {
        Prompt(system: systemPrompt(for: instruction), user: text)
    }

    private static func systemPrompt(for instruction: String) -> String {
        """
        \(instruction)

        Rules:
        - Return ONLY the transformed text.
        - Do not add explanations, commentary, or metadata.
        - Do not wrap the output in quotes or markdown.
        - Preserve the original meaning unless the instruction explicitly asks for a change.
        """
    }
}
