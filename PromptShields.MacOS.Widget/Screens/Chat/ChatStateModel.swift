import Foundation
import os
import SwiftUI

// State for the floating Chat panel — Promptly's free-form Q&A surface.
//
// Two persisted pieces:
//   - `customInstructions` — user-defined reusable system prompts (e.g.
//     "Always respond in bullet points", "Translate to Norwegian"). Stored
//     in UserDefaults as a JSON-encoded array of CustomInstruction.
//   - `activeInstructionIds` — which instructions are currently switched on.
//     Stored separately so toggling doesn't rewrite the whole list.
//
// Conversation history is in-memory only for v1 — restart wipes the
// scrollback. SwiftData-backed history is a follow-up once we know what
// surface the user actually wants (per-window? per-app context?).

struct CustomInstruction: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var label: String          // shown on the chip (e.g. "Concise")
    var instruction: String    // the actual text prepended to the LLM call

    init(id: String = UUID().uuidString, label: String, instruction: String) {
        self.id = id
        self.label = label
        self.instruction = instruction
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant, error }

    let id: UUID
    let role: Role
    var text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = .now) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

@MainActor
final class ChatStateModel: ObservableObject {
    // MARK: - Persisted

    @Published private(set) var customInstructions: [CustomInstruction]
    @Published private(set) var activeInstructionIds: Set<String>

    // MARK: - In-memory

    @Published var isExpanded: Bool = false      // floating button vs full panel
    @Published var messages: [ChatMessage] = []
    @Published var isResponding: Bool = false
    @Published var draftText: String = ""

    // MARK: - Init

    private static let instructionsKey = "ai.bit-pulse.promptly.chat.customInstructions"
    private static let activeIdsKey = "ai.bit-pulse.promptly.chat.activeInstructionIds"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "ChatStateModel"
    )

    init() {
        let stored = Self.loadInstructions()
        if stored.isEmpty {
            self.customInstructions = Self.starterInstructions
            Self.saveInstructions(Self.starterInstructions)
        } else {
            self.customInstructions = stored
        }
        self.activeInstructionIds = Self.loadActiveIds()
    }

    // MARK: - Custom instruction CRUD

    func addInstruction(_ ci: CustomInstruction) {
        customInstructions.append(ci)
        Self.saveInstructions(customInstructions)
    }

    func updateInstruction(_ ci: CustomInstruction) {
        guard let i = customInstructions.firstIndex(where: { $0.id == ci.id }) else { return }
        customInstructions[i] = ci
        Self.saveInstructions(customInstructions)
    }

    func deleteInstruction(_ id: String) {
        customInstructions.removeAll { $0.id == id }
        activeInstructionIds.remove(id)
        Self.saveInstructions(customInstructions)
        Self.saveActiveIds(activeInstructionIds)
    }

    func toggleActive(_ id: String) {
        if activeInstructionIds.contains(id) {
            activeInstructionIds.remove(id)
        } else {
            activeInstructionIds.insert(id)
        }
        Self.saveActiveIds(activeInstructionIds)
    }

    func isActive(_ id: String) -> Bool {
        activeInstructionIds.contains(id)
    }

    // MARK: - Conversation API

    func appendUserMessage(_ text: String) -> ChatMessage {
        let msg = ChatMessage(role: .user, text: text)
        messages.append(msg)
        return msg
    }

    func appendAssistant(_ text: String) {
        messages.append(ChatMessage(role: .assistant, text: text))
    }

    func appendError(_ text: String) {
        messages.append(ChatMessage(role: .error, text: text))
    }

    func clearConversation() {
        messages.removeAll()
    }

    /// Builds the prompt to send to the LLM: each enabled custom
    /// instruction is prepended as a system-style line, then a separator,
    /// then the user's message. The Chat suggestion type's prompt template
    /// is just `{{TEXT}}` so we control the structure here.
    func composedPrompt(for userText: String) -> String {
        let active = customInstructions.filter { activeInstructionIds.contains($0.id) }
        guard !active.isEmpty else { return userText }
        let header = active.map { "[Instruction] \($0.instruction)" }.joined(separator: "\n")
        return "\(header)\n\n---\n\n\(userText)"
    }

    // MARK: - Persistence

    private static func loadInstructions() -> [CustomInstruction] {
        guard let data = UserDefaults.standard.data(forKey: instructionsKey),
              let decoded = try? JSONDecoder().decode([CustomInstruction].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveInstructions(_ items: [CustomInstruction]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: instructionsKey)
        }
    }

    private static func loadActiveIds() -> Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: activeIdsKey) ?? []
        return Set(raw)
    }

    private static func saveActiveIds(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: activeIdsKey)
    }

    // MARK: - Starter pack

    /// Six common-sense presets so the user has something to click on
    /// the first time they open the chat. They're regular instructions
    /// — fully editable / deletable.
    private static let starterInstructions: [CustomInstruction] = [
        .init(label: "Concise", instruction: "Reply as concisely as possible without losing meaning."),
        .init(label: "Bullet points", instruction: "Format the answer as a bulleted list."),
        .init(label: "Formal tone", instruction: "Reply in a professional, formal register."),
        .init(label: "Plain English", instruction: "Avoid jargon. Explain in plain English."),
        .init(label: "Norwegian", instruction: "Respond in Norwegian (Bokmål)."),
        .init(label: "Code only", instruction: "Reply with code only, no prose explanations.")
    ]
}
