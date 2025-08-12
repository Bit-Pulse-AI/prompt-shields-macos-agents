import SwiftUI
import RevenueCat

struct SubscriptionPackageView: View {
   let package: Package
   let isCurrentPlan: Bool
   let onPurchase: () async -> Void
   
   @State private var isPurchasing = false
   
   var priceView: some View {
       if let introPrice = package.storeProduct.introductoryDiscount {
           Text("\(introPrice.localizedPriceString) for \(introPrice.numberOfPeriods) \(introPrice.subscriptionPeriod.unit.description)")
               .font(NSFont.body3.swiftUIFont)
               .foregroundStyle(Color.green)
       } else {
           Text("")
       }
   }
   var body: some View {
       HStack {
           VStack(alignment: .leading, spacing: 4) {
               Text(package.storeProduct.localizedTitle)
                   .font(NSFont.body1.swiftUIFont)
                   .foregroundStyle(Color.onSurface)
               
               Text(package.storeProduct.localizedDescription)
                   .font(NSFont.body2.swiftUIFont)
                   .foregroundStyle(Color.onSurfaceVariant)
                   .lineLimit(2)
           }
           
           Spacer()
           
           VStack(alignment: .trailing, spacing: 4) {
               Text(package.localizedPriceString)
                   .font(NSFont.heading4.swiftUIFont)
                   .foregroundStyle(Color.onSurface)
               priceView
           }
       }
       .padding(12)
       .background(
           RoundedRectangle(cornerRadius: 8)
               .fill(isCurrentPlan ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
               .overlay(
                   RoundedRectangle(cornerRadius: 8)
                       .stroke(isCurrentPlan ? Color.blue : Color.clear, lineWidth: 1)
               )
       )
       .overlay(
           HStack {
               Spacer()
               if isCurrentPlan {
                   Text("Current")
                       .font(NSFont.body3.swiftUIFont)
                       .foregroundColor(.blue)
                       .padding(.horizontal, 8)
                       .padding(.vertical, 2)
                       .background(Color.blue.opacity(0.1))
                       .cornerRadius(4)
               } else {
                   Button {
                       Task {
                           isPurchasing = true
                           await onPurchase()
                           isPurchasing = false
                       }
                   } label: {
                       if isPurchasing {
                           ProgressView()
                               .scaleEffect(0.8)
                       } else {
                           Text("Subscribe")
                       }
                   }
                   .buttonStyle(AccountButtonStyle(
                       foregroundColor: .white,
                       backgroundColor: .blue,
                       borderColor: .blue,
                       cornerRadius: 6
                   ))
                   .disabled(isPurchasing)
               }
           }
           .padding(.trailing, 12),
           alignment: .trailing
       )
   }
}
