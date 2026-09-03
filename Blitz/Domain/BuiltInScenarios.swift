import Foundation

struct ScenarioDefinition {
    let name: String
    let instruction: String
}

enum BuiltInScenarios {
    static let all: [ScenarioDefinition] = [
        ScenarioDefinition(
            name: "Fix Grammar",
            instruction: "Fix the grammar and punctuation of the following text. Return only the corrected text, with no additional commentary."
        ),
        ScenarioDefinition(
            name: "Make Formal",
            instruction: "Rewrite the following text in a formal, professional tone. Return only the rewritten text."
        ),
        ScenarioDefinition(
            name: "Make Casual",
            instruction: "Rewrite the following text in a casual, conversational tone. Return only the rewritten text."
        ),
        ScenarioDefinition(
            name: "Summarize",
            instruction: "Summarize the following text concisely. Return only the summary."
        ),
        ScenarioDefinition(
            name: "Translate to English",
            instruction: "Translate the following text to English. Return only the translation."
        ),
    ]
}
