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
        var isEnabled: Bool
        var enabledSuggestionTypes: [String]
        var blockedApplications: [String]
        let language: String
        var autoApplySuggestions: Bool
        var showFloatingPanel: Bool
        var panelPosition: PanelPosition
        let lastUpdated: Date
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
        persistent.isEnabled = model.isEnabled
        persistent.enabledSuggestionTypes = Array(model.enabledSuggestionTypes)
        persistent.blockedApplications = Array(model.blockedApplications)
        persistent.language = model.language
        persistent.autoApplySuggestions = model.autoApplySuggestions
        persistent.showFloatingPanel = model.showFloatingPanel
        persistent.panelPosition = model.panelPosition.rawValue
        persistent.lastUpdated = model.lastUpdated
        return persistent
    }
    
    static func fromPersistentModel(_ persistent: UserPreferencesPersistentModel) -> UserPreferences {
        let model = UserPreferencesModel(
            uuid: persistent.uuid,
            isEnabled: persistent.isEnabled,
            enabledSuggestionTypes: persistent.enabledSuggestionTypes,
            blockedApplications: persistent.blockedApplications,
            language: persistent.language,
            autoApplySuggestions: persistent.autoApplySuggestions,
            showFloatingPanel: persistent.showFloatingPanel,
            panelPosition: PanelPosition(rawValue: persistent.panelPosition) ?? .right,
            lastUpdated: persistent.lastUpdated
        )
        return UserPreferences(model: model, identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
}

// MARK: - API Models

struct UserPreferencesAPIResponse: APIResponse, Encodable {
    let isEnabled: Bool
    let enabledSuggestionTypes: [String]
    let blockedApplications: [String]
    let language: String
    let autoApplySuggestions: Bool
    let showFloatingPanel: Bool
    let panelPosition: String
    
    enum CodingKeys: String, CodingKey {
        case isEnabled
        case enabledSuggestionTypes
        case blockedApplications
        case language
        case autoApplySuggestions
        case showFloatingPanel
        case panelPosition
    }
    
    func toDomain() -> some Domain {
        let model = UserPreferences.UserPreferencesModel(
            uuid: "",
            isEnabled: isEnabled,
            enabledSuggestionTypes: enabledSuggestionTypes,
            blockedApplications: blockedApplications,
            language: language,
            autoApplySuggestions: autoApplySuggestions,
            showFloatingPanel: showFloatingPanel,
            panelPosition: PanelPosition(rawValue: panelPosition) ?? .right,
            lastUpdated: Date()
        )
        return UserPreferences(model: model)
    }
}

// MARK: - Persistent Model

@Model
final class UserPreferencesPersistentModel: UpdatablePersistentModel {
    var uuid: String = ""
    var isEnabled: Bool = true
    
    var enabledSuggestionTypesData: Data?
    var enabledSuggestionTypes: [String] {
        get {
            guard let enabledSuggestionTypesData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: enabledSuggestionTypesData)) ?? []
        }
        set {
            enabledSuggestionTypesData = try? JSONEncoder().encode(newValue)
        }
    }
    var blockedApplicationsData: Data?
    var blockedApplications: [String] {
        get {
            guard let blockedApplicationsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: blockedApplicationsData)) ?? []
        }
        set {
            blockedApplicationsData = try? JSONEncoder().encode(newValue)
        }
    }
    var language: String = "en"
    var autoApplySuggestions: Bool = false
    var showFloatingPanel: Bool = true
    var panelPosition: String = "right"
    var lastUpdated: Date = Date()
    
    var pk: String?
    var ik: String?
    
    init() {}
    
    func updateProperties(from preferences: UserPreferencesPersistentModel) {
        self.uuid = preferences.uuid
        self.ik = preferences.ik
        self.isEnabled = preferences.isEnabled
        self.enabledSuggestionTypes = preferences.enabledSuggestionTypes
        self.blockedApplications = Array(preferences.blockedApplications)
        self.language = preferences.language
        self.autoApplySuggestions = preferences.autoApplySuggestions
        self.showFloatingPanel = preferences.showFloatingPanel
        self.panelPosition = preferences.panelPosition
        self.lastUpdated = preferences.lastUpdated
    }
}
