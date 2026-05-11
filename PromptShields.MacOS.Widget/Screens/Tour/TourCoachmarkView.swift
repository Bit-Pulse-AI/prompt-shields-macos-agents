import SwiftUI

// The popover that sits next to the spotlight. Visual spec from
// docs/guided-tour-design.md §6 — 280pt wide, surface-coloured, 1pt
// border, 16pt shadow. Step counter top-left, Skip + Next at the
// bottom.

struct TourCoachmarkView: View {
    let step: TourStep
    let tour: Tour
    let stepIndex: Int
    let onNext: () -> Void
    let onSkip: () -> Void

    private var primaryLabel: String { step.primaryLabel ?? "Next →" }
    private var secondaryLabel: String? { step.secondaryLabel ?? "Skip tour" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 6) {
                Text(stepCounter)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.psText3)
                Spacer(minLength: 0)
                if tour.steps.count > 1 {
                    progressDots
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.psText)
                Text(step.body)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.psText2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let secondaryLabel {
                    Button(action: onSkip) {
                        Text(secondaryLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.psText3)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                Button(action: onNext) {
                    Text(primaryLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.psBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.psBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
    }

    private var stepCounter: String {
        "\(stepIndex + 1) / \(tour.steps.count)"
    }

    private var progressDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<tour.steps.count, id: \.self) { i in
                Capsule()
                    .fill(i == stepIndex ? Color.psBlue : Color.psBorder2)
                    .frame(width: i == stepIndex ? 14 : 5, height: 5)
                    .animation(.easeInOut(duration: 0.2), value: stepIndex)
            }
        }
    }
}
