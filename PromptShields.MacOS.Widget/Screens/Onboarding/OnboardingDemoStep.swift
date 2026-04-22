import SwiftUI

struct OnboardingDemoStep: View {
    @State private var didCopy: Bool = false

    private let promptToCopy = "Write a cold email to john.smith@clientcorp.com about our Q3 results showing €2.4M revenue. Our CEO Anna Berg wants to close by Friday."

    var body: some View {
        VStack(alignment: .leading, spacing: PSSpacing.lg) {
            OnboardingEyebrow(text: "See it in action")
            OnboardingTitle(firstLine: "This is your", secondLine: "aha moment", italicAccent: true)

            (Text("Try it yourself: go to ")
                .foregroundStyle(Color.psText2)
             + Text("chat.openai.com").foregroundStyle(Color.psText).fontWeight(.semibold)
             + Text(" and type this prompt. Watch Prompt Shields catch the risk in real time.")
                .foregroundStyle(Color.psText2))
                .font(.system(size: 15))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)

            demoBox
            resultNote
        }
    }

    private var demoBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("🔴 What Prompt Shields catches")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.psText3)
                Spacer()
                Button(action: copyPrompt) {
                    HStack(spacing: 4) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        Text(didCopy ? "Copied" : "Copy prompt")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(didCopy ? Color.psGreen : Color.psBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, PSSpacing.lg)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.psBg2)

            VStack(alignment: .leading, spacing: 14) {
                label("YOUR PROMPT (WHAT YOU TYPE)")
                promptBox

                HStack(spacing: 8) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Prompt Shields removes sensitive data before sending")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Color.psGreen)
                .frame(maxWidth: .infinity)

                label("SANITISED PROMPT (WHAT AI RECEIVES)")
                cleanBox
            }
            .padding(20)
        }
        .background(Color.psBg)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                .stroke(Color.psBorder, lineWidth: 1)
        )
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Color.psText3)
    }

    // Risky-text spans rendered with strikethrough red highlight.
    private var promptBox: some View {
        let text =
            Text("Write a cold email to ").foregroundStyle(Color.psText2)
            + risky("john.smith@clientcorp.com")
            + Text(" about our Q3 results showing ").foregroundStyle(Color.psText2)
            + risky("€2.4M revenue")
            + Text(". Our CEO ").foregroundStyle(Color.psText2)
            + risky("Anna Berg")
            + Text(" wants to close by Friday.").foregroundStyle(Color.psText2)
        return text
            .font(.system(size: 13, design: .monospaced))
            .lineSpacing(4)
            .padding(.horizontal, PSSpacing.lg)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.psSurface)
            .clipShape(RoundedRectangle(cornerRadius: PSRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PSRadius.md, style: .continuous)
                    .stroke(Color.psBorder2, lineWidth: 1.5)
            )
    }

    private func risky(_ value: String) -> Text {
        Text(value)
            .foregroundStyle(Color.psRed)
            .strikethrough(true, color: Color.psRed)
    }

    private var cleanBox: some View {
        Text("Write a cold email to [client contact] about our Q3 results showing [revenue figure]. Our CEO [name] wants to close by Friday.")
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Color.psGreen)
            .lineSpacing(4)
            .padding(.horizontal, PSSpacing.lg)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.psGreenLight)
            .clipShape(RoundedRectangle(cornerRadius: PSRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PSRadius.md, style: .continuous)
                    .stroke(Color.psGreen.opacity(0.25), lineWidth: 1.5)
            )
    }

    private var resultNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
            Text("The AI still gives you a great email — without knowing any confidential details.")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(Color.psGreen)
        .padding(.horizontal, PSSpacing.lg)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.psGreenLight)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.md, style: .continuous)
                .stroke(Color.psGreen.opacity(0.3), lineWidth: 1)
        )
    }

    private func copyPrompt() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(promptToCopy, forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { didCopy = false }
            }
        }
    }
}
