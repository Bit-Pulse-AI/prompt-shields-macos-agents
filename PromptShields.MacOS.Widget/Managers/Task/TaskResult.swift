import Foundation

public struct TaskResult: Sendable {
    public let id: UUID
    public let order: Int
    public let result: Result<any SafePersistentModel, Error>
    public let executionTime: TimeInterval
    public let timestamp: Date
    
    public var isSuccess: Bool {
        switch result {
        case .success: return true
        case .failure: return false
        }
    }
    
    public var value: (any SafePersistentModel)? {
        switch result {
        case .success(let value): return value
        case .failure: return nil
        }
    }
    
    public var error: Error? {
        switch result {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}
