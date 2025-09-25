import Foundation
import SwiftData
import SwiftUI

enum PersistenceManagerError: Error {
    case missingModelForIdentifier
    case missingIdentifier
    case missingDomainForIdentifier
    case missingDomainForUID
    case missingModel
}

/// Protocol for persistence operations to enable testing
protocol PersistenceManager: Sendable {
    func update<D: Domain>(domain: D) async throws 
    func update<D: Domain>(domains: [D]) async throws
    @discardableResult
    func syncLocalWithRemote<D: Domain>(domain: D) async throws -> D
    func syncLocalWithRemote<D: Domain>(domains: [D]) async throws
    func fetchItem<D: Domain>(persistentIdentifier: PersistentIdentifier) async throws -> D 
    func fetchItem<D: Domain>(persistentIdentifier: PersistentIdentifier?) async throws -> D 
    func fetchItem<D: Domain>(uid: UID) async throws -> D 
    func fetchItem<D: Domain>(uid: UID?) async throws -> D 
    func fetchItem<D: Domain>(filter: @Sendable @escaping (D) -> Bool) async throws -> D
    
    @discardableResult
    func insert<D: Domain>(domain: D) async throws -> D
    func insert<D: Domain>(domains: [D]) async throws
    func query<D: Domain>() async throws -> [D] where D.M == D.M
    func query<D: Domain>(predicate: Predicate<D.P>?) async throws -> [D] where D.M == D.M
    func query<D>(sortDescriptors: [SortDescriptor<D.P>]) async throws -> [D] where D: Domain, D.M == D.M
    func query<D: Domain>(predicate: Predicate<D.P>?, sortDescriptors: [SortDescriptor<D.P>]) async throws -> [D] where D.M == D.M
    
    func query<D: Domain>(limit: Int) async throws -> [D] where D.M == D.M
    func query<D: Domain>(predicate: Predicate<D.P>?, limit: Int) async throws -> [D] where D.M == D.M
    func query<D>(sortDescriptors: [SortDescriptor<D.P>], limit: Int) async throws -> [D] where D: Domain, D.M == D.M
    func query<D: Domain>(predicate: Predicate<D.P>?, sortDescriptors: [SortDescriptor<D.P>], limit: Int?) async throws -> [D] where D.M == D.M
    
    func deleteEntity<D: Domain>(entity: D.Type) async throws
    func delete<D: Domain>(domains: [D]) async throws
    func delete<D: Domain>(domain: D) async throws
    func logout() async throws
}

@ModelActor
actor PersistenceManagerImpl: PersistenceManager {
    static let entity: [any PersistentModel.Type] = [SuggestionTypePersistentModel.self,
                                                     SuggestionGroupPersistentModel.self,
                                                     SuggestionPersistentModel.self,
                                                     OrganisationPersistentModel.self,
                                                     SubscriptionPersistentModel.self,
                                                     TeamPersistentModel.self,
                                                     TenantPersistentModel.self,
                                                     UserPersistentModel.self,
                                                     UserPreferencesPersistentModel.self,
                                                     ProfilePersistentModel.self]
    static let shared: PersistenceManagerImpl = {
        let persistenceStack = PersistenceStack(modelTypes: entity,
                                                migrationPlan: ChannelsMigrationPlan.self)
        return PersistenceManagerImpl(modelContainer: persistenceStack.modelContainer)
    }()
    
    // Track memory usage and cleanup
    private var lastCleanupTime: Date = Date()
    private let cleanupInterval: TimeInterval = 300 // 5 minutes
    
    func insert<D: Domain>(domains: [D]) throws {
        domains.forEach {
            let persistent = $0.toPersistentModel(context: modelContext)
            modelContext.insert(persistent)
        }
        try modelContext.save()
    }
    
    @discardableResult
    func insert<D: Domain>(domain: D) async throws -> D {
        let persistent = domain.toPersistentModel(context: modelContext)
        modelContext.insert(persistent)
        try modelContext.save()
        return D.fromPersistentModel(persistent)
    }
    
    // MARK: - Memory Management
    
    func query<D: Domain>(predicate: Predicate<D.P>? = nil, sortDescriptors: [SortDescriptor<D.P>] = [], limit: Int?) async throws -> [D] where D.M == D.M {
        var fetchDescriptor = FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)
        if let limit {
            fetchDescriptor.fetchLimit = limit
        }
        let result = try modelContext.fetch(fetchDescriptor)
        return result.compactMap {
            let persistent = $0
            return D.fromPersistentModel(persistent)
        }
    }
    
    @discardableResult
    func syncLocalWithRemote<D: Domain>(domain: D) async throws -> D {
        do {
            let existingDomain: D = try await fetchItem(uid: domain.model.uuid)
            let syncedDomain: D = .init(model: domain.model, identifier: existingDomain.identifier)
            try await update(domain: syncedDomain)
            return syncedDomain
        } catch {
            try await insert(domain: domain)
            return domain
        }
    }
    
    func syncLocalWithRemote<D: Domain>(domains: [D]) async throws {
        let pks = domains.map { try? $0.model.uuid.sha512 }
        
        let existingItems: [D] = try await query(predicate: #Predicate<D.P> { item in
            pks.contains(item.ik)
        })
        
        let existingDict = Dictionary(grouping: existingItems, by: { $0.model.uuid })
        
        var itemsToUpdate: [D] = []
        var itemsToInsert: [D] = []
        
        for domain in domains {
            if let existingItem = existingDict[domain.model.uuid]?.first {
                let syncedDomain = D(model: domain.model, identifier: existingItem.identifier)
                itemsToUpdate.append(syncedDomain)
            } else {
                itemsToInsert.append(domain)
            }
        }
        if !itemsToUpdate.isEmpty {
            try await update(domains: itemsToUpdate)
        }
        
        if !itemsToInsert.isEmpty {
            try insert(domains: itemsToInsert)
        }
    }
    
    func fetchItem<D: Domain>(persistentIdentifier: PersistentIdentifier?) async throws -> D {
        guard let persistentIdentifier else {
            throw PersistenceManagerError.missingIdentifier
        }
        return try await fetchItem(persistentIdentifier: persistentIdentifier)
    }
    
    func fetchItem<D: Domain>(uid: UID) async throws -> D {
        try await fetchItem { $0.model.uuid == uid }
    }
    
    func fetchItem<D: Domain>(uid: UID?) async throws -> D {
        guard let uid else {
            throw PersistenceManagerError.missingDomainForUID
        }
        return try await fetchItem(uid: uid)
    }
    
    func fetchItem<D: Domain>(persistentIdentifier: PersistentIdentifier) async throws -> D {
        guard let persistent: D.P = fetchItem(persistentIdentifier: persistentIdentifier) else {
            throw PersistenceManagerError.missingModelForIdentifier
        }
        return D.fromPersistentModel(persistent)
    }
    
    func fetchItem<D: Domain>(filter: @Sendable @escaping (D) -> Bool) async throws -> D {
        // Use a different approach since we can't access uuid generically
        let items: [D] = try await self.query()
        guard let result = items.first(where: filter) else {
            throw PersistenceManagerError.missingModel
        }
        return result
    }
    
    func update<D: Domain>(domain: D) async throws {
        guard
        let persistentIdentifier = domain.identifier?.persistentIdentifier,
        let persistent = modelContext.model(for: persistentIdentifier) as? D.P else {
            throw PersistenceManagerError.missingModelForIdentifier
        }
        
        // Update the persistent model with new domain data
        let updatedPersistent = domain.toPersistentModel(context: modelContext)
        persistent.update(from: updatedPersistent)
        
        try modelContext.save()
    }
    
    func update<D: Domain>(domains: [D]) async throws {
        try domains.forEach { domain in
            guard
            let persistentIdentifier = domain.identifier?.persistentIdentifier,
            let persistent = modelContext.model(for: persistentIdentifier) as? D.P else {
                throw PersistenceManagerError.missingModelForIdentifier
            }
            
            // Update the persistent model with new domain data
            let updatedPersistent = domain.toPersistentModel(context: modelContext)
            persistent.update(from: updatedPersistent)
        }
        try modelContext.save()
    }
    
    func delete<D: Domain>(domain: D) async throws {
        guard let persistentIdentifier = domain.identifier?.persistentIdentifier, let persistent: D.P = fetchItem(persistentIdentifier: persistentIdentifier) else {
            throw PersistenceManagerError.missingModel
        }
        
        modelContext.delete(persistent)
        try modelContext.save()
    }
    func delete<D>(domains: [D]) async throws where D: Domain {
        try domains.forEach {
            guard let persistentIdentifier = $0.identifier?.persistentIdentifier, let persistent: D.P = fetchItem(persistentIdentifier: persistentIdentifier) else {
                throw PersistenceManagerError.missingModel
            }
            
            modelContext.delete(persistent)
        }
        try modelContext.save()
    }
    
    func deleteEntity<D: Domain>(entity: D.Type) async throws {
        try modelContext.delete(model: entity.P)
    }
    
    private func fetchItem<P: PersistentModel>(persistentIdentifier: PersistentIdentifier) -> P? {
        let model = modelContext.model(for: persistentIdentifier)
        return model as? P
    }
    
    func logout() async throws {
        try PersistenceManagerImpl.entity.forEach {
            try modelContext.delete(model: $0)
        }
    }
}

extension PersistenceManagerImpl {
    func query<D>(predicate: Predicate<D.P>?, sortDescriptors: [SortDescriptor<D.P>]) async throws -> [D] where D: Domain {
        try await query(predicate: predicate, sortDescriptors: sortDescriptors, limit: nil)
    }
    
    func query<D>(limit: Int) async throws -> [D] where D: Domain {
        try await query()
    }
    
    func query<D>(predicate: Predicate<D.P>?, limit: Int) async throws -> [D] where D: Domain {
        try await query(predicate: predicate, limit: nil)
    }
    
    func query<D>(sortDescriptors: [SortDescriptor<D.P>], limit: Int) async throws -> [D] where D: Domain {
        try await query(sortDescriptors: sortDescriptors, limit: nil)
    }
    
    func query<D>(predicate: Predicate<D.P>?, sortDescriptors: [SortDescriptor<D.P>], limit: Int) async throws -> [D] where D: Domain {
        try await query(predicate: predicate, sortDescriptors: sortDescriptors, limit: nil)
    }
    func query<D: Domain>() async throws -> [D] {
        try await query(predicate: nil, sortDescriptors: [], limit: nil)
    }
    
    func query<D: Domain>(sortDescriptors: [SortDescriptor<D.P>]) async throws -> [D] {
        try await query(predicate: nil, sortDescriptors: sortDescriptors, limit: nil)
    }
    
    func query<D: Domain>(predicate: Predicate<D.P>?) async throws -> [D] {
        try await query(predicate: predicate, sortDescriptors: [], limit: nil)
    }
}

// MARK: - PersistentModel Extensions
protocol UpdatablePersistentModel: PersistentModel {
    var uuid: UID { get }
    var pk: String? { get }
    var ik: String? { get }
    func updateProperties(from other: Self)
}

extension UpdatablePersistentModel {
    func update(from other: any PersistentModel) {
        if let otherSelf = other as? Self {
            updateProperties(from: otherSelf)
        }
    }
}
