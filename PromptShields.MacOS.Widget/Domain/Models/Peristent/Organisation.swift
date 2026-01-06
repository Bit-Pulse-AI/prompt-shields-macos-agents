import Foundation
import SwiftData

struct Organisation: Domain {
    typealias M = OrganisationModel
    typealias P = OrganisationPersistentModel

    struct OrganisationModel: Model {
        var uuid: UID
        var name: String
        var description: String?
        var subscriptions: [Subscription]?
        let tenantUID: UID?
        let createdAt: Date
        var modifiedAt: Date
    }

    let identifier: ModelIdentifier?
    var model: Organisation.OrganisationModel

    init(model: OrganisationModel) {
        self.model = model
        self.identifier = nil
    }

    init(model: OrganisationModel, identifier: ModelIdentifier?) {
        self.model = model
        self.identifier = identifier
    }

    // MARK: - Mapping Methods

    func toPersistentModel(context: ModelContext?) -> OrganisationPersistentModel {
        let persistent = OrganisationPersistentModel()
        persistent.uuid = model.uuid.encrypt
        persistent.name = model.name.encrypt
        persistent.details = model.description?.encrypt
        persistent.subscriptions = model.subscriptions?.map { $0.toPersistentModel(context: context) } ?? []
        persistent.tenantUID = model.tenantUID
        persistent.createdAt = model.createdAt
        persistent.modifiedAt = model.modifiedAt
        return persistent
    }

    static func fromPersistentModel(_ persistent: OrganisationPersistentModel) -> Organisation {
        let model = OrganisationModel(
            uuid: persistent.uuid.decrypt,
            name: persistent.name.decrypt,
            description: persistent.details?.decrypt,
            subscriptions: persistent.subscriptions.map { Subscription.fromPersistentModel($0) },
            tenantUID: persistent.tenantUID,
            createdAt: persistent.createdAt,
            modifiedAt: persistent.modifiedAt
        )
        return Organisation(model: model, identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
}

// MARK: - API Models

struct OrganisationAPIResponse: APIResponse {
    let id: String
    let name: String
    let description: String?
    let subscriptionCount: Int
    let tenantId: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case subscriptionCount = "subscription_count"
        case tenantId = "tenant_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> Organisation {
        let dateFormatter = ISO8601DateFormatter()
        let model = Organisation.OrganisationModel(
            uuid: id,
            name: name,
            description: description,
            subscriptions: nil,
            tenantUID: tenantId,
            createdAt: dateFormatter.date(from: createdAt) ?? Date(),
            modifiedAt: dateFormatter.date(from: updatedAt) ?? Date()
        )
        return Organisation(model: model)
    }
}

struct OrganisationAPIRequest: Codable {
    let name: String
    let description: String?

    init(from organisation: Organisation) {
        self.name = organisation.model.name
        self.description = organisation.model.description
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
    }
}

// MARK: - Persistent Model

@Model
final class OrganisationPersistentModel: UpdatablePersistentModel {
    var uuid: String = ""
    var pk: String?
    var ik: String?
    var name: String = ""
    var details: String? // was description
    var customerId: String?
    var subscriptions: [SubscriptionPersistentModel] = []
    var tenantUID: UID?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init() {
        // Default initializer for SwiftData
    }

    func updateProperties(from other: OrganisationPersistentModel) {
        self.uuid = other.uuid
        self.name = other.name
        self.details = other.details
        self.customerId = other.customerId
        self.subscriptions = other.subscriptions
        self.tenantUID = other.tenantUID
        self.createdAt = other.createdAt
        self.modifiedAt = other.modifiedAt
    }
}

extension Organisation {
    var encrypt: Organisation {
        let model = OrganisationModel(uuid: model.uuid.encrypt,
                                      name: model.name.encrypt,
                                      tenantUID: model.tenantUID?.encrypt,
                                      createdAt: model.createdAt,
                                      modifiedAt: model.modifiedAt)
        return Organisation(model: model,
                            identifier: identifier)
    }
}
