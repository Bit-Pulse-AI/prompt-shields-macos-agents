import SwiftUI
import os

enum BillingPeriod: String {
    case yearly
    case monthly
}

private extension Date {
    var formattedDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        return dateFormatter.string(from: self)
    }
}

struct SubscriptionIntegrationView: View {
    @Environment(\.subscriptionDomainService) private var subscriptionDomainService
    @Environment(\.profileDomainService) private var profileDomainService
    @EnvironmentObject private var overlayStateModel: OverlayStateModel

    private let availableSubscriptionTiers = [SubscriptionTier.tin, SubscriptionTier.bronze]
    private let pricingPlans = [PricingPlan]()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: SubscriptionIntegrationView.self)
    )
    @State private var currentSubscription: Subscription?
    @State private var isLoading = false
    @State private var showCancelDialog = false
    @State private var showingSubscriptionDetail = false
    @State private var checkoutURL: URL?

    private var showCancelButton: Bool {
        currentSubscription?.model.cancelledAt != nil
    }

    private var membershipEndDate: String {
        currentSubscription?.model.stripePeriodEnd?.formattedDate ?? ""
    }

    var body: some View {
        subscriptionStatusView
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .sheet(isPresented: $showingSubscriptionDetail) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        showingSubscriptionDetail = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .padding(8)
                }
                if let checkoutURL {
                    CheckoutWebView(url: checkoutURL) { _ in
                        Task {
                            await refreshAfterCheckout()
                        }
                    }
                } else {
                    VStack { ProgressView() }
                        .frame(width: 300, height: 200)
                }
            }
            .frame(width: 900, height: 700)
        }
        .frame(alignment: .leading)
        .task {
            do {
                try await loadCurrentSubscription()
            } catch {
                logger.debug("Error \(error)")
                // TBD: Add toast
            }
        }.alert("Notice", isPresented: $showCancelDialog) {
            Button("OK", role: .destructive) {
                Task {
                    isLoading = true
                    do {
                        let profile = try await profileDomainService.currentProfile.model
                        let organisationId = profile.defaultOrganisationId
                        let subscriptionId = profile.defaultSubscriptionId
                        try await subscriptionDomainService.cancel(organisationId: organisationId, subscriptionId: subscriptionId)
                        try await loadCurrentSubscription()
                        isLoading = false
                    } catch {
                        isLoading = false
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                showCancelDialog = false
            }
        } message: {
            Text("Are you sure you want to cancel your current subscription ?")
        }
    }

    @ViewBuilder
    private var subscriptionStatusView: some View {
        if isLoading {
            ProgressView()
                .scaleEffect(0.8)
        } else if let currentSubscription {
            switch currentSubscription.model.tier {
            case SubscriptionTier.tin.rawValue:
                HStack {
                    let monthlyPlan = PricingPlan(subscriptionTier: .bronze, billingPeriod: .monthly, features: ["Monthly premium offering"])
                    PricingPlanCard(plan: monthlyPlan) {
                        Task {
                            await subscribeUser(subscriptionTier: monthlyPlan.subscriptionTier, billingPeriod: monthlyPlan.billingPeriod)
                        }
                    }
                    Spacer()
                    let yearlyPlan = PricingPlan(subscriptionTier: .bronze, billingPeriod: .yearly, features: ["Yearly premium deal!"])
                    PricingPlanCard(plan: yearlyPlan) {
                        Task {
                            await subscribeUser(subscriptionTier: yearlyPlan.subscriptionTier, billingPeriod: yearlyPlan.billingPeriod)
                        }
                    }
                }
            case SubscriptionTier.bronze.rawValue:
                Text("Premium user subscription active")
                if showCancelButton {
                    Text("Membership will end on \(membershipEndDate)")
                } else {
                    Button("Cancel subscription") {
                        Task {
                            showCancelDialog = true
                        }
                    }
                }

            default:
                Image(systemName: "crown.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
            }
        } else {
            Image(systemName: "crown.fill")
                .foregroundColor(.orange)
                .font(.title2)
        }
    }

    private func subscribeUser(subscriptionTier: SubscriptionTier, billingPeriod: BillingPeriod) async {
        isLoading = true
        do {
            let profile = try await profileDomainService.currentProfile.model
            let organisationId = profile.defaultOrganisationId
            let subscriptionId = profile.defaultSubscriptionId
            let tenantId = profile.defaultTenantId

            let checkout = try await subscriptionDomainService.checkout(
                subscriptionTier: SubscriptionTier.bronze.rawValue,
                organisationId: organisationId,
                subscriptionId: subscriptionId,
                tenantId: tenantId,
                billingPeriod: billingPeriod.rawValue,
                successURL: webBillingSuccessURL,
                cancelURL: webBillingCancelURL
            )
            await MainActor.run {
                self.checkoutURL = checkout.url
                self.showingSubscriptionDetail = true
            }
        } catch {
            logger.debug("error \(error)")
        }

        isLoading = false
    }

    @MainActor
    private func loadCurrentSubscription() async throws {
        isLoading = true
        currentSubscription = try await subscriptionDomainService.currentSubscription(refresh: true)
        isLoading = false
    }

    @MainActor
    private func refreshAfterCheckout() async {
        showingSubscriptionDetail = false
        do {
            try await loadCurrentSubscription()
        } catch {
            logger.debug("Failed to refresh subscription after checkout: \(error)")
        }
    }
}

// MARK: - Preview

struct SubscriptionIntegrationView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionIntegrationView()
            .padding()
    }
}
