import Foundation
import SwiftData

enum PanelPosition: String, CaseIterable, Codable {
    case left = "left"
    case right = "right"
    case top = "top"
    case bottom = "bottom"

    var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
}

struct UserPreferences: Domain {
    typealias M = UserPreferencesModel
    typealias P = UserPreferencesPersistentModel

    struct UserPreferencesModel: Model {
        let uuid: UID
        var enabledSuggestionTypes: [String]
    }

    let identifier: ModelIdentifier?
    var model: UserPreferences.UserPreferencesModel

    init(model: UserPreferencesModel) {
        self.model = model
        self.identifier = nil
    }

    init(model: UserPreferencesModel, identifier: ModelIdentifier?) {
        self.model = model
        self.identifier = identifier
    }

    // MARK: - Mapping Methods

    func toPersistentModel(context: ModelContext?) -> UserPreferencesPersistentModel {
        let persistent = UserPreferencesPersistentModel()
        persistent.ik = try? model.uuid.sha512
        persistent.uuid = model.uuid
        persistent.enabledSuggestionTypes = model.enabledSuggestionTypes
        return persistent
    }

    static func fromPersistentModel(_ persistent: UserPreferencesPersistentModel) -> UserPreferences {
        let model = UserPreferencesModel(
            uuid: persistent.uuid,
            enabledSuggestionTypes: persistent.enabledSuggestionTypes
        )
        return UserPreferences(model: model, identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
}

// MARK: - Persistent Model

@Model
final class UserPreferencesPersistentModel: UpdatablePersistentModel {
    var uuid: String = ""
    var enabledSuggestionTypes: [String] = []

    var pk: String?
    var ik: String?

    init() {}

    func updateProperties(from preferences: UserPreferencesPersistentModel) {
        self.uuid = preferences.uuid
        self.ik = preferences.ik
        self.enabledSuggestionTypes = preferences.enabledSuggestionTypes
    }
}
