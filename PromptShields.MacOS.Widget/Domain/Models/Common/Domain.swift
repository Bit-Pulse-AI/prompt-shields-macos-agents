import Foundation
import SwiftData

// MARK: - Type Aliases
typealias UID = String

extension [UID] {
    var encrypt: [String] {
        compactMap { $0.encrypt }
    }
    var decrypt: [String] {
        compactMap { $0.decrypt }
    }
}

protocol APIResponse: SendableDecodable {
    associatedtype D: Domain
    func toDomain() -> D
}

protocol Domain: Sendable, Equatable, Identifiable, Hashable {
    associatedtype M: Model
    associatedtype P: UpdatablePersistentModel
    associatedtype R: SendableDecodable
    
    var identifier: ModelIdentifier? { get }
    var model: M { get }
    var id: String { get }
    
    init(model: M)
    init(model: M, identifier: ModelIdentifier?)
    
    // Mapping methods for API and persistence
    func toPersistentModel(context: ModelContext?) -> P
    static func fromPersistentModel(_ persistent: P) -> Self
}

extension Domain {
    func saveLocally() async throws {
        let persistenceManager = PersistenceManagerImpl.shared
        try await persistenceManager.update(domain: self)
    }
}

struct ModelIdentifier: Sendable, Equatable, Identifiable, Hashable, Codable {
    var id: String {
        "identifier_\(String(describing: persistentIdentifier.entityName))_\(String(describing: persistentIdentifier.hashValue))"
    }
    let persistentIdentifier: PersistentIdentifier
    
    func domain<D: Domain>() async throws -> D {
        let persistenceManager = PersistenceManagerImpl.shared
        return try await persistenceManager.fetchItem(persistentIdentifier: persistentIdentifier)
    }
}

enum DomainError: Error {
    case faultyOrMissingIdentifier
    case mappingFailed
    case apiMappingFailed
}

extension Domain {
    var id: String {
        let backupId = identifier?.id ?? UUID().uuidString
        return (try? model.uuid.sha512) ?? backupId
    }
}

typealias SendableEquatable = Sendable & Equatable

protocol Model: SendableEquatable, Hashable {
    var uuid: UID { get }
}
