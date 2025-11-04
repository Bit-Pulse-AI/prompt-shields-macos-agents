import SwiftData

extension PersistentModel {
    func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [:]
        let mirror = Mirror(reflecting: self)

        for child in mirror.children {
            if let propertyName = child.label {
                if child.value is String {
                }
                dictionary[propertyName] = child.value
            }
        }
        return dictionary
    }
}
