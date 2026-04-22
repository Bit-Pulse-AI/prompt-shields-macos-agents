import SwiftUI

struct OnboardingHowItWorksStep: View {
    private let steps: [(number: Int, title: String, body: String)] = [
        (1, "You type a prompt",
         "As you write in any AI tool, Prompt Shields analyses what you're about to send — completely locally on your Mac."),
        (2, "We detect & clean risks",
         "Names, emails, financial data, or policy violations are flagged. You see a suggestion — but nothing is changed without your approval."),
        (3, "Better prompt, safer send",
         "Accept, edit, or ignore our suggestion. Your AI gets the improved prompt. Your data stays protected.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: PSSpacing.lg) {
            OnboardingEyebrow(text: "How it works")
            OnboardingTitle(firstLine: "Works invisibly,", secondLine: "every time you type", italicAccent: false)
            OnboardingBodyText(text: "Here's exactly what happens when you write a prompt in ChatGPT, Notion, or any AI tool.")

            VStack(spacing: PSSpacing.lg) {
                ForEach(steps, id: \.number) { step in
                    stepCard(number: step.number, title: step.title, body: step.body)
                }
            }
            .padding(.top, PSSpacing.xs)
        }
    }

    private func stepCard(number: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: PSSpacing.lg) {
            Text("\(number)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.psBlue)
                .frame(width: 28, height: 28)
                .background(Color.psBlueMid)
                .clipShape(RoundedRectangle(cornerRadius: PSRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.psText)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.psText2)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.psBg)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                .stroke(Color.psBorder, lineWidth: 1)
        )
    }
}
