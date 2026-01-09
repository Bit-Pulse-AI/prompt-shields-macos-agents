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
/// 
/// IMPORTANT: This class does NOT auto-load data on init to avoid SwiftData race conditions.
/// Use the `.onAppear` modifier to call `refresh()` when the view appears.
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
    private var loadTask: Task<Void, Never>?

    // State management to prevent concurrent loads
    private var isLoading: Bool = false
    private var isObserving: Bool = false

    // Debounce state to prevent rapid reloads from notification storms
    private var lastLoadTime: Date = .distantPast
    private let minimumLoadInterval: TimeInterval = 0.3

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

        // Auto-start observing on next run loop iteration
        // This ensures we're fully initialized before accessing SwiftData
        Task { @MainActor [weak self] in
            // Wait for any pending view setup to complete
            try? await Task.sleep(for: .milliseconds(100))
            self?.startObservingIfNeeded()
        }
    }

    /// Manually trigger a refresh. Safe to call multiple times.
    func refresh() async {
        await performLoad()
    }

    /// Start the notification observer. Called automatically, but can be called early if needed.
    func startObservingIfNeeded() {
        guard !isObserving else { return }
        isObserving = true
        setupObservers()
    }

    private func setupObservers() {
        // Cancel any existing observer
        observerTask?.cancel()

        // Start notification observer
        observerTask = Task { @MainActor [weak self] in
            // Perform initial load
            await self?.performLoad()

            // Then listen for changes
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                guard !Task.isCancelled else { break }
                guard let self = self else { continue }

                // Debounce rapid notifications
                let now = Date()
                guard now.timeIntervalSince(self.lastLoadTime) >= self.minimumLoadInterval else {
                    continue
                }

                // Small delay to let SwiftData settle after save
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { break }

                await self.performLoad()
            }
        }
    }

    private func performLoad() async {
        // Prevent concurrent loads - if already loading, skip this request
        guard !isLoading else { return }
        isLoading = true
        lastLoadTime = Date()

        defer { isLoading = false }

        do {
            // The persistence manager is an actor, so this call properly
            // hops to its executor for SwiftData access
            let raw: [D] = try await self.persistenceManager.query(
                predicate: self.predicate,
                sortDescriptors: self.sortDescriptors,
                limit: limit
            )
            // Mapping happens on MainActor with domain objects (not @Model objects)
            let results = raw.compactMap { domain in
                M.canMap(domain) ? M.map(domain) : nil
            }
            // Update published property on MainActor
            self.wrappedValue = results
        } catch {
            // On error, don't update - keep existing data
        }
    }

    deinit {
        observerTask?.cancel()
        loadTask?.cancel()
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
