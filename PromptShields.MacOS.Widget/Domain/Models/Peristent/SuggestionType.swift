import Foundation
import SwiftData

/// Represents a user-customizable suggestion type
/// Suggestion types define how user text is processed by the LLM
/// The promptTemplate field contains instructions that wrap around the user's text
/// using {{TEXT}} as a placeholder for where the user's selected text will be injected
struct SuggestionType: Domain {
    typealias M = SuggestionTypeModel
    typealias P = SuggestionTypePersistentModel

    /// The placeholder used in prompt templates to indicate where user text should be injected
    static let textPlaceholder = "{{TEXT}}"

    struct SuggestionTypeModel: Model {
        var uuid: UID
        let typeKey: String
        let name: String
        var description: String
        let category: String
        var promptTemplate: String
        let suggestionTypeGroupId: String
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

    // MARK: - Mapping Methods

    func toPersistentModel(context: ModelContext?) -> SuggestionTypePersistentModel {
        let persistent = SuggestionTypePersistentModel()
        persistent.uuid = model.uuid.encrypt
        persistent.typeKey = model.typeKey.encrypt
        persistent.name = model.name.encrypt
        persistent.suggestionTypeGroupId = model.suggestionTypeGroupId.encrypt
        persistent.descriptionText = model.description.encrypt
        persistent.category = model.category.encrypt
        persistent.promptTemplate = model.promptTemplate.encrypt
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
            promptTemplate: persistent.promptTemplate.decrypt,
            suggestionTypeGroupId: persistent.suggestionTypeGroupId.decrypt,
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
    let promptTemplate: String
    let suggestionTypeGroupId: String
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
        case suggestionTypeGroupId = "suggestion_type_group_id"
        case category
        case promptTemplate = "prompt_template"
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
            promptTemplate: promptTemplate,
            suggestionTypeGroupId: suggestionTypeGroupId,
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
    var promptTemplate: String = ""
    var suggestionTypeGroupId: String = ""
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
        self.suggestionTypeGroupId = suggestion.suggestionTypeGroupId
        self.promptTemplate = suggestion.promptTemplate
        self.icon = suggestion.icon
        self.isDefault = suggestion.isDefault
        self.isEnabled = suggestion.isEnabled
        self.sortOrder = suggestion.sortOrder
        self.createdAt = suggestion.createdAt
        self.updatedAt = suggestion.updatedAt
    }
}
