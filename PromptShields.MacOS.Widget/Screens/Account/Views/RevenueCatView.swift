import RevenueCat
import SwiftUI

struct RevenueCatPackage {
    let id: String
    let name: String
    let description: String
    let price: String
}

struct RevenueCatPackageView: View {
    
    let package: RevenueCatPackage
    
    init(package: RevenueCatPackage) {
        self.package = package
    }
    
    var body: some View {
        VStack(spacing: .zero) {
            Text(self.package.name)
            Text(self.package.price)
        }
    }
}
struct RevenueCatSubscription: View {
    
    @State private var packages: [RevenueCatPackage] = []
    
    var body: some View {
        HStack {
            ForEach(packages, id: \.id) { package in
                RevenueCatPackageView(package: package)
            }
        }.task {
            fetchOfferings()
        }
    }
    
    func fetchOfferings() {
        Purchases.shared.getOfferings { (offerings, error) in
            if let error = error {
                print("Error fetching offerings: \(error.localizedDescription)")
            } else if let packages = offerings?.current?.availablePackages {
                self.packages = packages.compactMap {
                    RevenueCatPackage(id: $0.identifier,
                                      name: $0.storeProduct.localizedTitle,
                                      description: $0.storeProduct.localizedDescription,
                                      price: $0.localizedPriceString,)
                }
            }
        }
    }
}
