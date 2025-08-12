import SwiftUI

struct OrganisationCard: View {
    let organisation: Organisation
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCreateSubscription: () -> Void
    let onCreateTeam: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(organisation.model.name)
                        .font(NSFont.heading4.swiftUIFont)
                        .foregroundStyle(Color.onSurface)
                    
                    if let description = organisation.model.description {
                        Text(description)
                            .font(NSFont.body2.swiftUIFont)
                            .foregroundStyle(Color.onSurfaceVariant)
                    }
                }
                
//                Spacer()
//                
//                Menu {
//                    Button("Edit") {
//                        onEdit()
//                    }
//                    Button("Create Subscription") {
//                        onCreateSubscription()
//                    }
//                    Button("Create Team") {
//                        onCreateTeam()
//                    }
//                    Divider()
//                    Button("Delete", role: .destructive) {
//                        onDelete()
//                    }
//                } label: {
//                    Image(systemName: "ellipsis")
//                        .foregroundStyle(Color.onSurfaceVariant)
//                }
            }
            
            HStack(spacing: 8) {
                Button("Create Subscription") {
                    onCreateSubscription()
                }
                .buttonStyle(AccountButtonStyle(
                    foregroundColor: .blue,
                    backgroundColor: .blue.opacity(0.1),
                    borderColor: .blue,
                    cornerRadius: 6
                ))
                
                Button("Create Team") {
                    onCreateTeam()
                }
                .buttonStyle(AccountButtonStyle(
                    foregroundColor: .green,
                    backgroundColor: .green.opacity(0.1),
                    borderColor: .green,
                    cornerRadius: 6
                ))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.border, lineWidth: 1)
                )
        )
    }
 }
