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
    private var pendingLoadTask: Task<Void, Never>?

    // State management
    private var isLoading: Bool = false
    private var isObserving: Bool = false
    private var needsReloadAfterCurrentLoad: Bool = false

    // Debounce state to prevent rapid reloads from notification storms
    private var lastLoadTime: Date = .distantPast
    private let minimumLoadInterval: TimeInterval = 0.2

    // Published data consumed by SwiftUI
    @Published private(set) var wrappedValue: [D] = []

    /// Indicates if initial load has completed
    @Published private(set) var hasLoaded: Bool = false

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

        // Start observing immediately on next run loop
        Task { @MainActor [weak self] in
            self?.startObservingIfNeeded()
        }
    }

    /// Manually trigger a refresh. Safe to call multiple times.
    /// This will wait for any in-progress load to complete before loading again.
    func refresh() async {
        if isLoading {
            // Mark that we need another load after current one finishes
            needsReloadAfterCurrentLoad = true
            // Wait for current load to finish
            while isLoading {
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
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
            // Perform initial load immediately
            await self?.performLoad()

            // Then listen for changes
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                guard !Task.isCancelled else { break }
                guard let self = self else { continue }

                // Debounce rapid notifications
                let now = Date()
                if now.timeIntervalSince(self.lastLoadTime) < self.minimumLoadInterval {
                    // Schedule a delayed load instead of skipping entirely
                    self.scheduleDelayedLoad()
                    continue
                }

                await self.performLoad()
            }
        }
    }

    /// Schedules a load after a short delay, coalescing multiple requests
    private func scheduleDelayedLoad() {
        pendingLoadTask?.cancel()
        pendingLoadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.performLoad()
        }
    }

    private func performLoad() async {
        // If already loading, mark that we need to reload after
        if isLoading {
            needsReloadAfterCurrentLoad = true
            return
        }

        isLoading = true
        lastLoadTime = Date()
        needsReloadAfterCurrentLoad = false

        defer {
            isLoading = false
            hasLoaded = true

            // If a reload was requested while we were loading, do it now
            if needsReloadAfterCurrentLoad {
                needsReloadAfterCurrentLoad = false
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(50))
                    await self?.performLoad()
                }
            }
        }

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
        pendingLoadTask?.cancel()
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
