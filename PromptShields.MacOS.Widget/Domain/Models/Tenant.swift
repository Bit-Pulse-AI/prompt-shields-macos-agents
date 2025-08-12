import Foundation
import SwiftData

struct Tenant: Domain {
    typealias M = TenantModel
    typealias P = TenantPersistentModel
    typealias R = TenantAPIResponse
    
    struct TenantModel: Model {
        var uuid: UID
        var name: String
        var description: String?
        var customerId: String?
        var organisations: [Organisation]?
        var createdAt: Date
        var modifiedAt: Date
    }
    
    let identifier: ModelIdentifier?
    var model: Tenant.TenantModel
    
    init(model: TenantModel) {
        self.model = model
        self.identifier = nil
    }
    
    init(model: TenantModel, identifier: ModelIdentifier?) {
        self.model = model
        self.identifier = identifier
    }
    
    // MARK: - Mapping Methods
    
    func toPersistentModel(context: ModelContext?) -> TenantPersistentModel {
        let persistent = TenantPersistentModel()
        persistent.uuid = model.uuid.encrypt
        persistent.name = model.name.encrypt
        persistent.details = model.description?.encrypt
        persistent.customerId = model.customerId?.encrypt
        persistent.organisations = model.organisations?.map { $0.toPersistentModel(context: context) } ?? []
        persistent.createdAt = model.createdAt
        persistent.modifiedAt = model.modifiedAt
        return persistent
    }
    
    static func fromPersistentModel(_ persistent: TenantPersistentModel) -> Tenant {
        let model = TenantModel(
            uuid: persistent.uuid.decrypt,
            name: persistent.name.decrypt,
            description: persistent.details?.decrypt,
            customerId: persistent.customerId?.decrypt,
            organisations: persistent.organisations.map { Organisation.fromPersistentModel($0) },
            createdAt: persistent.createdAt,
            modifiedAt: persistent.modifiedAt
        )
        return Tenant(model: model, identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
    
    static func fromAPIResponse(_ response: Data) throws -> Tenant {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let tenantDTO = try decoder.decode(TenantAPIResponse.self, from: response)
        return tenantDTO.toDomain()
    }
    
    func toAPIRequest() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let request = TenantAPIRequest(from: self)
        return try encoder.encode(request)
    }
}

// MARK: - API Models

struct TenantAPIResponse: APIResponse {
    let id: String
    let name: String
    let description: String?
    let customerId: String?
    let createdAt: String
    let updatedAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case customerId = "customer_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    func toDomain() -> Tenant {
        let dateFormatter = ISO8601DateFormatter()
        let model = Tenant.TenantModel(
            uuid: id,
            name: name,
            description: description,
            customerId: customerId,
            organisations: nil, // Will be resolved from persistence
            createdAt: dateFormatter.date(from: createdAt) ?? Date(),
            modifiedAt: dateFormatter.date(from: updatedAt) ?? Date()
        )
        return Tenant(model: model)
    }
}

struct TenantAPIRequest: Codable {
    let name: String
    let description: String?
    let customerId: String?
    
    init(from tenant: Tenant) {
        self.name = tenant.model.name
        self.description = tenant.model.description
        self.customerId = tenant.model.customerId
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case description
        case customerId = "customer_id"
    }
}

// MARK: - Persistent Model

@Model
final class TenantPersistentModel: UpdatablePersistentModel {
    var uuid: String = ""
    var pk: String?
    var ik: String?
    var name: String = ""
    var details: String? // was description
    var customerId: String?
    var organisations: [OrganisationPersistentModel] = []
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    
    init() {}
    
    func updateProperties(from other: TenantPersistentModel) {
        self.uuid = other.uuid
        self.name = other.name
        self.details = other.details
        self.customerId = other.customerId
        self.organisations = other.organisations
        self.createdAt = other.createdAt
        self.modifiedAt = other.modifiedAt
    }
}

extension Tenant {
    var encrypt: Tenant {
        let model = TenantModel(uuid: model.uuid,
                                name: model.name,
                                createdAt: model.createdAt,
                                modifiedAt: model.modifiedAt)
        return Tenant(model: model,
                      identifier: identifier)
    }
}
