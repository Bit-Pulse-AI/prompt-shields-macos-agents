import Foundation
import SwiftData

struct Team: Domain {
    typealias M = TeamModel
    typealias P = TeamPersistentModel

    struct TeamModel: Model {
        var uuid: UID
        var name: String
        var description: String?
        var subscription: Subscription?
        var members: [User]?
        var status: String
        var createdAt: Date
        var modifiedAt: Date
    }

    let identifier: ModelIdentifier?
    var model: Team.TeamModel

    init(model: TeamModel) {
        self.model = model
        self.identifier = nil
    }

    init(model: TeamModel, identifier: ModelIdentifier?) {
        self.model = model
        self.identifier = identifier
    }

    // MARK: - Mapping Methods

    func toPersistentModel(context: ModelContext?) -> TeamPersistentModel {
        let persistent = TeamPersistentModel()
        persistent.uuid = model.uuid.encrypt
        persistent.name = model.name.encrypt
        persistent.details = model.description?.encrypt
        persistent.subscription = model.subscription?.toPersistentModel(context: context)
        persistent.members = model.members?.map { $0.toPersistentModel(context: context) } ?? []
        persistent.status = model.status.encrypt
        persistent.createdAt = model.createdAt
        persistent.modifiedAt = model.modifiedAt
        return persistent
    }

    static func fromPersistentModel(_ persistent: TeamPersistentModel) -> Team {
        let model = TeamModel(
            uuid: persistent.uuid.decrypt,
            name: persistent.name.decrypt,
            description: persistent.details?.decrypt,
            subscription: persistent.subscription.map { Subscription.fromPersistentModel($0) },
            members: persistent.members.map { User.fromPersistentModel($0) },
            status: persistent.status.decrypt,
            createdAt: persistent.createdAt,
            modifiedAt: persistent.modifiedAt
        )
        return Team(model: model, identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
}

// MARK: - API Models

struct TeamAPIResponse: APIResponse {
    let id: String
    let name: String
    let description: String?
    let subscriptionId: String
    let teamStatus: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case subscriptionId = "subscription_id"
        case teamStatus = "team_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> Team {
        let dateFormatter = ISO8601DateFormatter()
        let model = Team.TeamModel(
            uuid: id,
            name: name,
            description: description,
            subscription: nil, // Will be resolved from persistence
            members: nil, // Will be resolved from persistence
            status: teamStatus,
            createdAt: dateFormatter.date(from: createdAt) ?? Date(),
            modifiedAt: dateFormatter.date(from: updatedAt) ?? Date()
        )
        return Team(model: model)
    }
}

struct TeamAPIRequest: Codable {
    let name: String
    let description: String?

    init(from team: Team) {
        self.name = team.model.name
        self.description = team.model.description
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
    }
}

// MARK: - Persistent Model

@Model
final class TeamPersistentModel: UpdatablePersistentModel {
    var uuid: String = ""
    var pk: String?
    var ik: String?
    var name: String = ""
    var details: String? // was description
    var subscription: SubscriptionPersistentModel?
    var channelCount: Int = 0
    var members: [UserPersistentModel] = []
    var status: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init() {
        // Default initializer for SwiftData
    }

    func updateProperties(from other: TeamPersistentModel) {
        self.uuid = other.uuid
        self.name = other.name
        self.details = other.details
        self.channelCount = other.channelCount
        self.subscription = other.subscription
        self.members = other.members
        self.status = other.status
        self.createdAt = other.createdAt
        self.modifiedAt = other.modifiedAt
    }
}

// MARK: - Team Status

enum TeamStatus: String, CaseIterable, Codable {
    case active = "active"
    case archived = "archived"
    case deleted = "deleted"

    var encrypt: String {
        rawValue.encrypt
    }
}

extension Team {
    var encrypt: Team {
        let model = TeamModel(uuid: model.uuid,
                              name: model.name,
                              status: model.status.encrypt,
                              createdAt: model.createdAt,
                              modifiedAt: model.modifiedAt)
        return Team(model: model,
                    identifier: identifier)
    }
}
