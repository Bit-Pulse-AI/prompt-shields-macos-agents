import SwiftUI
import os

// Expanded chat surface — sits where the FloatingChatButton was, sized
// like a small sidebar (Grammarly's right-rail proportions). Three
// sections top→bottom:
//   1. Header (title, collapse, clear)
//   2. Active-instructions chip bar (toggleable presets)
//   3. Conversation scroll
//   4. Composer (multiline input + send)

struct ChatPanelView: View {
    @EnvironmentObject private var chat: ChatStateModel
    @EnvironmentObject private var overlayState: OverlayStateModel
    @Environment(\.suggestionDomainService) private var suggestionDomainService
    @Environment(\.profileDomainService) private var profileDomainService

    @FocusState private var inputFocused: Bool

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "ChatPanelView"
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.psBorder)
            instructionChips
            Divider().background(Color.psBorder)
            conversation
            Divider().background(Color.psBorder)
            composer
        }
        .frame(width: 380, height: 540)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                .stroke(Color.psBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .onAppear { inputFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.psBlue, Color(hex: "3B82F6")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Promptly Chat")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.psText)
                Text("Ask anything. Apply instructions for tone, format, language.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.psText3)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                chat.clearConversation()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.psText3)
            }
            .buttonStyle(.plain)
            .help("Clear conversation")
            .disabled(chat.messages.isEmpty)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    chat.isExpanded = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.psText3)
            }
            .buttonStyle(.plain)
            .help("Collapse chat (⌘⇧P)")
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.psBg2)
    }

    // MARK: - Instruction chips

    private var instructionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chat.customInstructions) { ci in
                    instructionChip(ci)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color.psBg)
    }

    private func instructionChip(_ ci: CustomInstruction) -> some View {
        let active = chat.isActive(ci.id)
        return Button {
            chat.toggleActive(ci.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(ci.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(active ? .white : Color.psText2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(active ? Color.psBlue : Color.psSurface)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(active ? Color.psBlue : Color.psBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(ci.instruction)
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if chat.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(chat.messages) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }
                    }
                    if chat.isResponding {
                        thinkingIndicator
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: .infinity)
            .background(Color.psSurface)
            .onChange(of: chat.messages.count) { _, _ in
                if let last = chat.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 22))
                .foregroundStyle(Color.psBlue.opacity(0.5))
            Text("Ask Promptly")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.psText)
            Text("Type a question or paste a prompt. Toggle the chips above to apply instructions.")
                .font(.system(size: 11))
                .foregroundStyle(Color.psText3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func messageBubble(_ msg: ChatMessage) -> some View {
        HStack(alignment: .top) {
            if msg.role == .user { Spacer(minLength: 32) }
            VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 4) {
                Text(msg.text)
                    .font(.system(size: 12))
                    .foregroundStyle(msg.role == .error ? Color.psRed
                                     : msg.role == .user ? .white : Color.psText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(bubbleBackground(for: msg.role))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .textSelection(.enabled)
            }
            if msg.role != .user { Spacer(minLength: 32) }
        }
    }

    private func bubbleBackground(for role: ChatMessage.Role) -> Color {
        switch role {
        case .user: return Color.psBlue
        case .assistant: return Color.psBg
        case .error: return Color.psRedLight
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.psText3)
                    .frame(width: 5, height: 5)
                    .opacity(0.4)
                    .scaleEffect(thinkingScale(i))
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.15),
                        value: chat.isResponding
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.psBg)
        .clipShape(Capsule())
    }

    private func thinkingScale(_ i: Int) -> CGFloat {
        chat.isResponding ? 1.4 : 1.0
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $chat.draftText)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .background(Color.psBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.psBorder, lineWidth: 1)
                )
                .frame(minHeight: 36, maxHeight: 100)
                .focused($inputFocused)
                .overlay(alignment: .topLeading) {
                    if chat.draftText.isEmpty {
                        Text("Ask anything…")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.psText3)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? Color.psBlue : Color.psBorder2)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.psBg2)
    }

    private var canSend: Bool {
        !chat.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !chat.isResponding
    }

    // MARK: - Send

    @MainActor
    private func send() async {
        let trimmed = chat.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chat.isResponding else { return }

        chat.draftText = ""
        _ = chat.appendUserMessage(trimmed)
        chat.isResponding = true

        let prompt = chat.composedPrompt(for: trimmed)
        let appName = overlayState.elementInfo?.applicationName ?? "Promptly Chat"

        do {
            let suggestion = try await suggestionDomainService.process(
                text: prompt,
                suggestionGroupId: profileDomainService.currentProfile.model.defaultSuggestionGroupId,
                teamId: profileDomainService.currentProfile.model.defaultTeamId,
                suggestionType: SuggestionTypeCatalog.chatTypeKey,
                application: appName
            )
            chat.appendAssistant(suggestion.model.suggestedText)
        } catch {
            logger.error("Chat send failed: \(error.localizedDescription)")
            chat.appendError("Couldn't reach Promptly: \(error.localizedDescription)")
        }
        chat.isResponding = false
    }
}
