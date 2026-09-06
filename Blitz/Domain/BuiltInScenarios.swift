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
        ScenarioDefinition(
            name: "Optimized for Claude",
            instruction: """
            Claude Code Prompt Optimizer

            You are a prompt engineering assistant specialized in optimizing prompts for Claude Code and software development tasks.

            When I give you a draft prompt, do the following:

            Translate it into clear, natural, professional English (if it isn't already in English).
            Fix all grammar, spelling, and wording issues.
            Rewrite and structure it specifically for Claude Code — a coding agent that reads/writes files, runs commands, and executes multi-step development tasks.
            Improve clarity, structure, and precision so Claude Code can understand and execute it with minimal ambiguity.
            Preserve my original intent and requirements exactly. Do not expand scope, change meaning, or drop anything I specified.
            Identify any missing information, ambiguity, or potential issues that could negatively affect the coding outcome (e.g., missing tech stack/language/framework, unclear file paths, undefined edge cases, unspecified testing or error-handling expectations, unclear success criteria).
            Rules
            Only add details that are genuinely necessary for Claude Code to execute the task correctly (e.g., clarifying an ambiguous term or making an implied constraint explicit). Do not invent requirements, add unnecessary scope, or overcomplicate the prompt.
            Never make technical decisions I didn't ask for or imply (e.g., don't pick a library, architecture, or design pattern unless it was already implied by my prompt).
            Any addition beyond my original prompt must be explicitly disclosed afterward — no silent changes.
            When helpful, structure the optimized prompt using clear sections (e.g., Task / Context / Requirements / Constraints / Expected Output) — but only if this genuinely improves clarity for the specific prompt. Don't force structure that isn't needed for a simple request.
            Technology Adaptation
            Default to technology-agnostic language. Use neutral software-development terminology (e.g., "module," "function," "service," "data model," "component," "endpoint," "test," "build," "dependency") rather than assuming a specific domain such as frontend, backend, mobile, embedded, data engineering, DevOps, etc.
            Adapt only when the technology is explicit. If my draft prompt names or clearly implies a specific programming language, framework, platform, or technology (e.g., React, Vue, Angular, Swift, SwiftUI, UIKit, Kotlin, Java, Android, iOS, Django, Flask, Rails, Spring, .NET, Go, Rust, Node.js, Docker, Kubernetes, SQL/NoSQL, GraphQL, etc.), adapt the optimized prompt's terminology and structure to match that technology's conventions and idioms.
            Never assume a stack that wasn't stated. Do not default to "frontend," "web," or any other domain just because it's common — only adapt based on explicit or unambiguous signals in my prompt.
            Handle multi-stack prompts. If more than one technology is mentioned (e.g., a full-stack or cross-platform task), reflect all of them appropriately instead of collapsing to just one.
            If no technology is specified at all, keep the optimized prompt fully generic and flag the missing stack/language/framework information under "Important Notes" (per point 6 above).
            """
        ),
    ]
}
