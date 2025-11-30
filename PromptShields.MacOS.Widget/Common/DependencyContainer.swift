import Foundation
import os

// MARK: - Dependency Container Protocol

/// Thread-safe dependency injection container following SOLID principles
/// - Single Responsibility: Only manages dependency registration and resolution
/// - Open/Closed: New dependencies added via registration, not code modification
/// - Dependency Inversion: Depends on abstractions (protocols), not concretions
protocol DependencyContainerProtocol: Sendable {
    func register<T>(_ type: T.Type, factory: @escaping @Sendable () -> T)
    func resolve<T>(_ type: T.Type) -> T?
}

// MARK: - Dependency Container Implementation

/// Production-ready dependency container with thread-safe access
final class DependencyContainer: DependencyContainerProtocol, @unchecked Sendable {
    
    // MARK: - Singleton
    
    static let shared = DependencyContainer()
    
    // MARK: - Private Properties
    
    private let lock = NSRecursiveLock()
    private var factories: [ObjectIdentifier: Any] = [:]
    private var singletons: [ObjectIdentifier: Any] = [:]
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
        category: "DependencyContainer"
    )
    
    // MARK: - Initialization
    
    private init() {
        registerDefaults()
    }
    
    // MARK: - Registration
    
    /// Registers a factory for creating instances of the specified type
    /// - Parameters:
    ///   - type: The protocol or type to register
    ///   - factory: A closure that creates an instance of the type
    func register<T>(_ type: T.Type, factory: @escaping @Sendable () -> T) {
        lock.lock()
        defer { lock.unlock() }
        
        let key = ObjectIdentifier(type)
        factories[key] = factory
        logger.debug("Registered dependency: \(String(describing: type))")
    }
    
    /// Registers a singleton instance for the specified type
    /// - Parameters:
    ///   - type: The protocol or type to register
    ///   - instance: The singleton instance
    func registerSingleton<T>(_ type: T.Type, instance: T) {
        lock.lock()
        defer { lock.unlock() }
        
        let key = ObjectIdentifier(type)
        singletons[key] = instance
        logger.debug("Registered singleton: \(String(describing: type))")
    }
    
    // MARK: - Resolution
    
    /// Resolves an instance of the specified type
    /// - Parameter type: The protocol or type to resolve
    /// - Returns: An instance of the type, or nil if not registered
    func resolve<T>(_ type: T.Type) -> T? {
        lock.lock()
        defer { lock.unlock() }
        
        let key = ObjectIdentifier(type)
        
        // Check singletons first
        if let singleton = singletons[key] as? T {
            return singleton
        }
        
        // Then check factories
        if let factory = factories[key] as? @Sendable () -> T {
            return factory()
        }
        
        logger.error("Failed to resolve dependency: \(String(describing: type))")
        return nil
    }
    
    /// Resolves an instance of the specified type, throwing if not found
    /// - Parameter type: The protocol or type to resolve
    /// - Returns: An instance of the type
    /// - Throws: DependencyError.notRegistered if the type is not registered
    func resolveOrThrow<T>(_ type: T.Type) throws -> T {
        guard let instance = resolve(type) else {
            throw DependencyError.notRegistered(String(describing: type))
        }
        return instance
    }
    
    // MARK: - Default Registrations
    
    private func registerDefaults() {
        // Singletons - shared instances
        registerSingleton(PersistenceManager.self, instance: PersistenceManagerImpl.shared)
        registerSingleton(KeychainManager.self, instance: KeychainManagerImpl.shared)
        registerSingleton(NetworkManager.self, instance: NetworkManagerImpl.shared)
        
        // Network Services - new instance per injection
        register(LLMNetworkService.self) { LLMNetworkServiceImpl() }
        register(SuggestionNetworkService.self) { SuggestionNetworkServiceImpl() }
        register(ProfileNetworkService.self) { ProfileNetworkServiceImpl() }
        register(UserNetworkService.self) { UserNetworkServiceImpl() }
        register(OrganisationNetworkService.self) { OrganisationNetworkServiceImpl() }
        register(SubscriptionNetworkService.self) { SubscriptionNetworkServiceImpl() }
        register(TeamNetworkService.self) { TeamNetworkServiceImpl() }
        
        // Domain Services - new instance per injection
        register(UserDomainService.self) { UserDomainServiceImpl() }
        register(ProfileDomainService.self) { ProfileDomainServiceImpl() }
        register(OrganisationDomainService.self) { OrganisationDomainServiceImpl() }
        register(SubscriptionDomainService.self) { SubscriptionDomainServiceImpl() }
        register(TeamDomainService.self) { TeamDomainServiceImpl() }
        register(UserPreferencesDomainService.self) { UserPreferencesDomainServiceImpl() }
        register(SuggestionDomainService.self) { SuggestionDomainServiceImpl() }
        register(LLMDomainService.self) { LLMDomainServiceImpl() }
    }
    
    // MARK: - Testing Support
    
    /// Clears all registrations (for testing purposes only)
    #if DEBUG
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        
        factories.removeAll()
        singletons.removeAll()
        registerDefaults()
    }
    
    /// Overrides a registration for testing
    func override<T>(_ type: T.Type, with instance: T) {
        lock.lock()
        defer { lock.unlock() }
        
        let key = ObjectIdentifier(type)
        singletons[key] = instance
    }
    #endif
}

// MARK: - Dependency Errors

enum DependencyError: Error, LocalizedError {
    case notRegistered(String)
    
    var errorDescription: String? {
        switch self {
        case .notRegistered(let typeName):
            return "Dependency not registered: \(typeName)"
        }
    }
}

