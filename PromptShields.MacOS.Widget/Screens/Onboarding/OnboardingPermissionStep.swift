import SwiftUI

struct OnboardingPermissionStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: PSSpacing.lg) {
            OnboardingEyebrow(text: "One permission needed")
            OnboardingTitle(firstLine: "Why we need", secondLine: "Accessibility access", italicAccent: false)
            OnboardingBodyText(text: "To read text fields before you send, macOS requires Accessibility permission. Here's exactly what we can and can't do.")

            VStack(spacing: PSSpacing.md) {
                permissionCard(
                    icon: "checkmark.circle.fill",
                    iconBg: Color.psGreenLight,
                    iconColor: Color.psGreen,
                    title: "What we do",
                    body: "Read the text in AI tool input fields (ChatGPT, Notion, etc.) only at the moment you're about to send. We analyse it locally — nothing leaves your Mac without your action.",
                    badge: "✓ Local only · never stored without consent",
                    badgeBg: Color.psGreenLight,
                    badgeColor: Color.psGreen
                )

                permissionCard(
                    icon: "hand.raised.fill",
                    iconBg: Color.psBlueLight,
                    iconColor: Color.psBlue,
                    title: "What we never do",
                    body: "We never read passwords, banking apps, personal messages, emails, or any app not on your approved AI tool list.",
                    badge: "✓ Allowlist controlled · you choose which apps",
                    badgeBg: Color.psBlueLight,
                    badgeColor: Color.psBlue
                )
            }
            .padding(.top, PSSpacing.xs)

            trustNote
        }
    }

    private func permissionCard(
        icon: String, iconBg: Color, iconColor: Color,
        title: String, body: String,
        badge: String, badgeBg: Color, badgeColor: Color
    ) -> some View {
        HStack(alignment: .top, spacing: PSSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background(iconBg)
                .clipShape(RoundedRectangle(cornerRadius: PSRadius.md - 2, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.psText)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.psText2)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(badge)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badgeBg)
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.psBg)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.lg, style: .continuous)
                .stroke(Color.psBorder, lineWidth: 1)
        )
    }

    private var trustNote: some View {
        HStack(alignment: .top, spacing: PSSpacing.md) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.psAmber)
                .padding(.top, 2)
            Text("On the next screen, macOS will ask to confirm this permission. After clicking \"Open System Settings\", find Promptly in the list and toggle it on.")
                .font(.system(size: 13))
                .foregroundStyle(Color.psAmber)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PSSpacing.lg)
        .padding(.vertical, 12)
        .background(Color.psAmberLight)
        .clipShape(RoundedRectangle(cornerRadius: PSRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PSRadius.md, style: .continuous)
                .stroke(Color.psAmberBorder, lineWidth: 1)
        )
    }
}
