import SwiftUI

// Top-level onboarding container. Presented as a sheet from `MainWindowContent`.
// On completion, marks `OnboardingPersistence.hasCompleted` so it never re-appears
// unless the user explicitly opens it from Help → "Show onboarding…".

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @EnvironmentObject private var mainState: MainStateModel

    @State private var step: OnboardingStep = .welcome
    @State private var loginInProgress: Bool = false
    @State private var loginErrorMessage: String?

    private var isLoggedIn: Bool {
        if case .loggedIn = mainState.authState { return true }
        return false
    }

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
        // Step 3 (permission trust) has the most content; size the sheet
        // to fit it comfortably without the card clipping at the top.
        // Steps with less content are vertically centred via the .frame
        // above.
        .frame(minWidth: 720, minHeight: 760)
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
            // Step 4 is the merged "demo + login" screen. The CTA reads
            // "Log in & turn on Promptly" until Auth0 succeeds, then
            // collapses to "Turn on Promptly" — same single tap to
            // activate the shield.
            OnboardingCard(
                step: step,
                primaryLabel: ahaMomentPrimaryLabel,
                onPrimary: handleAhaMomentPrimary,
                onBack: goBack
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    OnboardingDemoStep()
                    if let error = loginErrorMessage {
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(.top, 8)
                    }
                }
            }
        }
    }

    private var ahaMomentPrimaryLabel: String {
        if loginInProgress { return "Signing in…" }
        return isLoggedIn ? "Turn on Promptly" : "Log in & turn on Promptly"
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
        // Surface the macOS Accessibility pane in case the user wants to
        // grant now — but never block the onboarding flow on the result.
        // If they don't grant, the persistent amber banner in the Control
        // Panel keeps reminding them; if they do, the periodic
        // refreshPermissionState polling picks it up and the Activate
        // button switches automatically. Either way, advance to step 4.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        accessibilityManager.refreshPermissionState()
        advance()
    }

    private func handleActivate() {
        if accessibilityManager.hasAccessibilityPermission {
            accessibilityManager.enableMonitoring()
        }
        complete()
    }

    /// Step 4 primary action. If already logged in (e.g. user re-opened
    /// onboarding via Help → Show Onboarding…) just activates the shield.
    /// Otherwise runs the Auth0 login flow inline; on success activates
    /// + completes; on failure surfaces the error and lets the user
    /// retry without leaving onboarding.
    private func handleAhaMomentPrimary() {
        guard !loginInProgress else { return }

        if isLoggedIn {
            handleActivate()
            return
        }

        loginErrorMessage = nil
        loginInProgress = true
        Task { @MainActor in
            defer { loginInProgress = false }
            do {
                let state = try await AuthenticationManagerImpl.shared.login()
                mainState.authState = state
                // Only auto-activate if the user landed all the way at
                // .loggedIn. .acceptTerms means the dashboard will route
                // to the T&C view next — let monitoring wait until they
                // explicitly toggle it on after accepting.
                if isLoggedIn, accessibilityManager.hasAccessibilityPermission {
                    accessibilityManager.enableMonitoring()
                }
                complete()
            } catch {
                loginErrorMessage = "Login failed: \(error.localizedDescription). Try again or use Help → Skip Login (Dev) for QA."
            }
        }
    }

    private func complete() {
        OnboardingPersistence.markCompleted()
        dismiss()
    }
}
