import SwiftUI

// SwiftUI AnchorPreference machinery. A view that wants the tour engine
// to spotlight it tags itself with .tourAnchor("activate-shield"). The
// window's root reads the merged [anchorId : Anchor<CGRect>] dictionary
// and asks for the current step's anchor when rendering the overlay.

struct TourAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        // Last-write-wins. Two views shouldn't claim the same id — but
        // if they do, the closer-to-leaf one wins, which is the more
        // useful default.
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Make this view discoverable by the tour engine under the given id.
    /// The id must match an `anchorId` in a step in Tours.json. Multiple
    /// views can share an id; the most-recently-rendered wins.
    func tourAnchor(_ id: String) -> some View {
        anchorPreference(key: TourAnchorPreferenceKey.self,
                         value: .bounds) { [id: $0] }
    }
}
