import SwiftUI

struct TermsAndConditionsView: View {
    /// Your markup/terms text (plain text is fine; you can also pass markdown-rendered text yourself)
    let termsText: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    @EnvironmentObject private var globalMainStateModel: MainStateModel
    @State private var reachedBottom = false
    @State private var viewportHeight: CGFloat = 0
    @State private var bottomSentinelMinY: CGFloat = .greatestFiniteMagnitude

    private let scrollSpaceName = "terms-scroll-space"
    private let bottomTolerance: CGFloat = 12

    var body: some View {
        VStack(spacing: 12) {
            header

            termsScroller
            if reachedBottom {
                unlockHint
            }

            actionButtons
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: viewportHeight) { _, _ in
            updateReachedBottom()
        }
        .onChange(of: bottomSentinelMinY) { _, _ in
            updateReachedBottom()
        }
    }

    // MARK: UI

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Promptshields Terms & Conditions")
                .font(.title3.weight(.semibold))

            Text("Please read the full agreement. Accept and Decline will become available once you reach the end.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var termsScroller: some View {
        GeometryReader { outerGeo in
            // The outerGeo is our visible viewport for the scroll area.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(termsText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Bottom sentinel: we measure its position, but we do NOT use onAppear.
                    BottomSentinel()
                }
                .padding(16)
                .background(
                    SentinelPositionReader(space: scrollSpaceName)
                )
            }
            .coordinateSpace(name: scrollSpaceName)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            )
            .onAppear {
                viewportHeight = outerGeo.size.height
                updateReachedBottom()
            }
            .onChange(of: outerGeo.size.height) { newValue, _ in
                viewportHeight = newValue
                updateReachedBottom()
            }
            // Listen for sentinel position updates via preference
            .onPreferenceChange(BottomSentinelMinYKey.self) { minY in
                bottomSentinelMinY = minY
            }
        }
        .frame(minHeight: 420)
    }

    private var unlockHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text("You’ve reached the end of the agreement.")
        }
        .font(.footnote)
        .foregroundStyle(reachedBottom ? .green : .secondary)
        .animation(.easeInOut(duration: 0.15), value: reachedBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button("Decline") {
                onDecline()
            }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(ButtonStyleWhite())

            Spacer()

            Button("Accept") {
                onAccept()
            }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(ButtonStyleBlack())
                .disabled(!reachedBottom)
        }
    }

    // MARK: Logic

    private func updateReachedBottom() {
        guard viewportHeight > 0, bottomSentinelMinY.isFinite else { return }
        let reached = bottomSentinelMinY <= (viewportHeight + bottomTolerance)
        if reached != reachedBottom {
            reachedBottom = reached
        }
    }
}

// MARK: - Sentinel view and measurement

private struct BottomSentinel: View {
    var body: some View {
        Color.clear
            .frame(height: 1)
            .accessibilityHidden(true)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: BottomSentinelMinYKey.self,
                            value: geo.frame(in: .named("terms-scroll-space")).minY
                        )
                }
            )
    }
}

private struct SentinelPositionReader: View {
    let space: String
    var body: some View {
        // This view intentionally does nothing; we keep it to make the structure explicit.
        Color.clear
            .accessibilityHidden(true)
    }
}

private struct BottomSentinelMinYKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // We want the latest measured value.
        value = nextValue()
    }
}
