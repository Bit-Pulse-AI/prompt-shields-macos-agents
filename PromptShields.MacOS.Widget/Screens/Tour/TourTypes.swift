import Foundation

// Wire-format mirrors of Resources/Tours.json. v2's tutorial overlay
// will fetch identical shape from the dashboard — see
// docs/guided-tour-design.md §2.

enum TourTrigger: String, Codable, Sendable {
    case manual                       // Help menu only
    case firstDashboardMount
    case firstChatExpand
    case firstActivityLogVisit
}

enum CoachmarkPlacement: String, Codable, Sendable {
    case auto, above, below, leading, trailing
}

struct TourStep: Codable, Sendable, Identifiable, Equatable, Hashable {
    let id: String
    let anchorId: String
    let placement: CoachmarkPlacement
    let title: String
    let body: String
    let primaryLabel: String?
    let secondaryLabel: String?
    let spotlightPadding: Double?
    let interactionAllowed: Bool?

    /// Spotlight inset in points around the anchor frame. Default 8.
    var resolvedSpotlightPadding: CGFloat { CGFloat(spotlightPadding ?? 8) }

    /// Whether the user can click the underlying control while the
    /// coachmark is up — for steps where the coordinator auto-advances
    /// on a real action (PR-1 in the design doc).
    var resolvedInteractionAllowed: Bool { interactionAllowed ?? false }
}

struct Tour: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let title: String
    let trigger: TourTrigger
    let steps: [TourStep]
}

struct TourCatalogPayload: Codable, Sendable {
    let tours: [Tour]
}
