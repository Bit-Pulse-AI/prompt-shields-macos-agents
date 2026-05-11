import SwiftUI

// Modifier applied to a window's root view. Renders the backdrop +
// spotlight + coachmark when an active step's anchor lives in this
// window. Cross-window steps are handled by individual windows
// listening to Notification.Name.tourActiveStep and applying their own
// `.tourOverlay()` modifier — each window draws whichever step it owns
// an anchor for; everything else is a noop.

struct TourOverlayModifier: ViewModifier {
    @ObservedObject private var coordinator = TourCoordinator.shared

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(TourAnchorPreferenceKey.self) { anchors in
                GeometryReader { proxy in
                    TourOverlayContent(
                        coordinator: coordinator,
                        anchors: anchors,
                        proxy: proxy
                    )
                    // Block taps outside the spotlight unless the step
                    // opts in to interaction. Click-outside-to-dismiss
                    // is handled in TourOverlayContent.
                    .allowsHitTesting(coordinator.isActive)
                }
            }
    }
}

extension View {
    /// Render the tour overlay for any active step whose anchor exists
    /// inside this view's subtree. Should be applied once per window
    /// root.
    func tourOverlay() -> some View {
        modifier(TourOverlayModifier())
    }
}

// MARK: - Overlay content

private struct TourOverlayContent: View {
    @ObservedObject var coordinator: TourCoordinator
    let anchors: [String: Anchor<CGRect>]
    let proxy: GeometryProxy

    var body: some View {
        if let step = coordinator.activeStep,
           let anchor = anchors[step.anchorId] {
            let rect = proxy[anchor].insetBy(dx: -step.resolvedSpotlightPadding,
                                             dy: -step.resolvedSpotlightPadding)
            ZStack {
                TourBackdrop(spotlightRect: rect, allowedInteraction: step.resolvedInteractionAllowed) {
                    // Tap outside spotlight skips the tour (matches
                    // Grammarly). Q3 default; in v2 we may make this
                    // configurable per-step.
                    coordinator.skip()
                }

                TourSpotlightRing(rect: rect)

                TourCoachmarkView(
                    step: step,
                    tour: coordinator.activeTour!,
                    stepIndex: coordinator.activeStepIndex,
                    onNext: { coordinator.next() },
                    onSkip: { coordinator.skip() }
                )
                .position(coachmarkPosition(for: rect, in: proxy.size, placement: step.placement))
                .transition(.opacity.combined(with: .offset(y: 4)))
                .id(step.id) // forces re-mount so animation fires per step
            }
            .animation(.interpolatingSpring(stiffness: 240, damping: 26), value: rect)
            .animation(.easeOut(duration: 0.2), value: step.id)
        }
    }

    /// Position the coachmark relative to the spotlight rect. Auto picks
    /// "below" if there's space, else "above", with leading/trailing
    /// reserved for narrow vertical anchors like sidebar rows.
    private func coachmarkPosition(for rect: CGRect, in size: CGSize,
                                   placement: CoachmarkPlacement) -> CGPoint {
        let coachmarkWidth: CGFloat = 280
        let coachmarkHeight: CGFloat = 140
        let gap: CGFloat = 14

        let resolved: CoachmarkPlacement = {
            if placement != .auto { return placement }
            let spaceBelow = size.height - rect.maxY
            let spaceAbove = rect.minY
            return spaceBelow >= coachmarkHeight + gap ? .below
                : (spaceAbove >= coachmarkHeight + gap ? .above : .trailing)
        }()

        switch resolved {
        case .below:
            return CGPoint(
                x: clamp(rect.midX, low: coachmarkWidth / 2 + gap,
                         high: size.width - coachmarkWidth / 2 - gap),
                y: rect.maxY + gap + coachmarkHeight / 2
            )
        case .above:
            return CGPoint(
                x: clamp(rect.midX, low: coachmarkWidth / 2 + gap,
                         high: size.width - coachmarkWidth / 2 - gap),
                y: rect.minY - gap - coachmarkHeight / 2
            )
        case .trailing:
            return CGPoint(
                x: min(rect.maxX + gap + coachmarkWidth / 2,
                       size.width - coachmarkWidth / 2 - gap),
                y: clamp(rect.midY, low: coachmarkHeight / 2 + gap,
                         high: size.height - coachmarkHeight / 2 - gap)
            )
        case .leading:
            return CGPoint(
                x: max(rect.minX - gap - coachmarkWidth / 2, coachmarkWidth / 2 + gap),
                y: clamp(rect.midY, low: coachmarkHeight / 2 + gap,
                         high: size.height - coachmarkHeight / 2 - gap)
            )
        case .auto:
            // Shouldn't reach — handled above. Centre as a safety net.
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }

    private func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        guard low <= high else { return (low + high) / 2 }
        return Swift.min(Swift.max(value, low), high)
    }
}

// MARK: - Backdrop with destinationOut cutout

private struct TourBackdrop: View {
    let spotlightRect: CGRect
    let allowedInteraction: Bool
    let onTapOutside: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture { onTapOutside() }

            // Punch the cutout. .blendMode(.destinationOut) on the
            // shape inside a .compositingGroup turns the rect into a
            // hole, letting clicks through if the step allows.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .frame(width: spotlightRect.width, height: spotlightRect.height)
                .position(x: spotlightRect.midX, y: spotlightRect.midY)
                .blendMode(.destinationOut)
                .allowsHitTesting(allowedInteraction)
        }
        .compositingGroup()
        .ignoresSafeArea()
    }
}

private struct TourSpotlightRing: View {
    let rect: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.psBlue.opacity(0.6), lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }
}
