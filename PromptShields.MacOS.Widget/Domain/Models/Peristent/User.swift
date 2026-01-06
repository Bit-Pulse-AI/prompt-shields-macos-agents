import Foundation
import SwiftData

struct User: Domain {
    typealias M = UserModel
    typealias P = UserPersistentModel

    struct UserModel: Model {
        var uuid: UID
        var email: String
        var firstName: String
        var lastName: String
        var photoURL: URL?
        var profileId: UID?
        var preferenceId: UID?
        let createdAt: Date
        let modifiedAt: Date
    }

    let identifier: ModelIdentifier?
    var model: User.UserModel

    init(model: UserModel) {
        self.model = model
        self.identifier = nil
    }

    init(model: UserModel, identifier: ModelIdentifier?) {
        self.model = model
        self.identifier = identifier
    }

    // MARK: - Mapping Methods

    func toPersistentModel(context: ModelContext?) -> UserPersistentModel {
        let persistent = UserPersistentModel()
        persistent.uuid = model.uuid.encrypt
        persistent.email = model.email.encrypt
        persistent.profileId = model.profileId?.encrypt
        persistent.preferenceId = model.preferenceId?.encrypt
        persistent.firstName = model.firstName.encrypt
        persistent.lastName = model.lastName.encrypt
        persistent.photoURL = model.photoURL?.absoluteString.encrypt
        persistent.createdAt = model.createdAt
        persistent.modifiedAt = model.modifiedAt
        return persistent
    }

    static func fromPersistentModel(_ persistent: UserPersistentModel) -> User {
        let model = UserModel(
            uuid: persistent.uuid.decrypt,
            email: persistent.email.decrypt,
            firstName: persistent.firstName.decrypt,
            lastName: persistent.lastName.decrypt,
            photoURL: persistent.photoURL != nil ? URL(string: persistent.photoURL!.decrypt) : nil,
            profileId: persistent.profileId?.decrypt,
            preferenceId: persistent.preferenceId?.decrypt,
            createdAt: persistent.createdAt,
            modifiedAt: persistent.modifiedAt
        )
        return User(model: model, identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
}

// MARK: - API Models

struct UserAPIResponse: APIResponse, Encodable {
    let id: String
    let firstName: String
    let lastName: String
    let email: String?
    let accessToken: String
    let refreshToken: String?
    let photoURL: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case firstName
        case lastName
        case email
        case photoURL
        case accessToken
        case refreshToken
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain(profileId: UID?, preferenceId: UID?) -> User {
        let model = User.UserModel(
            uuid: id,
            email: email ?? "",
            firstName: firstName,
            lastName: lastName,
            photoURL: try? photoURL?.url,
            profileId: profileId,
            preferenceId: preferenceId,
            createdAt: createdAt,
            modifiedAt: updatedAt
        )
        return User(model: model)
    }

    func toDomain() -> some Domain {
        toDomain(profileId: nil, preferenceId: nil)
    }
}

struct UserAPIRequest: Codable {
    let email: String
    let firstName: String?
    let lastName: String?
    let photoUrl: String?

    init(from user: User) {
        self.email = user.model.email
        self.firstName = user.model.firstName
        self.lastName = user.model.lastName
        self.photoUrl = user.model.photoURL?.absoluteString
    }

    enum CodingKeys: String, CodingKey {
        case email
        case firstName = "first_name"
        case lastName = "last_name"
        case photoUrl = "photo_url"
    }
}

// MARK: - Persistent Model

@Model
final class UserPersistentModel: UpdatablePersistentModel {
    var uuid: UID = ""
    var pk: String?
    var ik: String?
    var email: String = ""
    var firstName: String = "n/a"
    var lastName: String = "n/a"
    var photoURL: String?
    var profileId: UID?
    var preferenceId: UID?
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    init() {
        // Default initializer for SwiftData
    }

    func updateProperties(from other: UserPersistentModel) {
        self.uuid = other.uuid
        self.email = other.email
        self.firstName = other.firstName
        self.lastName = other.lastName
        self.photoURL = other.photoURL
        self.profileId = other.profileId
        self.preferenceId = other.preferenceId
        self.createdAt = other.createdAt
        self.modifiedAt = other.modifiedAt
    }
}
