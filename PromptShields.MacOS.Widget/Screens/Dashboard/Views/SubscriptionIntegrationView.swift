import SwiftUI
import os

enum BillingPeriod: String {
    case yearly
    case monthly
}

struct SubscriptionIntegrationView: View {
    @Environment(\.subscriptionDomainService) private var subscriptionDomainService
    @Environment(\.profileDomainService) private var profileDomainService
    @EnvironmentObject private var overlayStateModel: OverlayStateModel

    private let availableSubscriptionTiers = [SubscriptionTier.tin, SubscriptionTier.bronze]
    private let pricingPlans = [PricingPlan]()

    @State private var currentSubscription: Subscription?
    @State private var isLoading = false
    @State private var showingSubscriptionDetail = false

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ActionView.self)
    )

    var body: some View {
        subscriptionStatusView
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .sheet(isPresented: $showingSubscriptionDetail) {

        }
        .frame(alignment: .leading)
        .task {
            do {
                try await loadCurrentSubscription()
            } catch {
                print("Error \(error)")
                // TBD: Add toast
            }
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
                Text("You're already a premium user - thinking about an upgrade ?")
                if currentSubscription.model.stripeBillingPeriod == BillingPeriod.monthly.rawValue {
                    let yearlyPlan = PricingPlan(subscriptionTier: .bronze, billingPeriod: .yearly, features: ["Upgrade now for a better deal!"])
                    PricingPlanCard(plan: yearlyPlan) {
                        Task {
                            await subscribeUser(subscriptionTier: yearlyPlan.subscriptionTier, billingPeriod: yearlyPlan.billingPeriod)
                        }
                    }
                }
                Button("Cancel subscription") {
                    print("Cancel sub")
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
            let tenantId = profile.defaultTenantId

            let checkout = try await subscriptionDomainService.checkout(
                subscriptionTier: SubscriptionTier.bronze.rawValue,
                organisationId: organisationId,
                tenantId: tenantId,
                billingPeriod: billingPeriod.rawValue,
                successURL: "https://www.google.com",
                cancelURL: "https://www.google.com"
            )
        } catch {
            logger.error("error \(error)")
        }

        isLoading = false
    }

    @MainActor
    private func loadCurrentSubscription() async throws {
        isLoading = true
        currentSubscription = try await subscriptionDomainService.currentSubscription
        isLoading = false
    }
}

// MARK: - Preview

struct SubscriptionIntegrationView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionIntegrationView()
            .padding()
    }
}
