import SwiftUI
import os

struct ActionView: View {
    @EnvironmentObject private var overlayStateModel: OverlayStateModel
    @EnvironmentObject private var accessibilityManager: AccessibilityManagerImpl
    @Environment(\.suggestionDomainService) private var suggestionDomainService
    @Environment(\.userPreferencesDomainService) private var userPreferencesDomainService
    @Environment(\.profileDomainService) private var profileDomainService

    @StateObject private var suggestionTypesQueryable = ObservableQueryable(
        sortDescriptors: [SortDescriptor(\.sortOrder, order: .forward)],
        mapping: DefaultMapping<SuggestionType>.self
    )
    @State private var currentUserPreferences: UserPreferences?
    @State private var isProcessing = false
    @State private var isViewActive = true
    @State private var actionText: String = ""
    @State private var injectionError: String?

    /// Text injection service - created once and reused
    private let textInjectionService: TextInjectionService = DefaultTextInjectionService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ActionView.self)
    )

    /// Returns true if the action tool is in an interactive state (not idle)
    private var isInteractive: Bool {
        switch overlayStateModel.actionToolState {
        case .idle:
            return false
        case .loading, .action, .options:
            return true
        }
    }

    /// When true, the focused text contains something the local detector
    /// thinks is PII. Used to (a) float the Redaction suggestion to the top
    /// and (b) show the "PII detected" banner above the suggestion list.
    private var piiDetected: Bool {
        let text = overlayStateModel.elementInfo?.text ?? ""
        guard !text.isEmpty else { return false }
        return PIIDetector.containsPII(text)
    }

    /// Lazily-resolved decision from the AI-SPM-driven `PolicyEnforcer`.
    /// `nil` means no enforcer is configured (NullPolicyTransport tenant —
    /// fall back to local-only behaviour). Recomputed each render off the
    /// current `elementInfo.text`; cheap because the enforcer short-circuits.
    private var policyDecision: PolicyDecision? {
        guard let enforcer = overlayStateModel.policyEnforcer else { return nil }
        let text = overlayStateModel.elementInfo?.text ?? ""
        let appId = MonitoredAppsRegistry.shared
            .enabledNativeApp(bundleId: overlayStateModel.elementInfo?.applicationBundleId ?? "")?
            .id ?? "unknown"
        return enforcer.evaluate(text: text, appId: appId)
    }

    private var suggestionTypes: [SuggestionType] {
        let allTypes = suggestionTypesQueryable.wrappedValue
        let enabledTypes = allTypes.filter { $0.model.isEnabled }
        let piiDetected = self.piiDetected
        return enabledTypes.sorted { lhs, rhs in
            // When PII is detected, Redaction-type suggestions jump to the
            // top regardless of sortOrder. Backend may ship the type with a
            // different typeKey casing (e.g. "REDACTION") so we normalise.
            if piiDetected {
                let lhsRedacts = Self.isRedactionType(lhs)
                let rhsRedacts = Self.isRedactionType(rhs)
                if lhsRedacts != rhsRedacts { return lhsRedacts }
            }
            return lhs.model.sortOrder < rhs.model.sortOrder
        }
    }

    /// Matches the Redaction seed's typeKey or display name. Tolerant to
    /// server-side naming drift ("Redaction" vs "Redact" vs "REDACT_PII").
    static func isRedactionType(_ type: SuggestionType) -> Bool {
        let normalise: (String) -> String = {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
        }
        let typeKey = normalise(type.model.typeKey)
        let name = normalise(type.model.name)
        return typeKey.hasPrefix("redact") || name.hasPrefix("redact")
    }

    var body: some View {
        contentView
            .onAppear {
                isViewActive = true
            }
            .onDisappear {
                isViewActive = false
                isProcessing = false
                accessibilityManager.resumeFromInteraction()
            }
            .onChange(of: overlayStateModel.actionToolState) { oldState, newState in
                handleStateChange(from: oldState, to: newState)
            }
            .task {
                // Ensure suggestion types are loaded when view appears
                await suggestionTypesQueryable.refresh()
                await loadUserPreferences()
            }
    }

    private func loadUserPreferences() async {
        do {
            currentUserPreferences = try await userPreferencesDomainService.currentUserPreferences
        } catch {
            logger.error("Failed loading user preferences")
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch overlayStateModel.actionToolState {
        case .idle:
            idleView
        case .loading:
            loadingView
        case .action:
            actionResultView
        case .options:
            optionsView
        }
    }

    // MARK: - State Views

    private var idleView: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                isProcessing = true
                Task { @MainActor in
                    overlayStateModel.actionToolState = .options
                    isProcessing = false
                }
            } label: {
                Image(ImageResource(name: "logo_mid", bundle: .main))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(ButtonStyleWhite())
            .frame(width: 50, height: 50)
            .cornerRadius(8)

            // Grammarly-style passive indicator: small red badge with the
            // detected-issue count. Visible whenever PIIDetector finds
            // something in the focused field, even before the user clicks
            // to expand. Encourages awareness without being intrusive.
            if piiIssueCount > 0 {
                idleCountBadge
                    .offset(x: 6, y: -6)
            }
        }
        .frame(width: 56, height: 56)
    }

    private var idleCountBadge: some View {
        ZStack {
            Circle()
                .fill(Color.psRed)
                .frame(width: 18, height: 18)
                .shadow(color: Color.psRed.opacity(0.4), radius: 2, x: 0, y: 1)
            Text(piiIssueCount > 99 ? "99+" : "\(piiIssueCount)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    /// Total PII detections in the currently-focused text field. Drives
    /// the count badge on the idle indicator and the issues list
    /// inside the expanded options view.
    private var piiIssueCount: Int {
        let text = overlayStateModel.elementInfo?.text ?? ""
        guard !text.isEmpty else { return 0 }
        return PIIDetector.findMatches(in: text).count
    }

    private var piiMatches: [PIIMatch] {
        let text = overlayStateModel.elementInfo?.text ?? ""
        guard !text.isEmpty else { return [] }
        return PIIDetector.findMatches(in: text)
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
                .controlSize(.small)
        }
        .frame(width: 60, height: 60)
        .background(.white)
        .cornerRadius(8)
    }

    private var actionResultView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(actionText)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)

            if let error = injectionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                Button {
                    Task { @MainActor in
                        await replaceText()
                    }
                } label: {
                    Text("Agree & Update")
                        .font(.caption)
                }
                .buttonStyle(ButtonStyleGreen())

                Button {
                    rejectSuggestion()
                } label: {
                    Text("Keep Original")
                        .font(.caption)
                }
                .buttonStyle(ButtonStyleRed())
            }
        }
        .padding(12)
        .frame(width: 250)
        .background(.white)
        .cornerRadius(8)
    }

    /// Blocked-by-policy card shown when an AI-SPM PolicyInstance with
    /// `enforcementMode = block` matches the focused text. We don't show
    /// suggestions in this state — the user has to revise the prompt
    /// before any action can proceed.
    private func policyBlockedCard(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "octagon.fill")
                    .foregroundStyle(Color.psRed)
                Text("Blocked by policy")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.psRed)
            }
            Text(reason)
                .font(.system(size: 11))
                .foregroundStyle(Color.psText2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Revise the prompt to remove the flagged content. Contact your IT admin if you believe this is a mistake.")
                .font(.system(size: 11))
                .foregroundStyle(Color.psText3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.psRedLight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.psRed.opacity(0.3), lineWidth: 1)
        )
    }

    /// Lighter banner for flagged (non-blocking) policy hits. Tells the
    /// user "we logged this" without preventing the action.
    private func policyFlaggedBanner(decision: PolicyDecision) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "flag.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.psAmber)
            VStack(alignment: .leading, spacing: 1) {
                Text("Policy flagged")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.psAmber)
                if let first = decision.triggered.first {
                    Text(first.instance.name)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.psAmber.opacity(0.85))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.psAmberLight)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.psAmberBorder, lineWidth: 1)
        )
    }

    /// Grammarly-style issues panel. Lists each PIIDetector match as
    /// a small chip (category + matched substring) so the user can see
    /// exactly what Promptly is going to redact. Header reads N issues
    /// with the same amber tone as the existing banner. Pairs with the
    /// Redaction-first reorder below.
    private var piiDetectedBanner: some View {
        let matches = piiMatches
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.psAmber)
                Text(headerText(for: matches.count))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.psAmber)
                Spacer(minLength: 0)
                Text("Redact first")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.psAmber.opacity(0.8))
            }

            if !matches.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(matches.prefix(8).enumerated()), id: \.offset) { _, match in
                            issueRow(match: match)
                        }
                        if matches.count > 8 {
                            Text("+ \(matches.count - 8) more")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.psAmber.opacity(0.7))
                                .padding(.top, 1)
                        }
                    }
                }
                .frame(maxHeight: 96)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.psAmberLight)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.psAmberBorder, lineWidth: 1)
        )
    }

    /// One row per detected PII match — category emoji + truncated
    /// matched substring. Mimics Grammarly's per-issue card; the
    /// "fix" affordance is implicit (Redaction is the first suggestion).
    private func issueRow(match: PIIMatch) -> some View {
        HStack(spacing: 4) {
            Text(emoji(for: match.category))
                .font(.system(size: 10))
            Text(label(for: match.category))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.psAmber)
            Text(snippet(for: match))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.psText2)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.psSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func headerText(for count: Int) -> String {
        switch count {
        case 0: return "Sensitive data detected"
        case 1: return "1 sensitive item"
        default: return "\(count) sensitive items"
        }
    }

    private func snippet(for match: PIIMatch) -> String {
        let text = overlayStateModel.elementInfo?.text ?? ""
        let raw = String(text[match.range])
        return raw.count > 28 ? String(raw.prefix(28)) + "…" : raw
    }

    private func emoji(for category: PIICategory) -> String {
        switch category {
        case .email: return "✉️"
        case .phone: return "📞"
        case .creditCard: return "💳"
        case .ssn: return "🪪"
        case .ipAddress: return "🌐"
        case .apiKey: return "🔑"
        case .jwt: return "🎫"
        case .iban: return "🏦"
        case .bitcoinAddress: return "₿"
        case .currency: return "💰"
        case .personName: return "👤"
        }
    }

    private func label(for category: PIICategory) -> String {
        switch category {
        case .email: return "Email"
        case .phone: return "Phone"
        case .creditCard: return "Card"
        case .ssn: return "ID"
        case .ipAddress: return "IP"
        case .apiKey: return "API key"
        case .jwt: return "Token"
        case .iban: return "IBAN"
        case .bitcoinAddress: return "Crypto"
        case .currency: return "Currency"
        case .personName: return "Name"
        }
    }

    /// True when an active AI-SPM policy hard-blocks this prompt. Hides
    /// the suggestion list — the user must revise before any LLM call.
    private var isBlockedByPolicy: Bool {
        if case .block = policyDecision?.action { return true }
        return false
    }

    private var optionsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let decision = policyDecision {
                if case .block(let reason) = decision.action {
                    policyBlockedCard(reason: reason)
                } else if case .flag = decision.action {
                    policyFlaggedBanner(decision: decision)
                } else if case .redact = decision.action {
                    piiDetectedBanner
                } else if piiDetected {
                    piiDetectedBanner
                }
            } else if piiDetected {
                piiDetectedBanner
            }
            if isBlockedByPolicy {
                Button {
                    overlayStateModel.actionToolState = .idle
                } label: {
                    Text("Close")
                        .font(.caption)
                }
                .buttonStyle(ButtonStyleRed())
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            } else {
            ScrollView {
                LazyVStack {
                    if suggestionTypes.count > 0 {
                        ForEach(suggestionTypes, id: \.model.typeKey) { suggestionType in
                            Button { [weak overlayStateModel] in
                                guard !isProcessing else { return }
                                isProcessing = true
                                overlayStateModel?.actionToolState = .loading

                                Task { @MainActor in
                                    await processSuggestion(suggestionType: suggestionType)
                                }
                            } label: {
                                VStack(spacing: .zero) {
                                    Text(suggestionType.displayName)
                                        .font(.headline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .foregroundStyle(.black)

                                    Text(suggestionType.displayDescription)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(10)
                                }.frame(maxWidth: 200)
                            }
                            .buttonStyle(HoverHighlightButtonStyle())
                            .disabled(isProcessing)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text("No suggestions enabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 300)
            Button {
                overlayStateModel.actionToolState = .idle
            } label: {
                Text("Close suggestions")
                    .font(.caption)
            }
            .buttonStyle(ButtonStyleRed())
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            }
        }
        .padding(8)
        .frame(minWidth: 150)
        .frame(minHeight: 50)
        .background(.white)
        .cornerRadius(8)
    }
    // MARK: - State Management

    private func handleStateChange(from oldState: ActionToolState, to newState: ActionToolState) {
        let wasInteractive = isInteractiveState(oldState)
        let isNowInteractive = isInteractiveState(newState)

        if !wasInteractive && isNowInteractive {
            // Entering interactive state - pause monitoring to preserve element info
            accessibilityManager.pauseForInteraction()
            injectionError = nil
            Analytics.trackAsync(.actionMenuOpened)
        } else if wasInteractive && !isNowInteractive {
            // Leaving interactive state - resume monitoring
            accessibilityManager.resumeFromInteraction()
            Analytics.trackAsync(.actionMenuClosed)
        }
    }

    private func isInteractiveState(_ state: ActionToolState) -> Bool {
        switch state {
        case .idle:
            return false
        case .loading, .action, .options:
            return true
        }
    }

    private func resetState() {
        injectionError = nil
        accessibilityManager.resumeFromInteraction()
        overlayStateModel.actionToolState = .idle
    }

    // MARK: - Telemetry helpers

    /// Maps a suggestion + active policy decision to the usage-rollup
    /// counter that should bump for this action.
    private func usageKind(for typeKey: String, decision: PolicyDecision?) -> UsageEventAggregator.Kind {
        if let action = decision?.action {
            switch action {
            case .block: return .blocked
            case .redact: return .redacted
            case .flag: return .flagged
            case .allow, .log: break
            }
        }
        // Redaction-typed suggestions count as redacted regardless of policy.
        if typeKey.lowercased().hasPrefix("redact") { return .redacted }
        return .prompt
    }

    /// When a policy enforcer is configured AND the current decision was
    /// `.allow`, emit a single `evaluated` tick to the dashboard so it
    /// gets a denominator for FP rates. Native-app actions only — browser
    /// URL host plumbing is a follow-up.
    @MainActor
    private func emitEvaluatedTickIfClean(promptlyAppId: String) async {
        guard let decision = policyDecision, case .allow = decision.action else { return }
        guard let enforcer = overlayStateModel.policyEnforcer,
              let client = overlayStateModel.policyClient else { return }
        let urlHost = overlayStateModel.elementInfo?.focusedURLHost
        let violation = enforcer.makeEvaluatedTick(
            applicationId: promptlyAppId,
            promptHash: decision.promptHash,
            user: nil,
            urlHost: urlHost
        )
        await client.reportViolation(violation)
    }

    // MARK: - Suggestion Processing

    @MainActor
    private func processSuggestion(suggestionType: SuggestionType) async {
        defer { isProcessing = false }

        let suggestionTypeKey = suggestionType.model.typeKey
        let suggestionCategory = suggestionType.model.category
        let startTime = Date()

        // Track suggestion type selected and processing started
        Analytics.trackAsync(.suggestionTypeSelected(type: suggestionTypeKey, category: suggestionCategory))
        Analytics.trackAsync(.suggestionProcessingStarted(type: suggestionTypeKey))

        // Resolve the Promptly app id (chatgpt / claude / etc.) and route
        // a usage-rollup tick + a policy-evaluated tick through the AI-SPM
        // telemetry stream. Both fail open — telemetry failures never
        // block the suggestion call.
        //
        // Resolution order: native bundle id (Electron apps like ChatGPT
        // desktop) → web URL host (chat.openai.com etc.) → shadow stub
        // for whichever we know.
        let bundleId = overlayStateModel.elementInfo?.applicationBundleId ?? ""
        let urlString = overlayStateModel.elementInfo?.focusedURL ?? ""
        let promptlyAppId: String
        if let native = MonitoredAppsRegistry.shared.enabledNativeApp(bundleId: bundleId) {
            promptlyAppId = native.id
        } else if let web = MonitoredAppsRegistry.shared.enabledWebApp(urlString: urlString) {
            promptlyAppId = web.id
        } else {
            promptlyAppId = "shadow-\(bundleId)"
        }
        UsageEventAggregator.shared.record(
            kind: usageKind(for: suggestionTypeKey, decision: policyDecision),
            promptlyAppId: promptlyAppId,
            auth0Sub: nil
        )
        Task { await emitEvaluatedTickIfClean(promptlyAppId: promptlyAppId) }

        do {
            let result = try await suggestionDomainService
                .process(
                    text: overlayStateModel.elementInfo?.text ?? "",
                    suggestionGroupId: profileDomainService.currentProfile.model.defaultSuggestionGroupId,
                    teamId: profileDomainService.currentProfile.model.defaultTeamId,
                    suggestionType: suggestionTypeKey,
                    application: overlayStateModel.elementInfo?.applicationName ?? "n/a"
                )

            try Task.checkCancellation()

            let duration = Date().timeIntervalSince(startTime)
            Analytics.trackAsync(.suggestionProcessingCompleted(type: suggestionTypeKey, duration: duration))

            actionText = result.model.suggestedText
            overlayStateModel.actionToolState = .action
        } catch is CancellationError {
            logger.debug("LLM processing was cancelled")
            Analytics.trackAsync(.suggestionProcessingFailed(type: suggestionTypeKey, error: "cancelled"))
            resetState()
        } catch {
            logger.debug("Error processing LLM request: \(error)")
            Analytics.trackAsync(.suggestionProcessingFailed(type: suggestionTypeKey, error: error.localizedDescription))
            resetState()
        }
    }

    // MARK: - Text Injection

    @MainActor
    private func replaceText() async {
        logger.debug("Starting text replacement")
        injectionError = nil

        // Get the preserved element info
        let targetInfo = overlayStateModel.elementInfo
        let applicationName = targetInfo?.applicationName ?? "unknown"

        guard targetInfo != nil else {
            logger.debug("No element info available")
            injectionError = "Target field not found"
            Analytics.trackAsync(.textInjectionFailed(application: applicationName, error: "no_element_info"))
            return
        }

        // Track injection started
        Analytics.trackAsync(.textInjectionStarted(application: applicationName))

        do {
            // Use the new injection service which gets a fresh element reference
            try textInjectionService.injectText(actionText, targetInfo: targetInfo)
            logger.debug("Text injection successful")

            // Track success and suggestion accepted
            Analytics.trackAsync(.textInjectionSucceeded(application: applicationName, method: "injection_service"))
            Analytics.trackAsync(.suggestionAccepted(type: "text_replacement"))

            resetState()
        } catch let error as AccessibilityError {
            logger.debug("Accessibility error: \(error.localizedDescription)")
            injectionError = error.localizedDescription
            Analytics.trackAsync(.textInjectionFailed(application: applicationName, error: error.localizedDescription))
        } catch {
            logger.debug("Unexpected error: \(error.localizedDescription)")
            injectionError = "Failed to update text"
            Analytics.trackAsync(.textInjectionFailed(application: applicationName, error: error.localizedDescription))
        }
    }

    private func rejectSuggestion() {
        Analytics.trackAsync(.suggestionRejected(type: "text_replacement"))
        resetState()
    }
}

struct HoverHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverHighlightButton(configuration: configuration)
    }
}

private struct HoverHighlightButton: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
