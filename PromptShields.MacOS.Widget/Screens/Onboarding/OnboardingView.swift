import SwiftUI

// Top-level onboarding container. Presented as a sheet from `MainWindowContent`.
// On completion, marks `OnboardingPersistence.hasCompleted` so it never re-appears
// unless the user explicitly opens it from Help → "Show onboarding…".

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl

    @State private var step: OnboardingStep = .welcome

    var body: some View {
        ZStack {
            Color(red: 0.969, green: 0.965, blue: 0.953, opacity: 0.96)
                .ignoresSafeArea()

            currentStepCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 12)),
                        removal: .opacity
                    )
                )
                .animation(.easeOut(duration: 0.25), value: step)
        }
        .frame(minWidth: 720, minHeight: 600)
        .onChange(of: accessibilityManager.hasAccessibilityPermission) { _, granted in
            // PS-05: if permission is already granted, skip step 3 the next time it would appear.
            if granted, step == .permission {
                advance()
            }
        }
    }

    @ViewBuilder
    private var currentStepCard: some View {
        switch step {
        case .welcome:
            OnboardingCard(
                step: step,
                primaryLabel: "Get started →",
                onPrimary: advance,
                secondaryLabel: "Skip setup",
                onSecondary: complete
            ) {
                OnboardingWelcomeStep()
            }

        case .howItWorks:
            OnboardingCard(
                step: step,
                primaryLabel: "Next →",
                onPrimary: advance,
                onBack: goBack
            ) {
                OnboardingHowItWorksStep()
            }

        case .permission:
            // If already granted, fast-forward.
            if accessibilityManager.hasAccessibilityPermission {
                Color.clear.onAppear { advance() }
            } else {
                OnboardingCard(
                    step: step,
                    primaryLabel: "I understand, continue →",
                    onPrimary: handlePermissionContinue,
                    onBack: goBack
                ) {
                    OnboardingPermissionStep()
                }
            }

        case .ahaMoment:
            OnboardingCard(
                step: step,
                primaryLabel: "Activate Shield 🛡️",
                onPrimary: handleActivate,
                onBack: goBack
            ) {
                OnboardingDemoStep()
            }
        }
    }

    private func advance() {
        if let next = step.next {
            withAnimation { step = next }
        } else {
            complete()
        }
    }

    private func goBack() {
        if let previous = step.previous {
            withAnimation { step = previous }
        }
    }

    private func handlePermissionContinue() {
        // Triggers the macOS accessibility prompt (and opens System Settings).
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        accessibilityManager.refreshPermissionState()
        // We don't auto-advance — user returns to the app after granting and the
        // `onChange(of: hasAccessibilityPermission)` listener moves them along.
    }

    private func handleActivate() {
        if accessibilityManager.hasAccessibilityPermission {
            accessibilityManager.enableMonitoring()
        }
        complete()
    }

    private func complete() {
        OnboardingPersistence.markCompleted()
        dismiss()
    }
}
