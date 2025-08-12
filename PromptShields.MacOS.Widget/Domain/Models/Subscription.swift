import Foundation
import SwiftData

// MARK: - Subscription Model

struct Subscription: Domain {
    typealias M = SubscriptionModel
    typealias P = SubscriptionPersistentModel
    typealias R = SubscriptionAPIResponse
    
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
    
    static func fromAPIResponse(_ response: Data) throws -> Subscription {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let subscriptionDTO = try decoder.decode(SubscriptionAPIResponse.self, from: response)
        return subscriptionDTO.toDomain()
    }
    
    func toAPIRequest() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let request = SubscriptionAPIRequest(from: self)
        return try encoder.encode(request)
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
    }
}

// MARK: - Subscription Tier

enum SubscriptionTier: String, CaseIterable, Codable {
    case tin = "tin"
    case bronze = "bronze"
    case silver = "silver"
    case gold = "gold"
    case platinum = "platinum"
    
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
