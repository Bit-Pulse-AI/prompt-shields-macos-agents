import Foundation

/// The four onboarding steps from the Feb 2025 redesign (PRD PS-04/05/06).
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case howItWorks = 1
    case permission = 2
    case ahaMoment = 3

    var id: Int { rawValue }

    var progress: Double {
        Double(rawValue) / Double(OnboardingStep.allCases.count - 1)
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}

/// Local-only flag — persisted per Mac user, not synced to backend.
enum OnboardingPersistence {
    private static let key = "ai.bit-pulse.promptshields.hasCompletedOnboarding"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
