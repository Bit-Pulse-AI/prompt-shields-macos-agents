import SwiftUI

struct BillingResultView: View {
//    let result: BillingResult
    let onDismiss: () -> Void
    
    @Environment(\.subscriptionDomainService) private var subscriptionService
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon and title
            VStack(spacing: 16) {
                resultIcon
                
                VStack(spacing: 8) {
                    Text(resultTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(resultMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Loading indicator
            if isLoading {
                ProgressView("Syncing subscription status...")
                    .padding()
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Close") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                
//                if case .success = result {
//                    Button("Sync Status") {
//                        Task {
//                            await syncSubscriptionStatus()
//                        }
//                    }
//                    .buttonStyle(.borderedProminent)
//                }
            }
        }
        .padding(32)
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            // Auto-sync if successful
//            if case .success = result {
//                Task {
//                    // Wait a moment for the backend to process
//                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
//                    await syncSubscriptionStatus()
//                }
//            }
        }
    }
    
    // MARK: - Result Content
    
    private var resultIcon: some View {
        Group {
//            switch result {
//            case .success:
//                Image(systemName: "checkmark.circle.fill")
//                    .foregroundColor(.green)
//                    .font(.system(size: 64))
//            case .cancelled:
//                Image(systemName: "xmark.circle.fill")
//                    .foregroundColor(.orange)
//                    .font(.system(size: 64))
//            case .returned:
//                Image(systemName: "arrow.left.circle.fill")
//                    .foregroundColor(.blue)
//                    .font(.system(size: 64))
//            }
        }
    }
    
    private var resultTitle: String {
//        switch result {
//        case .success:
            return "Subscription Updated!"
//        case .cancelled:
//            return "Subscription Cancelled"
//        case .returned:
//            return "Welcome Back"
//        }
    }
    
    private var resultMessage: String {
//        switch result {
//        case .success:
            return "Your subscription has been successfully updated. We're syncing your account status now."
//        case .cancelled:
//            return "Your subscription process was cancelled. You can try again anytime."
//        case .returned:
//            return "You've returned from the billing portal. Your subscription status has been updated."
//        }
    }
    
    // MARK: - Actions
    
    private func syncSubscriptionStatus() async {
        isLoading = true
        
//        do {
//            _ = try await subscriptionService.syncWithWebBilling()
//        } catch {
//            // Handle error silently or show a toast
//            print("Failed to sync subscription status: \(error)")
//        }
        
        isLoading = false
    }
}

// MARK: - Billing Result Overlay

struct BillingResultOverlay: ViewModifier {
    @ObservedObject var overlayStateModel: OverlayStateModel
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
//                    if let billingResult = overlayStateModel.billingResult {
//                        Color.black.opacity(0.4)
//                            .edgesIgnoringSafeArea(.all)
//                            .onTapGesture {
//                                // Prevent dismissing by tapping background for important results
//                                if case .cancelled = billingResult {
//                                    overlayStateModel.billingResult = nil
//                                }
//                            }
//                        
//                        BillingResultView(result: billingResult) {
//                            overlayStateModel.billingResult = nil
//                        }
//                        .transition(.scale.combined(with: .opacity))
//                        .animation(.spring(), value: overlayStateModel.billingResult)
//                    }
                }
            )
    }
}

extension View {
    func billingResultOverlay(overlayStateModel: OverlayStateModel) -> some View {
        self.modifier(BillingResultOverlay(overlayStateModel: overlayStateModel))
    }
}

// MARK: - Compact Billing Result View

struct CompactBillingResultView: View {
//    let result: BillingResult
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            resultIcon
            
            VStack(alignment: .leading, spacing: 4) {
                Text(resultTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(resultMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button("✕") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(8)
        .shadow(radius: 4)
    }
    
    private var resultIcon: some View {
        Group {
//            switch result {
//            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
//            case .cancelled:
//                Image(systemName: "xmark.circle.fill")
//                    .foregroundColor(.orange)
//            case .returned:
//                Image(systemName: "arrow.left.circle.fill")
//                    .foregroundColor(.blue)
//            }
        }
        .font(.title3)
    }
    
    private var backgroundColor: Color {
//        switch result {
//        case .success:
            return Color.green.opacity(0.1)
//        case .cancelled:
//            return Color.orange.opacity(0.1)
//        case .returned:
//            return Color.blue.opacity(0.1)
//        }
    }
    
    private var resultTitle: String {
//        switch result {
//        case .success:
            return "Subscription Updated"
//        case .cancelled:
//            return "Process Cancelled"
//        case .returned:
//            return "Billing Updated"
//        }
    }
    
    private var resultMessage: String {
//        switch result {
//        case .success:
            return "Your subscription has been successfully updated."
//        case .cancelled:
//            return "Subscription process was cancelled."
//        case .returned:
//            return "Billing portal session completed."
//        }
    }
}

// MARK: - Preview

struct BillingResultView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
//            BillingResultView(result: .success(sessionId: "test")) { }
//            BillingResultView(result: .cancelled(sessionId: "test")) { }
//            BillingResultView(result: .returned(sessionId: "test")) { }
        }
        .padding()
    }
}
