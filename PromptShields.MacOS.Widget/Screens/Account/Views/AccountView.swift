import SwiftUI
import os

struct AccountView: View {
    @EnvironmentObject private var mainState: MainStateModel

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
                    HStack(alignment: .center) {
                        if isLoading {
                            ProgressView()
                        } else {
                            logoutView
                                .frame(maxWidth: .infinity)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
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

    @MainActor
    func fetchUserDetails() async {
        do {
            let currentUser = try await userDomainService.currentUser
            accountLastName = currentUser.model.lastName
            accountFirstName = currentUser.model.firstName
            accountPhoto = currentUser.model.photoURL
            accountEmail = currentUser.model.email
        } catch {
            logger.debug("Error fetching user details \(error)")
        }
    }

    func titledTextField(title: String, placeholder: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(NSFont.body4.swiftUIFont)
                .foregroundStyle(Color.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(binding.wrappedValue)
//                .modifier(AccountTextFieldModifier(foregroundColor: .onSurface,
//                                                   backgroundColor: .white,
//                                                   borderColor: .border,
//                                                   cornerRadius: 8))
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
//            Button {
//                changePhoto()
//            } label: {
//                Text("Change photo")
//            }
//            .buttonStyle(accountButtonStyle)
//            Button {
//                deletePhoto()
//            } label: {
//                Text("Delete photo")
//            }
//            .buttonStyle(accountDeleteButtonStyle)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SubscriptionIntegrationView()
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
        Task { @MainActor in
            isLoading = true
            try? await userDomainService.logout()
            mainState.authState = .loggedOut(nil)
            isLoading = false
        }
    }

    private func changePhoto() {
    }

    private func deletePhoto() {
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
