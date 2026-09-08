import Foundation

enum PromptBuilder {
    struct Prompt {
        let system: String
        let user: String
    }

    nonisolated static func build(instruction: String, text: String) -> Prompt {
        Prompt(system: systemPrompt(for: instruction), user: text)
    }

    /// Builds a prompt for refining a previously transformed result.
    nonisolated static func buildRevision(previousResult: String, followUp: String) -> Prompt {
        Prompt(
            system: """
            You are refining a previously transformed text.

            Follow-up instruction: \(followUp)

            Rules:
            - Return ONLY the refined text.
            - Do not add explanations, commentary, or metadata.
            - Do not wrap the output in quotes or markdown.
            - Apply only the requested change; preserve everything else.
            """,
            user: previousResult
        )
    }

    nonisolated private static func systemPrompt(for instruction: String) -> String {
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
