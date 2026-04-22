import SwiftUI

struct OnboardingWelcomeStep: View {
    @State private var pulseRing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: PSSpacing.xl) {
            heroIcon
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, PSSpacing.sm)

            OnboardingEyebrow(text: "Welcome")
            OnboardingTitle(firstLine: "Your AI prompts,", secondLine: "protected.", italicAccent: true)

            OnboardingBodyText(text: "Prompt Shields quietly monitors what you send to AI tools — catching risks, removing sensitive data, and improving your prompts before they leave your computer. Setup takes 2 minutes.")

            featurePills
                .padding(.top, PSSpacing.xs)
        }
        .onAppear { pulseRing = true }
    }

    private var heroIcon: some View {
        ZStack {
            Circle()
                .stroke(Color.psBlue.opacity(0.15), lineWidth: 2)
                .frame(width: 88, height: 88)
                .scaleEffect(pulseRing ? 1.4 : 1.0)
                .opacity(pulseRing ? 0.0 : 1.0)
                .animation(
                    .easeOut(duration: 2.5).repeatForever(autoreverses: false),
                    value: pulseRing
                )

            Circle()
                .fill(Color.psBlueLight)
                .frame(width: 88, height: 88)

            Image(systemName: "shield.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.psBlue)
        }
        .frame(width: 140, height: 110)
    }

    private var featurePills: some View {
        HStack(spacing: 10) {
            pill(dot: Color.psRed, text: "Detects sensitive data")
            pill(dot: Color.psBlue, text: "Improves prompts")
            pill(dot: Color.psGreen, text: "Works across all apps")
        }
    }

    private func pill(dot: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.psText2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.psBg2)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.psBorder, lineWidth: 1))
    }
}
