import SwiftUI

/// A simple integration view that can be added to your existing dashboard
struct SubscriptionIntegrationView: View {
    @Environment(\.subscriptionDomainService) private var subscriptionService
    @EnvironmentObject private var overlayStateModel: OverlayStateModel
    
    @State private var subscription: Subscription?
    @State private var isLoading = false
    @State private var showingSubscriptionDetail = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Subscription status indicator
            statusIndicator
            
            // Subscription info
            VStack(alignment: .leading, spacing: 4) {
                Text(subscription?.model.name ?? "Free Plan")
                    .font(.headline)
                    .foregroundColor(.primary)
                
//                Text(subscription?.subscriptionStatus.displayText ?? "No active subscription")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Action button
//            Button(subscription?.model.isActive == true ? "Manage" : "Upgrade") {
//                showingSubscriptionDetail = true
//            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .onAppear {
            Task {
                await loadSubscription()
            }
        }
        .sheet(isPresented: $showingSubscriptionDetail) {
            BillingSubscriptionView()
        }
        .billingResultOverlay(overlayStateModel: overlayStateModel)
    }
    
    private var statusIndicator: some View {
        Group {
//            if isLoading {
//                ProgressView()
//                    .scaleEffect(0.8)
//            } else if let subscription = subscription {
//                Image(systemName: subscription.subscriptionStatus.systemImageName)
//                    .foregroundColor(colorForStatus(subscription.subscriptionStatus))
//                    .font(.title2)
//            } else {
//                Image(systemName: "crown.fill")
//                    .foregroundColor(.orange)
//                    .font(.title2)
//            }
        }
    }
    
//    private func colorForStatus(_ status: SubscriptionStatus) -> Color {
//        switch status.color {
//        case "green":
//            return .green
//        case "orange":
//            return .orange
//        case "red":
//            return .red
//        default:
//            return .secondary
//        }
//    }
    
    private func loadSubscription() async {
        isLoading = true
        
        do {
            subscription = try await subscriptionService.currentSubscription
        } catch {
            subscription = nil
        }
        
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
