import SwiftUI

// Shared chrome for the onboarding card: top progress bar, body container,
// footer with dots + button row. Each step provides its own body content.

struct OnboardingCard<Content: View>: View {
    let step: OnboardingStep
    let onBack: (() -> Void)?
    let onPrimary: () -> Void
    let primaryLabel: String
    let secondaryLabel: String?
    let onSecondary: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        step: OnboardingStep,
        primaryLabel: String,
        onPrimary: @escaping () -> Void,
        onBack: (() -> Void)? = nil,
        secondaryLabel: String? = nil,
        onSecondary: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.step = step
        self.primaryLabel = primaryLabel
        self.onPrimary = onPrimary
        self.onBack = onBack
        self.secondaryLabel = secondaryLabel
        self.onSecondary = onSecondary
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            // 3px top progress bar
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.psBg3)
                        .frame(height: 3)
                    LinearGradient(
                        colors: [Color.psBlue, Color(hex: "3B82F6")],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * step.progress, height: 3)
                    .animation(.easeInOut(duration: 0.3), value: step)
                }
            }
            .frame(height: 3)

            content()
                .padding(.horizontal, 40)
                .padding(.top, 40)
                .padding(.bottom, 24)

            Divider().background(Color.psBg3)

            // Footer: dots + buttons
            HStack {
                OnboardingDots(current: step)
                Spacer()
                footerButtons
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
        .frame(width: 580)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.xl, style: .continuous)
                .stroke(Color.psBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 24, x: 0, y: 16)
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 4)
    }

    @ViewBuilder
    private var footerButtons: some View {
        HStack(spacing: 10) {
            if let back = onBack {
                Button(action: back) {
                    Text("← Back")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.psText2)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Color.psBg)
                        .clipShape(RoundedRectangle(cornerRadius: PSRadius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PSRadius.sm, style: .continuous)
                                .stroke(Color.psBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            } else if let label = secondaryLabel, let action = onSecondary {
                Button(action: action) {
                    Text(label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.psText3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
            }

            Button(action: onPrimary) {
                Text(primaryLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.psBlue)
                    .clipShape(RoundedRectangle(cornerRadius: PSRadius.sm, style: .continuous))
                    .shadow(color: Color.psBlue.opacity(0.32), radius: 6, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }
}

struct OnboardingDots: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { step in
                Capsule()
                    .fill(step == current ? Color.psBlue : Color.psBorder2)
                    .frame(width: step == current ? 18 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.3), value: current)
            }
        }
    }
}

// Convenience text components used across steps.

struct OnboardingEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Color.psBlue.opacity(0.8))
    }
}

struct OnboardingTitle: View {
    let firstLine: String
    let secondLine: String
    let italicAccent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(firstLine)
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(Color.psText)
            if italicAccent {
                Text(secondLine)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(Color.psBlue)
            } else {
                Text(secondLine)
                    .font(.system(size: 26, weight: .regular, design: .serif))
                    .foregroundStyle(Color.psText)
            }
        }
        .lineSpacing(4)
    }
}

struct OnboardingBodyText: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Color.psText2)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
    }
}
