import SwiftUI

struct UserInfoView: View {
    @EnvironmentObject private var dashboardState: DashboardStateModel
    @Environment(\.userDomainService) private var userDomainService
    @State private var displayName: String = "—"
    @State private var initials: String = "—"
    @State private var photoURL: URL?

    var body: some View {
        Button {
            dashboardState.contentState = .account
        } label: {
            HStack(spacing: .zero) {
                avatar
                    .frame(width: 32, height: 32)
                Text(displayName)
                    .foregroundStyle(Color.onBackground)
                    .font(NSFont.body2.swiftUIFont)
                    .padding(.leading, 8)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }.frame(alignment: .center)
        }
        .buttonStyle(.plain)
        .task {
            await loadUser()
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if photoURL != nil {
            RoundCirclePortraitView(url: $photoURL, lineWidth: 1)
                .foregroundStyle(.gray)
        } else {
            ZStack {
                Circle().fill(Color.psBlueLight)
                Text(initials)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.psBlue)
            }
        }
    }

    private func loadUser() async {
        guard let currentUser = try? await userDomainService.currentUser else { return }
        let resolved = Self.resolveDisplayName(from: currentUser.model)
        displayName = resolved.name
        initials = resolved.initials
        photoURL = currentUser.model.photoURL
    }

    /// Fallback chain (PS-14):
    /// 1. firstName + lastName (if at least one is real)
    /// 2. email
    /// 3. "—"
    /// Never returns "n/a" (which is the default persisted value for missing fields).
    static func resolveDisplayName(from model: User.UserModel) -> (name: String, initials: String) {
        let first = Self.clean(model.firstName)
        let last = Self.clean(model.lastName)

        if !first.isEmpty || !last.isEmpty {
            let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
            let initials = Self.initials(first: first, last: last)
            return (name, initials)
        }

        let email = Self.clean(model.email)
        if !email.isEmpty {
            let username = email.split(separator: "@").first.map(String.init) ?? email
            return (email, Self.initials(fromSingle: username))
        }

        return ("—", "—")
    }

    private static func clean(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        // Treat the legacy "n/a" persisted default and other junk as empty.
        if lower == "n/a" || lower == "null" || lower == "undefined" || lower == "nil" {
            return ""
        }
        return trimmed
    }

    private static func initials(first: String, last: String) -> String {
        let f = first.first.map(String.init) ?? ""
        let l = last.first.map(String.init) ?? ""
        let combined = (f + l).uppercased()
        if !combined.isEmpty { return combined }
        return "—"
    }

    private static func initials(fromSingle value: String) -> String {
        let parts = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined().uppercased()
        if !letters.isEmpty { return letters }
        return value.prefix(2).uppercased()
    }
}
