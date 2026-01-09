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
/// All SwiftData access is properly isolated to the PersistenceManager actor
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

    // Debounce state to prevent rapid reloads from notification storms
    private var lastLoadTime: Date = .distantPast
    private let minimumLoadInterval: TimeInterval = 0.1

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

        // Defer observer setup to ensure @MainActor context is fully established
        // Using Task.detached with explicit @MainActor ensures proper actor isolation
        Task { @MainActor [weak self] in
            self?.setupObservers()
        }
    }

    private func setupObservers() {
        // Observe model context saves and reload with debouncing
        // Explicitly run on MainActor to ensure proper SwiftUI integration
        observerTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                guard !Task.isCancelled else { break }

                // Debounce rapid notifications to prevent SwiftData contention
                guard let self = self else { continue }
                let now = Date()
                guard now.timeIntervalSince(self.lastLoadTime) >= self.minimumLoadInterval else {
                    continue
                }
                self.lastLoadTime = now

                await self.loadData()
            }
        }

        // Initial load - explicitly on MainActor
        initialLoadTask = Task { @MainActor [weak self] in
            await self?.loadData()
        }
    }

    @MainActor
    private func loadData() async {
        // Ensure we're on MainActor for SwiftUI state updates
        assert(Thread.isMainThread, "loadData must run on main thread")

        let results: [D]
        do {
            // The persistence manager is an actor, so this call properly
            // hops to its executor for SwiftData access
            let raw: [D] = try await self.persistenceManager.query(
                predicate: self.predicate,
                sortDescriptors: self.sortDescriptors,
                limit: limit
            )
            // Mapping happens on MainActor with domain objects (not @Model objects)
            results = raw.compactMap { domain in
                M.canMap(domain) ? M.map(domain) : nil
            }
        } catch {
            results = []
        }
        // Update published property on MainActor
        self.wrappedValue = results
    }

    deinit {
        observerTask?.cancel()
        initialLoadTask?.cancel()
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
