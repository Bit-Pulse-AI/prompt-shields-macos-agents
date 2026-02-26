import Foundation
import SwiftData

// MARK: - Subscription Model

struct Subscription: Domain {
    typealias M = SubscriptionModel
    typealias P = SubscriptionPersistentModel

    struct SubscriptionModel: Model {
        var uuid: UID
        var name: String
        var tier: String
        var organisationUID: UID
        var createdAt: Date
        var modifiedAt: Date
    }

    let identifier: ModelIdentifier?
    var model: Subscription.SubscriptionModel

    init(model: SubscriptionModel) {
        self.model = model
        self.identifier = nil
    }

    init(model: SubscriptionModel, identifier: ModelIdentifier?) {
        self.model = model
        self.identifier = identifier
    }

    // MARK: - Mapping Methods
    func toPersistentModel(context: ModelContext?) -> SubscriptionPersistentModel {
        let persistent = SubscriptionPersistentModel()
        persistent.uuid = model.uuid.encrypt
        persistent.name = model.name.encrypt
        persistent.tier = model.tier.encrypt
        persistent.createdAt = model.createdAt
        persistent.modifiedAt = model.modifiedAt
        return persistent
    }

    static func fromPersistentModel(_ persistent: SubscriptionPersistentModel) -> Subscription {
        let model = SubscriptionModel(
            uuid: persistent.uuid.decrypt,
            name: persistent.name.decrypt,
            tier: persistent.tier.decrypt,
            organisationUID: persistent.organisationUID,
            createdAt: persistent.createdAt,
            modifiedAt: persistent.modifiedAt
        )
        return Subscription(model: model, identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
}

// MARK: - API Models

struct SubscriptionAPIResponse: APIResponse {
    let id: String
    let name: String
    let tier: String
    let origanisationUID: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case tier
        case origanisationUID = "organisation_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> Subscription {
        let dateFormatter = ISO8601DateFormatter()
        let model = Subscription.SubscriptionModel(
            uuid: id,
            name: name,
            tier: tier,
            organisationUID: origanisationUID,
            createdAt: dateFormatter.date(from: createdAt) ?? Date(),
            modifiedAt: dateFormatter.date(from: updatedAt) ?? Date()
        )
        return Subscription(model: model)
    }
}

struct SubscriptionAPIRequest: Codable {
    let name: String
    let tier: String

    init(from subscription: Subscription) {
        self.name = subscription.model.name
        self.tier = subscription.model.tier
    }

    enum CodingKeys: String, CodingKey {
        case name
        case tier
    }
}

// MARK: - Persistent Model

@Model
final class SubscriptionPersistentModel: UpdatablePersistentModel {
    var uuid: UID = ""
    var pk: String?
    var ik: String?
    var name: String = ""
    var tier: String = ""
    var iconUrl: String?
    var teams: [TeamPersistentModel] = []
    var organisationUID: UID = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var stripeSubscriptionId: String?
    var stripeCustomerId: String?
    var stripeBillingPeriod: String?
    var stripePeriodStart: String?
    var stripePeriodEnd: String?
    var cancelAtPeriodEnd: Bool?
    var cancelledAt: Date?
    var stripeStatus: String?

    init() {
        // Default initializer for SwiftData
    }

    func updateProperties(from other: SubscriptionPersistentModel) {
        self.uuid = other.uuid
        self.name = other.name
        self.tier = other.tier
        self.iconUrl = other.iconUrl
        self.teams = other.teams
        self.organisationUID = other.organisationUID
        self.createdAt = other.createdAt
        self.modifiedAt = other.modifiedAt
        self.stripeSubscriptionId = other.stripeSubscriptionId
        self.stripeCustomerId = other.stripeCustomerId
        self.stripeBillingPeriod = other.stripeBillingPeriod
        self.stripePeriodStart = other.stripePeriodStart
        self.stripePeriodEnd = other.stripePeriodEnd
        self.cancelAtPeriodEnd = other.cancelAtPeriodEnd
        self.cancelledAt = other.cancelledAt
        self.stripeStatus = other.stripeStatus
    }
}

// MARK: - Subscription Tier

enum SubscriptionTier: String, CaseIterable, Codable {
    case tin = "tin"
    case bronze = "bronze"

    var encrypt: String {
        rawValue.encrypt
    }
}

extension Subscription {
    var encrypt: Subscription {
        let model = SubscriptionModel(uuid: model.uuid.encrypt,
                                      name: model.name.encrypt,
                                      tier: model.tier.encrypt,
                                      organisationUID: model.organisationUID.encrypt,
                                      createdAt: model.createdAt,
                                      modifiedAt: model.modifiedAt)
        return Subscription(model: model,
                            identifier: identifier)
    }
}

private extension Date {
    var string: String {
        let dateFormatter = ISO8601DateFormatter()
        return dateFormatter.string(from: self)
    }
}

private extension String {
    var date: Date? {
        let dateFormatter = ISO8601DateFormatter()
        return dateFormatter.date(from: self)
    }
}
