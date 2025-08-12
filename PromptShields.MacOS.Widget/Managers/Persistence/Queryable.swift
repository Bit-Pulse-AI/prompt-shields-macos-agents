import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Mapping Protocol
/// Protocol that defines mapping capabilities for queryable properties
protocol QueryableMapping<SourceType, TargetType> {
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
actor QueryableActor<D: Domain, M: QueryableMapping> where M.SourceType == D, M.TargetType == D {
    private let persistenceManager: PersistenceManager
    private let predicate: Predicate<D.P>?
    private let sortDescriptors: [SortDescriptor<D.P>]
    private let mapping: M.Type
    private let limit: Int?
    
    private var results: [D] = []
    private var isLoading = false
    private var error: Error?
    
    // Use a simple callback approach
    private var onUpdate: (@Sendable ([D], Bool, Error?) -> Void)?
    
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
        
        Task {
            await setupObservers()
        }
    }
    
    private func setupObservers() {
        // Store the observer task for proper cleanup
        observerTask = Task { [weak self] in
            // Observe model context changes
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                // Check if task is cancelled before proceeding
                try? Task.checkCancellation()
                await self?.loadData()
            }
        }
        
        // Store the initial load task for proper cleanup
        initialLoadTask = Task { [weak self] in
            await self?.loadData()
        }
    }
    
    private func loadData() async {
        // Check if task is cancelled before proceeding
        try? Task.checkCancellation()
        
        isLoading = true
        error = nil
        
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
            onUpdate?(results, isLoading, error)
        } catch {
            self.error = error
            results = []
            onUpdate?(results, isLoading, error)
        }
        
        isLoading = false
        onUpdate?(results, isLoading, error)
    }
    
    func setUpdateCallback(_ callback: @escaping @Sendable ([D], Bool, Error?) -> Void) {
        onUpdate = callback
        // Immediately call with current state
        callback(results, isLoading, error)
    }
    
    func refresh() async {
        await loadData()
    }
    
    // Modern property access with async getters
    var currentResults: [D] { results }
    var loadingState: Bool { isLoading }
    var currentError: Error? { error }
    
    deinit {
        print("actor removed")
        // Cancel all tasks to prevent retain cycles
        observerTask?.cancel()
        initialLoadTask?.cancel()
    }
}

// MARK: - Queryable Property Wrapper
/// A property wrapper similar to @Query but usable outside views with protocol-based mapping and automatic updates
@propertyWrapper
@MainActor
struct Queryable<D: Domain, M: QueryableMapping> where M.SourceType == D, M.TargetType == D {
    private let actor: QueryableActor<D, M>
    private let state: QueryableState<D>
    
    init(
        predicate: Predicate<D.P>? = nil,
        sortDescriptors: [SortDescriptor<D.P>] = [],
        limit: Int?,
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
        self.state = QueryableState<D>()
        setUpdateCallback()
    }
    
    func setUpdateCallback() {
        // Set up the update callback
        Task {
            await actor.setUpdateCallback { [state] results, isLoading, error in
                Task { @MainActor in
                    state.wrappedValue = results
                    state.isLoading = isLoading
                    state.error = error
                }
            }
        }
    }
    
    var wrappedValue: [D] {
        get { state.wrappedValue }
        set { state.wrappedValue = newValue }
    }
    
    /// Manually refresh the data
    func refresh() async {
        await actor.refresh()
    }
    
    /// Get the underlying actor for more control
    var queryableActor: QueryableActor<D, M> { actor }
}

// MARK: - Observable Queryable for SwiftUI
/// Observable version of Queryable for use in SwiftUI views with automatic updates
@MainActor
final class ObservableQueryable<D: Domain, M: QueryableMapping>: ObservableObject where M.SourceType == D, M.TargetType == D {
    private let actor: QueryableActor<D, M>
    private var setupTask: Task<Void, Never>?
    
    @Published private(set) var wrappedValue: [D] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
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
        setupTask = Task {
            await actor.setUpdateCallback { [weak self] results, isLoading, error in
                Task { @MainActor in
                    self?.wrappedValue = results
                    self?.isLoading = isLoading
                    self?.error = error
                }
            }
        }
    }
    
    func refresh() async {
        await actor.refresh()
    }
    
    deinit {
        print("ObservableQueryable deallocated")
        setupTask?.cancel()
    }
}

// MARK: - Convenience Extensions with Modern Syntax

extension Queryable where M == DefaultMapping<D> {
    /// Convenience initializer for simple queries without custom mapping
    init(
        predicate: Predicate<D.P>? = nil,
        sortDescriptors: [SortDescriptor<D.P>] = [],
        limit: Int? = nil,
        persistenceManager: PersistenceManager = PersistenceManagerImpl.shared
    ) {
        self.init(
            predicate: predicate,
            sortDescriptors: sortDescriptors,
            limit: limit,
            persistenceManager: persistenceManager,
            mapping: DefaultMapping<D>.self
        )
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

// MARK: - Thread-Safe Access Extensions with Modern Async/Await

extension Queryable {
    /// Thread-safe access to current results
    func getResults() async -> [D] {
        await actor.currentResults
    }
    
    /// Thread-safe access to loading state
    func getLoadingState() async -> Bool {
        await actor.loadingState
    }
    
    /// Thread-safe access to error state
    func getError() async -> Error? {
        await actor.currentError
    }
}
