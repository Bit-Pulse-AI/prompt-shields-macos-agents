import os
import Foundation

// MARK: - Inject Property Wrapper

/// Property wrapper for dependency injection using the DependencyContainer
/// Follows Dependency Inversion Principle - depends on abstractions, not concretions
@propertyWrapper
struct Inject<T>: Sendable {
    
    // MARK: - Properties
    
    private let container: DependencyContainer
    
    // MARK: - Initialization
    
    init() {
        self.container = DependencyContainer.shared
    }
    
    // MARK: - Property Wrapper
    
    var wrappedValue: T {
        guard let instance = container.resolve(T.self) else {
            // In production, we should handle this gracefully
            // Log the error and provide a meaningful crash message
            let logger = Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
                category: "Inject"
            )
            logger.critical("Failed to resolve dependency: \(String(describing: T.self))")
            
            #if DEBUG
            fatalError("Dependency not registered: \(T.self). Register it in DependencyContainer.registerDefaults()")
            #else
            // In release builds, we still need to crash but with a user-friendly message
            preconditionFailure("Application configuration error. Please reinstall the application.")
            #endif
        }
        return instance
    }
}

// MARK: - Lazy Inject Property Wrapper

/// Lazy version of Inject that defers resolution until first access
/// Useful for breaking circular dependencies
@propertyWrapper
final class LazyInject<T>: @unchecked Sendable {
    
    // MARK: - Properties
    
    private var instance: T?
    private let lock = NSLock()
    private let container: DependencyContainer
    
    // MARK: - Initialization
    
    init() {
        self.container = DependencyContainer.shared
    }
    
    // MARK: - Property Wrapper
    
    var wrappedValue: T {
        lock.lock()
        defer { lock.unlock() }
        
        if let instance = instance {
            return instance
        }
        
        guard let resolved = container.resolve(T.self) else {
            let logger = Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "ai.promptshields.widget",
                category: "LazyInject"
            )
            logger.critical("Failed to resolve dependency: \(String(describing: T.self))")
            
            #if DEBUG
            fatalError("Dependency not registered: \(T.self)")
            #else
            preconditionFailure("Application configuration error. Please reinstall the application.")
            #endif
        }
        
        instance = resolved
        return resolved
    }
}

// MARK: - Optional Inject Property Wrapper

/// Optional version of Inject that returns nil instead of crashing
/// Useful for optional features or graceful degradation
@propertyWrapper
struct OptionalInject<T>: Sendable {
    
    // MARK: - Properties
    
    private let container: DependencyContainer
    
    // MARK: - Initialization
    
    init() {
        self.container = DependencyContainer.shared
    }
    
    // MARK: - Property Wrapper
    
    var wrappedValue: T? {
        container.resolve(T.self)
    }
}
