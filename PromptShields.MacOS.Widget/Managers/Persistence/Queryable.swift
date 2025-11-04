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

// MARK: - Queryable State Manager
/// Thread-safe state manager for queryable data
@MainActor
final class QueryableState<D: Domain> {
    var wrappedValue: [D] = []
    var isLoading = false
    var error: Error?
}

// MARK: - Queryable Actor
/// Thread-safe actor that manages queryable data with automatic updates
@MainActor
final class QueryableActor<D: Domain, M: QueryableMapping> where M.SourceType == D, M.TargetType == D {
    private let persistenceManager: PersistenceManager
    private let predicate: Predicate<D.P>?
    private let sortDescriptors: [SortDescriptor<D.P>]
    private let mapping: M.Type
    private let limit: Int?

    private var results: [D] = []

    // Use a simple callback approach
    private var onUpdate: (@Sendable ([D]) -> Void)?

    // Store task references for proper cleanup
    private var observerTask: Task<Void, Never>?
    private var initialLoadTask: Task<Void, Never>?

    init(
        predicate: Predicate<D.P>? = nil,
        sortDescriptors: [SortDescriptor<D.P>] = [],
        limit: Int? = nil,
        persistenceManager: PersistenceManager = PersistenceManagerImpl.shared,
        mapping: M.Type
    ) {
        self.predicate = predicate
        self.sortDescriptors = sortDescriptors
        self.persistenceManager = persistenceManager
        self.mapping = mapping
        self.limit = limit
        self.setupObservers()
    }

    private func setupObservers() {
        // Store the observer task for proper cleanup
        observerTask = Task { @MainActor [weak self] in
            // Observe model context changes
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                // Check if task is cancelled before proceeding
                try? Task.checkCancellation()
                await self?.loadData()
            }
        }

        // Store the initial load task for proper cleanup
        initialLoadTask = Task { @MainActor [weak self] in
            await self?.loadData()
        }
    }

    private func loadData() async {
        // Check if task is cancelled before proceeding
        try? Task.checkCancellation()

        do {
            let rawResult: [D] = try await persistenceManager.query(
                predicate: predicate,
                sortDescriptors: sortDescriptors,
                limit: limit
            )

            // Apply mapping using modern functional programming
            results = rawResult.compactMap { domain in
                M.canMap(domain) ? M.map(domain) : nil
            }

            // Notify callback
            await MainActor.run {
                onUpdate?(results)
            }
        } catch {
            results = []
            await MainActor.run {
                onUpdate?(results)
            }
        }

        await MainActor.run {
            onUpdate?(results)
        }
    }

    func setUpdateCallback(_ callback: @escaping @Sendable ([D]) -> Void) {
        onUpdate = callback
        // Immediately call with current state on main actor
        Task { @MainActor in
            callback(results)
        }
    }

    deinit {
        observerTask?.cancel()
        initialLoadTask?.cancel()
    }
}

// MARK: - Observable Queryable for SwiftUI
/// Observable version of Queryable for use in SwiftUI views with automatic updates
@MainActor
final class ObservableQueryable<D: Domain, M: QueryableMapping>: ObservableObject where M.SourceType == D, M.TargetType == D {
    private let actor: QueryableActor<D, M>
    private var setupTask: Task<Void, Never>?

    @Published private(set) var wrappedValue: [D] = []

    init(
        predicate: Predicate<D.P>? = nil,
        sortDescriptors: [SortDescriptor<D.P>] = [],
        limit: Int? = nil,
        persistenceManager: PersistenceManager = PersistenceManagerImpl.shared,
        mapping: M.Type
    ) {
        self.actor = QueryableActor(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit,
            persistenceManager: persistenceManager,
            mapping: mapping
        )

        setupBindings()
    }

    private func setupBindings() {
        actor.setUpdateCallback { [weak self] results in
            Task {
                await MainActor.run { [weak self] in
                    self?.wrappedValue = results
                }
            }
        }
    }

    deinit {
        print("ObservableQueryable deallocated")
        setupTask?.cancel()
    }
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
