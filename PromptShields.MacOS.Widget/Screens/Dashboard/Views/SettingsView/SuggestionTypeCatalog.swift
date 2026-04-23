import Foundation

// Static display-time metadata for the 13 suggestion types from the PRD (PS-10).
// Applied as an overlay on existing `SuggestionType` records — the persistence
// model is untouched, so custom user types keep working. Lookup is by
// `typeKey` first (stable identifier), then by exact `name` match.

struct SuggestionTypeMetadata: Sendable {
    let emoji: String
    let summary: String
    let before: String
    let after: String
    /// When true, this type is treated as a default-seeded one — Promptly
    /// will auto-create it on first launch if the backend doesn't already
    /// return a type with a matching key. Used by Redaction so PII
    /// protection is available out-of-the-box (per Jun's product call).
    let isDefaultSeeded: Bool
    /// The prompt template to seed with, if `isDefaultSeeded` is true.
    /// Uses `{{TEXT}}` as the placeholder per SuggestionType.textPlaceholder.
    let seedPromptTemplate: String?

    init(
        emoji: String,
        summary: String,
        before: String,
        after: String,
        isDefaultSeeded: Bool = false,
        seedPromptTemplate: String? = nil
    ) {
        self.emoji = emoji
        self.summary = summary
        self.before = before
        self.after = after
        self.isDefaultSeeded = isDefaultSeeded
        self.seedPromptTemplate = seedPromptTemplate
    }
}

enum SuggestionTypeCatalog {

    /// typeKey used for the Redaction seed. Kept as a constant because
    /// both the seeder and the ActionView reorder consult it.
    static let redactionTypeKey = "redaction"

    static let redactionSeedPromptTemplate = """
    Detect and redact all personal, confidential, or sensitive data.
    Replace with placeholders (e.g., [NAME], [EMAIL], [ACCOUNT_ID]) and preserve readability.

    Input:
    {{TEXT}}
    """

    /// Types we guarantee exist on first launch via auto-seed.
    static var defaultSeededMetadata: [(displayName: String, category: String, meta: SuggestionTypeMetadata)] {
        [
            (displayName: "Redaction", category: "Security & Compliance", meta: entries[normalize(redactionTypeKey)]!)
        ]
    }

    // Key: normalized typeKey or name
    private static let entries: [String: SuggestionTypeMetadata] = {
        let defs: [(keys: [String], meta: SuggestionTypeMetadata)] = [
            (["redaction", "redact"], .init(
                emoji: "🔒",
                summary: "Automatically redact or mask PII and sensitive data (this runs on every action by default).",
                before: "Send the Q3 summary to anna.berg@clientcorp.com — note she's at +47 912 34 567.",
                after: "Send the Q3 summary to [EMAIL] — note she's at [PHONE].",
                isDefaultSeeded: true,
                seedPromptTemplate: """
                Detect and redact all personal, confidential, or sensitive data.
                Replace with placeholders (e.g., [NAME], [EMAIL], [ACCOUNT_ID]) and preserve readability.

                Input:
                {{TEXT}}
                """
            )),
            (["detect_risk", "detectrisk", "detect risk"], .init(
                emoji: "🛡️",
                summary: "Scans for sensitive or confidential data before it leaves your Mac — PII, financial figures, internal names, API keys.",
                before: "Q3 revenue was €2.4M, help analyse?",
                after: "Flags €2.4M as financial data"
            )),
            (["optimise_for_model", "optimizeformodel", "optimise for model", "optimize for model"], .init(
                emoji: "⚡",
                summary: "Rewrites your prompt to get better results from the specific AI you're using.",
                before: "Make this shorter",
                after: "Condense the following to under 50 words while preserving the key argument:"
            )),
            (["shorten"], .init(
                emoji: "✂️",
                summary: "Removes redundant words so the AI focuses on what matters.",
                before: "I was wondering if you could maybe help me with writing something like a short summary",
                after: "Write a concise summary of:"
            )),
            (["align_with_policy", "alignwithpolicy", "align with policy"], .init(
                emoji: "📜",
                summary: "Flags prompts that may conflict with your company's AI usage policy.",
                before: "Summarise this legal contract and give me a recommendation",
                after: "Adds policy warning before sending"
            )),
            (["translate"], .init(
                emoji: "🌐",
                summary: "Translates your prompt to the language most suitable for the model.",
                before: "Oversett dette til norsk",
                after: "Translated version for optimal response"
            )),
            (["rephrase_for_role", "rephraseforrole", "rephrase for role"], .init(
                emoji: "🎭",
                summary: "Adjusts tone for your professional context.",
                before: "Fix the bug in this function",
                after: "Review the following function for logical errors and suggest a corrected version with explanation:"
            )),
            (["simplify"], .init(
                emoji: "📖",
                summary: "Breaks down complex or jargon-heavy prompts.",
                before: "Utilise your capabilities to synthesise an executive-level artefact…",
                after: "Write a 1-page executive summary of:"
            )),
            (["format_output", "formatoutput", "format output"], .init(
                emoji: "📋",
                summary: "Adds formatting instructions to get structured, usable responses.",
                before: "Tell me about AI risks",
                after: "Describe AI risks in a numbered list with a one-sentence summary for each"
            )),
            (["elaborate"], .init(
                emoji: "🔍",
                summary: "Expands a brief prompt to give the AI more context.",
                before: "Write an email",
                after: "Adds context about tone, audience, length, and goal"
            )),
            (["combine_prompts", "combineprompts", "combine prompts"], .init(
                emoji: "🔗",
                summary: "Merges multiple related prompts into one efficient request.",
                before: "Two separate prompts",
                after: "Single combined prompt"
            )),
            (["formalise", "formalize"], .init(
                emoji: "👔",
                summary: "Elevates casual language to professional register.",
                before: "hey can u help me write smth for my boss",
                after: "Please help me draft a professional message for my manager regarding:"
            )),
            (["add_safety_guardrails", "addsafetyguardrails", "add safety guardrails", "safety_guardrails"], .init(
                emoji: "🦺",
                summary: "Appends instructions that prevent harmful or biased AI outputs.",
                before: "Original prompt",
                after: "Prompt + \"Ensure the response is factual, balanced, and avoids harmful content.\""
            )),
            (["sanitise", "sanitize"], .init(
                emoji: "🧼",
                summary: "Replaces real names, companies, and numbers with generic placeholders.",
                before: "Anna Berg from Equinor asked about our NOK 45M contract",
                after: "[Name] from [Company] asked about our [contract value] contract"
            ))
        ]

        var result: [String: SuggestionTypeMetadata] = [:]
        for def in defs {
            for key in def.keys {
                result[normalize(key)] = def.meta
            }
        }
        return result
    }()

    static func metadata(for type: SuggestionType) -> SuggestionTypeMetadata? {
        if let meta = entries[normalize(type.model.typeKey)] {
            return meta
        }
        return entries[normalize(type.model.name)]
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
