import Foundation
import SwiftData

/// Represents a user-customizable suggestion type
/// Suggestion types define how user text is processed by the LLM
struct SuggestionType: Domain {
    typealias M = SuggestionTypeModel
    typealias P = SuggestionTypePersistentModel

    struct SuggestionTypeModel: Model {
        var uuid: UID
        let typeKey: String
        let name: String
        var description: String
        let category: String
        var systemPrompt: String
        var icon: String
        let isDefault: Bool
        var isEnabled: Bool
        var sortOrder: Int
        let createdAt: Date?
        let updatedAt: Date?
    }

    let identifier: ModelIdentifier?
    var model: SuggestionType.SuggestionTypeModel

    init(model: SuggestionTypeModel) {
        self.model = model
        self.identifier = nil
    }

    init(model: SuggestionTypeModel, identifier: ModelIdentifier?) {
        self.model = model
        self.identifier = identifier
    }

    // MARK: - Convenience Properties

    /// Display name with icon
    var displayName: String {
        "\(model.icon) \(model.name)"
    }

    /// Whether this type can be edited by the user
    var isEditable: Bool {
        true // All types are now editable
    }

    /// Whether this type can be deleted
    var isDeletable: Bool {
        !model.isDefault // Only custom types can be deleted
    }

    // MARK: - Mapping Methods

    func toPersistentModel(context: ModelContext?) -> SuggestionTypePersistentModel {
        let persistent = SuggestionTypePersistentModel()
        persistent.uuid = model.uuid.encrypt
        persistent.typeKey = model.typeKey.encrypt
        persistent.name = model.name.encrypt
        persistent.descriptionText = model.description.encrypt
        persistent.category = model.category.encrypt
        persistent.systemPrompt = model.systemPrompt.encrypt
        persistent.icon = model.icon.encrypt
        persistent.isDefault = model.isDefault
        persistent.isEnabled = model.isEnabled
        persistent.sortOrder = model.sortOrder
        persistent.createdAt = model.createdAt
        persistent.updatedAt = model.updatedAt
        return persistent
    }

    static func fromPersistentModel(_ persistent: SuggestionTypePersistentModel) -> SuggestionType {
        let model = SuggestionTypeModel(
            uuid: persistent.uuid.decrypt,
            typeKey: persistent.typeKey.decrypt,
            name: persistent.name.decrypt,
            description: persistent.descriptionText.decrypt,
            category: persistent.category.decrypt,
            systemPrompt: persistent.systemPrompt.decrypt,
            icon: persistent.icon.decrypt,
            isDefault: persistent.isDefault,
            isEnabled: persistent.isEnabled,
            sortOrder: persistent.sortOrder,
            createdAt: persistent.createdAt,
            updatedAt: persistent.updatedAt
        )
        return SuggestionType(model: model, identifier: ModelIdentifier(persistentIdentifier: persistent.persistentModelID))
    }
}

// MARK: - API Response

struct SuggestionTypeAPIResponse: APIResponse {
    let id: String
    let typeKey: String
    let name: String
    let description: String
    let category: String
    let systemPrompt: String
    let icon: String
    let isDefault: Bool
    let isEnabled: Bool
    let sortOrder: Int
    let createdAt: String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case typeKey = "type_key"
        case name
        case description
        case category
        case systemPrompt = "system_prompt"
        case icon
        case isDefault = "is_default"
        case isEnabled = "is_enabled"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomain() -> SuggestionType {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let model = SuggestionType.SuggestionTypeModel(
            uuid: id,
            typeKey: typeKey,
            name: name,
            description: description,
            category: category,
            systemPrompt: systemPrompt,
            icon: icon,
            isDefault: isDefault,
            isEnabled: isEnabled,
            sortOrder: sortOrder,
            createdAt: dateFormatter.date(from: createdAt),
            updatedAt: updatedAt.flatMap { dateFormatter.date(from: $0) }
        )
        return SuggestionType(model: model)
    }
}

/// Legacy API response for backward compatibility with /suggestion/types endpoint
struct LegacySuggestionTypeAPIResponse: APIResponse {
    let suggestionType: String
    let suggestionName: String
    let suggestionTypeCategory: String

    enum CodingKeys: String, CodingKey {
        case suggestionType = "type"
        case suggestionName = "name"
        case suggestionTypeCategory = "category"
    }

    func toDomain() -> SuggestionType {
        let model = SuggestionType.SuggestionTypeModel(
            uuid: suggestionType,
            typeKey: suggestionType,
            name: suggestionName,
            description: "",
            category: suggestionTypeCategory,
            systemPrompt: "",
            icon: String(suggestionName.prefix(2)),
            isDefault: true,
            isEnabled: true,
            sortOrder: 0,
            createdAt: nil,
            updatedAt: nil
        )
        return SuggestionType(model: model)
    }
}

// MARK: - Persistent Model

@Model
final class SuggestionTypePersistentModel: UpdatablePersistentModel {
    var pk: String?
    var ik: String?
    var uuid: String = ""
    var typeKey: String = ""
    var name: String = ""
    var descriptionText: String = ""
    var category: String = ""
    var systemPrompt: String = ""
    var icon: String = ""
    var isDefault: Bool = false
    var isEnabled: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date?
    var updatedAt: Date?

    // Legacy properties for migration compatibility
    var suggestionType: String {
        get { typeKey }
        set { typeKey = newValue }
    }
    var suggestionName: String {
        get { name }
        set { name = newValue }
    }
    var suggestionTypeCategory: String {
        get { category }
        set { category = newValue }
    }

    init() {}

    func updateProperties(from suggestion: SuggestionTypePersistentModel) {
        self.uuid = suggestion.uuid
        self.typeKey = suggestion.typeKey
        self.name = suggestion.name
        self.descriptionText = suggestion.descriptionText
        self.category = suggestion.category
        self.systemPrompt = suggestion.systemPrompt
        self.icon = suggestion.icon
        self.isDefault = suggestion.isDefault
        self.isEnabled = suggestion.isEnabled
        self.sortOrder = suggestion.sortOrder
        self.createdAt = suggestion.createdAt
        self.updatedAt = suggestion.updatedAt
    }
}
