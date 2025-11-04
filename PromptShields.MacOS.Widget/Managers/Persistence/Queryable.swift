import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Mapping Protocol
/// Protocol that defines mapping capabilities for queryable properties
protocol QueryableMapping<SourceType, TargetType>: Sendable {
    associatedtype SourceType
    associatedtype TargetType

    /// Maps from source type to target type
    static func map(_ source: SourceType) -> TargetType?

    /// Checks if the source type can be mapped to target type
    static func canMap(_ source: SourceType) -> Bool
}

// MARK: - Default Mapping Implementation
/// Default mapping that returns nil if types don't match
struct DefaultMapping<T>: QueryableMapping {
    typealias SourceType = T
    typealias TargetType = T

    static func map(_ source: T) -> T? {
        source
    }

    static func canMap(_ source: T) -> Bool {
        true
    }
}

// MARK: - Observable Queryable (merged)
/// Single component that performs background data operations and publishes updates on main thread
@MainActor
final class ObservableQueryable<D: Domain, M: QueryableMapping>: ObservableObject where M.SourceType == D, M.TargetType == D {
    // Query configuration
    private let predicate: Predicate<D.P>?
    private let sortDescriptors: [SortDescriptor<D.P>]
    private let limit: Int?
    private let persistenceManager: PersistenceManager
    private let mapping: M.Type

    // Tasks
    private var observerTask: Task<Void, Never>?
    private var initialLoadTask: Task<Void, Never>?

    // Published data consumed by SwiftUI
    @Published private(set) var wrappedValue: [D] = []

    init(
        predicate: Predicate<D.P>? = nil,
        sortDescriptors: [SortDescriptor<D.P>] = [],
        limit: Int? = nil,
        persistenceManager: PersistenceManager = PersistenceManagerImpl.shared,
        mapping: M.Type
    ) {
        self.predicate = predicate
        self.sortDescriptors = sortDescriptors
        self.limit = limit
        self.persistenceManager = persistenceManager
        self.mapping = mapping

//        setupObservers()
    }

    private func setupObservers() {
        // Observe model context saves off the main actor and reload
//        observerTask = Task { @MainActor [weak self] in
//            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
//                try? Task.checkCancellation()
//                await self?.loadData()
//            }
//        }

        // Initial load
//        initialLoadTask = Task { [weak self] in
//            await self?.loadData()
//        }
    }

    @MainActor
    private func loadData() async {
//        let results: [D]
//        do {
//            let raw: [D] = try await self.persistenceManager.query(
//                predicate: self.predicate,
//                sortDescriptors: self.sortDescriptors,
//                limit: limit
//            )
//            results = raw.compactMap { domain in
//                M.canMap(domain) ? M.map(domain) : nil
//            }
//        } catch {
//            results = []
//        }
//        self.wrappedValue = results
    }

//    deinit {
//        observerTask?.cancel()
//        initialLoadTask?.cancel()
//    }
}

extension ObservableQueryable where M == DefaultMapping<D> {
    /// Convenience initializer for simple queries without custom mapping
    convenience init(
        predicate: Predicate<D.P>? = nil,
        sortDescriptors: [SortDescriptor<D.P>] = [],
        persistenceManager: PersistenceManager = PersistenceManagerImpl.shared
    ) {
        self.init(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            persistenceManager: persistenceManager,
            mapping: DefaultMapping<D>.self
        )
    }
}
