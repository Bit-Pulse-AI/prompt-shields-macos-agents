import SwiftUI

// Grammarly-style floating round button. Always visible in the bottom-
// right of the active screen via a `.statusBar`-level NSWindow created
// in MainApp.swift. Click → expands the ChatPanelView.

struct FloatingChatButton: View {
    @EnvironmentObject private var chat: ChatStateModel

    var body: some View {
        if chat.isExpanded {
            ChatPanelView()
                .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
        } else {
            collapsedButton
                .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
        }
    }

    private var collapsedButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                chat.isExpanded = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.psBlue, Color(hex: "3B82F6")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.psBlue.opacity(0.45), radius: 12, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)

                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                if chat.activeInstructionIds.count > 0 {
                    activeInstructionsBadge
                        .frame(width: 18, height: 18)
                        .offset(x: 18, y: -18)
                }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .help("Open Promptly Chat (⌘⇧P)")
        .frame(width: 80, height: 80, alignment: .bottomTrailing)
    }

    /// Shows a subtle count when the user has at least one custom
    /// instruction switched on. Mirrors Grammarly's badge behaviour.
    private var activeInstructionsBadge: some View {
        ZStack {
            Circle().fill(Color.psSurface)
            Text("\(chat.activeInstructionIds.count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.psBlue)
        }
        .overlay(Circle().stroke(Color.psBlue.opacity(0.25), lineWidth: 1))
    }
}
