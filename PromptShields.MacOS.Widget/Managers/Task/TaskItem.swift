import Foundation
import SwiftData

public struct TaskItem: Sendable {
    let id: UUID
    let order: Int
    let task: @Sendable () async throws -> any SafePersistentModel
    let addedAt: Date
    
    init(order: Int, task: @escaping @Sendable () async throws -> any PersistentModel) {
        self.id = UUID()
        self.order = order
        self.task = task
        self.addedAt = Date()
    }
}
