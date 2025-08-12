import SwiftUI
import RevenueCat
import os

struct AccountView: View {
    @EnvironmentObject private var mainState: MainStateModel
    
    @State var offerings: Offerings?
    @State var customerInfo: CustomerInfo?
    @State var isLoading = false
    @State var showCreateOrganisation = false
    @State var showCreateSubscription = false
    @State var showCreateTeam = false
    @State var newOrganisationName = ""
    @State var accountEmail = "n/a"
    @State var accountFirstName = "n/a"
    @State var accountLastName = "n/a"
    @State var accountPhoto: URL?
    
    @Environment(\.userDomainService) private var userDomainService

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AccountView.self)
    )
    
    private let accountButtonStyle = AccountButtonStyle(foregroundColor: Color.primary,
                                                        backgroundColor: .white,
                                                        borderColor: .border,
                                                        cornerRadius: 8)
    
    private let accountDeleteButtonStyle = AccountButtonStyle(foregroundColor: .primary,
                                                              backgroundColor: .white,
                                                              borderColor: .border,
                                                              cornerRadius: 8,
                                                              imageName: "fi-rr-trash")

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                RoundBox(title: "Account") {
                    VStack(spacing: 24) {
                        photoSection
                        nameSection
                        emailSection
                    }.frame(maxWidth: .infinity)
                }
                RoundBox(title: "Subscription details") {
                    subscriptionSection
                        .frame(maxWidth: .infinity)
                }
                RoundBox(title: "Logout") {
                    logoutView
                        .frame(maxWidth: .infinity)
                }
                RoundBox(title: "Delete account") {
                    deleteAccount
                        .frame(maxWidth: .infinity)
                }.padding(.bottom, 32)
            }
        }.task {
            await fetchUserDetails()
        }
    }
    
    func fetchUserDetails() async {
        do {
            let currentUser = try await userDomainService.currentUser
            accountLastName = currentUser.model.lastName
            accountFirstName = currentUser.model.firstName
            accountPhoto = currentUser.model.photoURL
            accountEmail = currentUser.model.email
        } catch {
            logger.error("Error fetching user details \(error)")
        }
    }
    
    func titledTextField(title: String, placeholder: String, binding: Binding<String>) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(NSFont.body4.swiftUIFont)
                .foregroundStyle(Color.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            TextField(placeholder, text: binding)
                .modifier(AccountTextFieldModifier(foregroundColor: .onSurface,
                                                   backgroundColor: .white,
                                                   borderColor: .border,
                                                   cornerRadius: 8))
        }.frame(alignment: .leading)
    }
    
    var nameSection: some View {
        HStack(spacing: .zero) {
            titledTextField(title: "First name", placeholder: "First name", binding: $accountFirstName)
            titledTextField(title: "Last name", placeholder: "Last name", binding: $accountLastName)
        }
    }
    
    var emailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Email")
                .font(NSFont.body1.swiftUIFont)
                .foregroundStyle(Color.onSurface)
            Text(verbatim: accountEmail)
            Text("To change your email, please contact support@promptshields.com")
        }
        .frame(maxWidth: .infinity,
               alignment: .leading)
        .multilineTextAlignment(.leading)
    }
    
    var photoSection: some View {
        HStack {
            RoundCirclePortraitView(url: $accountPhoto)
                .frame(width: 80, height: 80)
            Button {
                changePhoto()
            } label: {
                Text("Change photo")
            }
            .buttonStyle(accountButtonStyle)
            Button {
                deletePhoto()
            } label: {
                Text("Delete photo")
            }
            .buttonStyle(accountDeleteButtonStyle)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let customerInfo = customerInfo {
                // Current subscription info
                if let currentSubscription = customerInfo.entitlements.active.first {
                    planBox(title: "Current plan")
                        .padding(.bottom, 8)
                    
                    Text(currentSubscription.value.productIdentifier)
                        .font(NSFont.heading4.swiftUIFont)
                        .foregroundStyle(Color.onSurface)
                        .padding(.bottom, 8)
                    
                    if let expirationDate = currentSubscription.value.expirationDate {
                        Text("Expires: \(expirationDate, style: .date)")
                            .font(NSFont.body2.swiftUIFont)
                            .foregroundStyle(Color.onSurfaceVariant)
                            .padding(.bottom, 16)
                    }
                } else {
                    Text("No active subscription")
                        .font(NSFont.body1.swiftUIFont)
                        .foregroundStyle(Color.onSurfaceVariant)
                        .padding(.bottom, 16)
                }
                
                // Available packages
                if let offerings = offerings, let current = offerings.current {
                    Text("Available Plans")
                        .font(NSFont.heading4.swiftUIFont)
                        .foregroundStyle(Color.onSurface)
                        .padding(.bottom, 8)
                    
                    ForEach(current.availablePackages, id: \.identifier) { package in
                        SubscriptionPackageView(
                            package: package,
                            isCurrentPlan: customerInfo.entitlements.active.contains { $0.value.productIdentifier == package.storeProduct.productIdentifier }
                        ) {
                            await purchasePackage(package)
                        }
                    }
                }
                
                // Action buttons
                HStack(spacing: 8) {
                    Button {
                        manageSubscription()
                    } label: {
                        Text("Manage subscription")
                    }
                    .buttonStyle(accountButtonStyle)
                    
                    Button {
                        explorePlans()
                    } label: {
                        Text("Explore plans")
                    }
                    .buttonStyle(accountButtonStyle)
                }
            } else {
                Text("Unable to load subscription information")
                    .font(NSFont.body1.swiftUIFont)
                    .foregroundStyle(Color.onSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var deleteAccount: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text("To delete your account, please contact support@promptshields.com")
        }.frame(maxWidth: .infinity,
                alignment: .leading)
    }
    
    var logoutView: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Button {
                logout()
            } label: {
                Text("Logout")
            }
            .buttonStyle(accountButtonStyle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    func planBox(title: String) -> some View {
        Text(title)
            .font(NSFont.body3.swiftUIFont)
            .foregroundColor(.blue500)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.additionalBlue100)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.additionalBlue, lineWidth: 1)
            )
    }
    
    // Logic
    
    private func logout() {
        Task {
            try await userDomainService.logout()
            mainState.authState = .loggedOut(nil)
        }
    }
    
    private func changePhoto() {
    }
    
    private func deletePhoto() {
    }
    
    private func manageSubscription() {
    }
    
    private func explorePlans() {
    }
    
    private func purchasePackage(_ package: Package) async {
        do {
            let purchaseResult = try await Purchases.shared.purchase(package: package)
            self.customerInfo = purchaseResult.customerInfo
        } catch {
            print("Error purchasing package: \(error)")
        }
    }
    
    @MainActor
    private func loadSubscriptionData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            async let offeringsTask = Purchases.shared.offerings()
            async let customerInfoTask = Purchases.shared.customerInfo()
            
            let (offeringsResult, customerInfoResult) = try await (offeringsTask, customerInfoTask)
            
            self.offerings = offeringsResult
            self.customerInfo = customerInfoResult
        } catch {
            print("Error loading subscription data: \(error)")
        }
    }
    
    //
    //    var createOrganisationSheet: some View {
    //        VStack(spacing: 24) {
    //            Text("Create Organisation")
    //                .font(NSFont.heading3.swiftUIFont)
    //                .foregroundStyle(Color.onSurface)
    //
    //            VStack(spacing: 16) {
    //                titledTextField(title: "Organisation Name", placeholder: "Enter organisation name", binding: $newOrganisationName)
    //                titledTextField(title: "Description (Optional)", placeholder: "Enter description", binding: $newOrganisationDescription)
    //            }
    //
    //            HStack(spacing: 12) {
    //                Button("Cancel") {
    //                    showCreateOrganisation = false
    //                    newOrganisationName = ""
    //                    newOrganisationDescription = ""
    //                }
    //                .buttonStyle(accountButtonStyle)
    //
    //                Button("Create") {
    //                    createOrganisation()
    //                }
    //                .buttonStyle(AccountButtonStyle(
    //                    foregroundColor: .white,
    //                    backgroundColor: .blue,
    //                    borderColor: .blue,
    //                    cornerRadius: 8
    //                ))
    //                .disabled(newOrganisationName.isEmpty)
    //            }
    //
    //            Spacer()
    //        }
    //        .padding(24)
    //    }
    //
    //    var createSubscriptionSheet: some View {
    //        VStack(spacing: 24) {
    //            Text("Create Subscription")
    //                .font(NSFont.heading3.swiftUIFont)
    //                .foregroundStyle(Color.onSurface)
    //
    //            VStack(spacing: 16) {
    //                titledTextField(title: "Subscription Name", placeholder: "Enter subscription name", binding: $newSubscriptionName)
    //
    //                VStack(alignment: .leading, spacing: 8) {
    //                    Text("Subscription Tier")
    //                        .font(NSFont.body4.swiftUIFont)
    //                        .foregroundStyle(Color.onSurface)
    //
    //                    Picker("Tier", selection: $newSubscriptionTier) {
    //                        Text("Bronze").tag(SubscriptionTier.bronze)
    //                        Text("Silver").tag(SubscriptionTier.silver)
    //                        Text("Gold").tag(SubscriptionTier.gold)
    //                    }
    //                    .pickerStyle(SegmentedPickerStyle())
    //                }
    //            }
    //
    //            HStack(spacing: 12) {
    //                Button("Cancel") {
    //                    showCreateSubscription = false
    //                    newSubscriptionName = ""
    //                    newSubscriptionTier = .bronze
    //                }
    //                .buttonStyle(accountButtonStyle)
    //
    //                Button("Create") {
    //                    createSubscription()
    //                }
    //                .buttonStyle(AccountButtonStyle(
    //                    foregroundColor: .white,
    //                    backgroundColor: .blue,
    //                    borderColor: .blue,
    //                    cornerRadius: 8
    //                ))
    //                .disabled(newSubscriptionName.isEmpty)
    //            }
    //
    //            Spacer()
    //        }
    //        .padding(24)
    //    }
    //
    //    var createTeamSheet: some View {
    //        VStack(spacing: 24) {
    //            Text("Create Team")
    //                .font(NSFont.heading3.swiftUIFont)
    //                .foregroundStyle(Color.onSurface)
    //
    //            VStack(spacing: 16) {
    //                titledTextField(title: "Team Name", placeholder: "Enter team name", binding: $newTeamName)
    //
    //                if let organisation = selectedOrganisationForTeam {
    //                    VStack(alignment: .leading, spacing: 8) {
    //                        Text("Organisation")
    //                            .font(NSFont.body4.swiftUIFont)
    //                            .foregroundStyle(Color.onSurface)
    //                        Text(organisation.model.name)
    //                            .font(NSFont.body2.swiftUIFont)
    //                            .foregroundStyle(Color.onSurfaceVariant)
    //                    }
    //
    //                    VStack(alignment: .leading, spacing: 8) {
    //                        Text("Subscription")
    //                            .font(NSFont.body4.swiftUIFont)
    //                            .foregroundStyle(Color.onSurface)
    //
    //                        if subscriptions.isEmpty {
    //                            Text("No subscriptions available. Please create a subscription first.")
    //                                .font(NSFont.body2.swiftUIFont)
    //                                .foregroundStyle(Color.onSurfaceVariant)
    //                        } else {
    //                            Picker("Subscription", selection: $selectedSubscriptionForTeam) {
    //                                Text("Select a subscription").tag(nil as Subscription?)
    //                                ForEach(subscriptions, id: \.id) { subscription in
    //                                    Text(subscription.model.name).tag(subscription as Subscription?)
    //                                }
    //                            }
    //                            .pickerStyle(MenuPickerStyle())
    //                        }
    //                    }
    //                }
    //            }
    //
    //            HStack(spacing: 12) {
    //                Button("Cancel") {
    //                    showCreateTeam = false
    //                    newTeamName = ""
    //                    selectedOrganisationForTeam = nil
    //                    selectedSubscriptionForTeam = nil
    //                }
    //                .buttonStyle(accountButtonStyle)
    //
    //                Button("Create") {
    //                    createTeam()
    //                }
    //                .buttonStyle(AccountButtonStyle(
    //                    foregroundColor: .white,
    //                    backgroundColor: .blue,
    //                    borderColor: .blue,
    //                    cornerRadius: 8
    //                ))
    //                .disabled(newTeamName.isEmpty || selectedSubscriptionForTeam == nil)
    //            }
    //
    //            Spacer()
    //        }
    //        .padding(24)
    //    }
    //
}

extension SubscriptionPeriod.Unit {
    var description: String {
        switch self {
        case .day:
            return "day"
        case .week:
            return "week"
        case .month:
            return "month"
        case .year:
            return "year"
        @unknown default:
            return "period"
        }
    }
}

//        .sheet(isPresented: $showCreateOrganisation) {
//            createOrganisationSheet
//        }
//        .sheet(isPresented: $showCreateSubscription) {
//            createSubscriptionSheet
//        }
//        .sheet(isPresented: $showCreateTeam) {
//            createTeamSheet
//        }

//    @State private var newOrganisationDescription = ""
//    @State private var newSubscriptionName = ""
//    @State private var newSubscriptionTier: SubscriptionTier = .bronze
//    @State private var newTeamName = ""
//    @State private var selectedOrganisationForSubscription: Organisation?
//    @State private var selectedOrganisationForTeam: Organisation?
//    @State private var selectedSubscriptionForTeam: Subscription?
//    @State private var subscriptions: [Subscription] = []
//    @State private var teams: [Team] = []
//
//    var organisationSection: some View {
//        VStack(alignment: .leading, spacing: 16) {
//            HStack {
//                Text("Your Organisations")
//                    .font(NSFont.heading4.swiftUIFont)
//                    .foregroundStyle(Color.onSurface)
//                Spacer()
//                Button("Create Organisation") {
//                    showCreateOrganisation = true
//                }
//                .buttonStyle(accountButtonStyle)
//            }
//
//            if viewModel.organisations.isEmpty {
//                Text("No organisations found. Create your first organisation to get started.")
//                    .font(NSFont.body2.swiftUIFont)
//                    .foregroundStyle(Color.onSurfaceVariant)
//                    .padding(.vertical, 16)
//            } else {
//                ForEach(viewModel.organisations, id: \.id) { organisation in
//                    OrganisationCard(
//                        organisation: organisation,
//                        onEdit: { editOrganisation(organisation) },
//                        onDelete: { deleteOrganisation(organisation) },
//                        onCreateSubscription: {
//                            selectedOrganisationForSubscription = organisation
//                            showCreateSubscription = true
//                        },
//                        onCreateTeam: {
//                            selectedOrganisationForTeam = organisation
//                            showCreateTeam = true
//                        }
//                    )
//                }
//            }
//        }
//    }
