import SwiftUI
import os

/// Settings view with editable suggestion types and user preferences
struct SettingsView: View {
    @Environment(\.userDomainService) private var userDomainService
    @Environment(\.userPreferencesDomainService) private var userPreferencesDomainService
    @Environment(\.suggestionDomainService) private var suggestionDomainService

    @State private var selectedTab: SettingsTab = .suggestionTypes

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SettingsView.self)
    )

    private enum SettingsTab: String, CaseIterable {
        case suggestionTypes = "Suggestion Types"
        case preferences = "Preferences"

        var icon: String {
            switch self {
            case .suggestionTypes: return "lightbulb"
            case .preferences: return "gearshape"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            tabSelector

            Divider()

            // Content based on selected tab
            switch selectedTab {
            case .suggestionTypes:
                SuggestionTypeListView()
            case .preferences:
                preferencesView
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                        Text(tab.rawValue)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Preferences View

    private var preferencesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                generalPreferencesSection
                aboutSection
            }
            .padding()
        }
    }

    private var generalPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                // Add more preference options here as needed
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("More preference options coming soon")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Build")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}
