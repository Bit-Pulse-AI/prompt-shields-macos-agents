import SwiftUI

struct BillingSubscriptionView: View {
    @Environment(\.subscriptionDomainService) private var subscriptionService
    
    @State private var subscription: Subscription?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingPricingPlans = false
    
    // Available pricing plans (these would typically come from your backend)
    private let pricingPlans = [
        PricingPlan(
            id: "price_basic_monthly",
            productId: "prod_basic",
            name: "Basic",
            description: "Essential features for individuals",
            price: "$9.99",
            interval: "month",
            features: ["Up to 10 projects", "Basic support", "5GB storage"]
        ),
        PricingPlan(
            id: "price_pro_monthly",
            productId: "prod_pro",
            name: "Pro",
            description: "Advanced features for professionals",
            price: "$19.99",
            interval: "month",
            features: ["Unlimited projects", "Priority support", "50GB storage", "Advanced analytics"]
        ),
        PricingPlan(
            id: "price_premium_monthly",
            productId: "prod_premium",
            name: "Premium",
            description: "Complete solution for teams",
            price: "$39.99",
            interval: "month",
            features: ["Everything in Pro", "Team collaboration", "200GB storage", "Custom integrations"]
        )
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading subscription information...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Current Subscription Status
                            currentSubscriptionCard
                            
                            // Quick Actions
                            quickActionsCard
                            
                            // Subscription Plans (if no active subscription)
//                            if subscription?.model.isActive != true {
//                                subscriptionPlansCard
//                            }
                        }
                        .padding()
                    }
                }
                
                if let errorMessage = errorMessage {
                    errorView(message: errorMessage)
                }
            }
            .navigationTitle("Subscription")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        Task {
                            await loadSubscriptionData()
                        }
                    }
                }
            }
            .onAppear {
                Task {
                    await loadSubscriptionData()
                }
            }
            .sheet(isPresented: $showingPricingPlans) {
                PricingPlansView(plans: pricingPlans) { priceId in
                    Task {
                        await subscribeToPlan(priceId: priceId)
                    }
                }
            }
        }
    }
    
    // MARK: - Current Subscription Card
    
    private var currentSubscriptionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current Subscription")
                .font(.headline)
                .foregroundColor(.primary)
            
            if let subscription = subscription {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(subscription.model.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
//                            statusBadge(for: subscription.subscriptionStatus)
                        }
                        
                        Text(subscription.model.tier.capitalized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
//                        if let periodFormatted = subscription.currentPeriodFormatted {
//                            Text("Current period: \(periodFormatted)")
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                        }
                        
//                        if subscription.model.cancelAtPeriodEnd,
//                           let periodEnd = subscription.model.currentPeriodEnd {
//                            HStack {
//                                Image(systemName: "exclamationmark.triangle.fill")
//                                    .foregroundColor(.orange)
//                                Text("Will cancel on \(periodEnd, style: .date)")
//                                    .font(.caption)
//                                    .foregroundColor(.orange)
//                            }
//                        }
                        
//                        if subscription.needsAttention {
//                            HStack {
//                                Image(systemName: "exclamationmark.circle.fill")
//                                    .foregroundColor(.red)
//                                Text("Needs attention - please update billing information")
//                                    .font(.caption)
//                                    .foregroundColor(.red)
//                            }
//                        }
                    }
                    
                    Spacer()
                    
//                    if subscription.model.isActive {
//                        Image(systemName: "checkmark.circle.fill")
//                            .foregroundColor(.green)
//                            .font(.title2)
//                    }
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No Active Subscription")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Free Tier")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Upgrade Now") {
                        showingPricingPlans = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Quick Actions Card
    
    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manage Subscription")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
//                if subscription?.model.isActive == true {
//                    Button("Open Billing Portal") {
//                        Task {
//                            await openBillingPortal()
//                        }
//                    }
//                    .buttonStyle(.bordered)
//                    .frame(maxWidth: .infinity)
//                } else {
//                    Button("View Pricing Plans") {
//                        showingPricingPlans = true
//                    }
//                    .buttonStyle(.borderedProminent)
//                    .frame(maxWidth: .infinity)
//                }
                
                Button("Sync Subscription Status") {
                    Task {
                        await syncSubscriptionStatus()
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Subscription Plans Card
    
    private var subscriptionPlansCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Available Plans")
                .font(.headline)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: min(pricingPlans.count, 3)), spacing: 16) {
                ForEach(pricingPlans, id: \.id) { plan in
                    subscriptionPlanCell(plan: plan)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func subscriptionPlanCell(plan: PricingPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                
                Text(plan.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Text(plan.price)
                .font(.title3)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 4) {
                ForEach(plan.features, id: \.self) { feature in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(feature)
                            .font(.caption2)
                    }
                }
            }
            
            Spacer()
            
            Button("Subscribe") {
                Task {
                    await subscribeToPlan(priceId: plan.id)
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(minHeight: 200)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Helper Views
    
//    private func statusBadge(for status: SubscriptionStatus) -> some View {
//        HStack(spacing: 4) {
//            Image(systemName: status.systemImageName)
//                .font(.caption)
//            Text(status.displayText)
//                .font(.caption)
//                .fontWeight(.medium)
//        }
//        .padding(.horizontal, 8)
//        .padding(.vertical, 4)
//        .background(Color(status.color == "green" ? .systemGreen : status.color == "orange" ? .systemOrange : .systemRed).opacity(0.1))
//        .foregroundColor(Color(status.color == "green" ? .systemGreen : status.color == "orange" ? .systemOrange : .systemRed))
//        .cornerRadius(4)
//    }
    
    private func errorView(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            Text(message)
                .foregroundColor(.primary)
            Spacer()
            Button("Dismiss") {
                errorMessage = nil
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    // MARK: - Actions
    
    @MainActor
    private func loadSubscriptionData() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Try to get current subscription
            subscription = try await subscriptionService.currentSubscription
            
            // Sync with web billing
//            subscription = try await subscriptionService.syncWithWebBilling()
        } catch {
            // If no subscription exists, that's okay for free tier users
            if case SubscriptionServiceError.missingSubscription = error {
                subscription = nil
            } else {
                errorMessage = "Failed to load subscription data: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
    }
    
    @MainActor
    private func subscribeToPlan(priceId: String) async {
        do {
//            _ = try await subscriptionService.createCheckoutSession(priceId: priceId)
            showingPricingPlans = false
            
            // Note: After the user completes checkout, they'll need to refresh or sync
            // In a real app, you might want to implement webhooks or polling
        } catch {
            errorMessage = "Failed to start checkout: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func openBillingPortal() async {
        do {
//            try await subscriptionService.openBillingPortal()
        } catch {
            errorMessage = "Failed to open billing portal: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func syncSubscriptionStatus() async {
        do {
//            subscription = try await subscriptionService.syncWithWebBilling()
        } catch {
            errorMessage = "Failed to sync subscription status: \(error.localizedDescription)"
        }
    }
}

// MARK: - Pricing Plan Model

struct PricingPlan {
    let id: String
    let productId: String
    let name: String
    let description: String
    let price: String
    let interval: String
    let features: [String]
}

// MARK: - Pricing Plans View

struct PricingPlansView: View {
    let plans: [PricingPlan]
    let onSubscribe: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("Choose Your Plan")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Select the plan that best fits your needs")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: min(plans.count, 3)), spacing: 20) {
                        ForEach(plans, id: \.id) { plan in
                            PricingPlanCard(plan: plan) {
                                onSubscribe(plan.id)
                                dismiss()
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Pricing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PricingPlanCard: View {
    let plan: PricingPlan
    let onSubscribe: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(plan.name)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(plan.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(plan.price)
                        .font(.title)
                        .fontWeight(.bold)
                    Text("/ \(plan.interval)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
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
            
            Spacer()
            
            Button("Subscribe Now") {
                onSubscribe()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(minHeight: 300)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}
