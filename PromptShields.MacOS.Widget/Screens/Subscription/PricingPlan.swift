import SwiftUI
// MARK: - Pricing Plan Model

struct PricingPlan {
    let subscriptionTier: SubscriptionTier
    let billingPeriod: BillingPeriod
    let features: [String]
}

extension BillingPeriod {
    var pretty: String {
        switch self {
        case .monthly:
            return "Monthly"
        case .yearly:
            return "Yearly"
        }
    }

    func price(subscriptionTier: SubscriptionTier) -> String {
        switch self {
        case .monthly:
            switch subscriptionTier {
            case .bronze:
                return "€19.99"
            case .tin:
                return "Free"
            }
        case .yearly:
            switch subscriptionTier {
            case .bronze:
                return "€199.99"
            case .tin:
                return "Free"
            }
        }
    }
}

extension SubscriptionTier {
    func title(period: BillingPeriod) -> String {
        switch self {
        case .tin:
            return "Free"
        case .bronze:
            return "Premium \(period.pretty)"
        }
    }
    func description(period: BillingPeriod) -> String {
        switch self {
        case .tin:
            return "Free app - limited AI capabilities"
        case .bronze:
            return "\(period.pretty) subscription"
        }
    }
}

struct PricingPlanCard: View {
    let plan: PricingPlan
    let onSubscribe: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(plan.subscriptionTier.title(period: plan.billingPeriod))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(plan.subscriptionTier.description(period: plan.billingPeriod))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(plan.billingPeriod.price(subscriptionTier: plan.subscriptionTier))
                    .font(.title)
                    .fontWeight(.bold)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.features, id: \.self) { feature in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(feature)
                            .font(.subheadline)
                    }
                }
            }

            Button("Purchase") {
                onSubscribe()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}
