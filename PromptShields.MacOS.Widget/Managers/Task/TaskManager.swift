import Foundation
import SwiftData

// MARK: - Demo and Testing

/// Demo function showing how to use the TaskManager
// public func demonstrateTaskManager() async {

//
//    let (_, stream1) = taskManager.addTask {
//        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
//        return "Task 1 completed"
//    }
//
//    let (_, stream2) = await taskManager.addTask {
//        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
//        return "Task 2 completed"
//    }
//
//    // Example 2: Processing results in order
//    Task {
//        for await result in stream1 {
//            print("✅ Task \(result.order): \(result.value ?? "Error") (took \(String(format: "%.2f", result.executionTime))s)")
//        }
//    }
//
//    Task {
//        for await result in stream2 {
//            print("✅ Task \(result.order): \(result.value ?? "Error") (took \(String(format: "%.2f", result.executionTime))s)")
//        }
//    }
//
//    // Example 3: Batch processing
//    print("\n🔄 Processing batch of tasks...")
//
//    let numbers = Array(1...5)
//    let batchStream = taskManager.processBatch(numbers) { number in
//        try await Task.sleep(nanoseconds: UInt64(number * 200_000_000)) // Variable delay
//        return number * number
//    }
//
//    Task {
//        for await result in batchStream {
//            if let value = result.value {
//                print("🔢 Batch Task \(result.order): \(value) (took \(String(format: "%.2f", result.executionTime))s)")
//            } else if let error = result.error {
//                print("❌ Batch Task \(result.order) failed: \(error)")
//            }
//        }
//    }
//
//    // Show stats periodically
//    Task {
//        for _ in 0..<10 {
//            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
//            let stats = await taskManager.getStats()
//            print("📊 Stats - Pending: \(stats.pendingCount), Running: \(stats.runningCount), Completed: \(stats.completedCount)")
//        }
//    }
//
//    // Wait for all tasks to complete
//    await taskManager.waitForAllTasks()
//    print("\n🏁 All tasks completed!")
//
//    let finalStats = await taskManager.getStats()
//    print("📊 Final Stats - Total tasks processed: \(finalStats.totalTasks)")
// }

public actor TaskManager {
    // MARK: - Private Properties
    
    private let taskActor: TaskManagerActor
    private var resultStreams: [UUID: Any] = [:]
    
    // MARK: - Initialization
    
    public init(maxConcurrentTasks: Int = 10) {
        self.taskActor = TaskManagerActor(maxConcurrentTasks: maxConcurrentTasks)
    }
    
    // MARK: - Public Methods
    
    /// Add a task to the manager and get an AsyncStream of results
    /// - Parameter task: The async task to execute
    /// - Returns: A tuple containing the task ID and an AsyncStream of results ordered by addition
    public func addTask(
        _ task: @escaping @Sendable () async throws -> any SafePersistentModel
    ) -> (id: UUID, results: AsyncStream<TaskResult>) {
        let (stream, continuation) = AsyncStream.makeStream(of: TaskResult.self)
        
        Task {
            let taskId = await taskActor.addTask {
                try await task()
            }
            
            // Store the continuation for this task
            resultStreams[taskId] = continuation
            
            // Listen for results from this specific task
            await listenForTaskResult(taskId: taskId, continuation: continuation)
        }
        
        return (UUID(), stream) // Return a placeholder ID for now, actual ID will be handled internally
    }
    
    /// Add multiple tasks and get a combined ordered stream
    /// - Parameter tasks: Array of async tasks to execute
    /// - Returns: AsyncStream of all task results in order of addition
    public func addTasks(
        _ tasks: [@Sendable () async throws -> any PersistentModel]
    ) -> AsyncStream<TaskResult> {
        let (stream, continuation) = AsyncStream.makeStream(of: TaskResult.self)
        
        Task {
            var taskIds: [UUID] = []
            
            // Add all tasks
            for task in tasks {
                let taskId = await taskActor.addTask {
                    try await task()
                }
                taskIds.append(taskId)
            }
            
            // Listen for all results in order
            await listenForOrderedResults(taskIds: taskIds, continuation: continuation)
        }
        
        return stream
    }
    
    /// Get current statistics about the task manager
    /// - Returns: TaskManagerStats with current state information
    public func getStats() async -> TaskManagerStats {
        return await taskActor.getStats()
    }
    
    /// Cancel all pending tasks
    public func cancelAllTasks() async {
        await taskActor.cancelAllTasks()
    }
    
    /// Wait for all current tasks to complete
    public func waitForAllTasks() async {
        await taskActor.waitForAllTasks()
    }
    
    // MARK: - Private Methods
    
    private func listenForTaskResult(
        taskId: UUID,
        continuation: AsyncStream<TaskResult>.Continuation
    ) async {
        // This would be implemented to listen for specific task completion
        // For now, we'll integrate this with the actor's result stream
    }
    
    private func listenForOrderedResults(
        taskIds: [UUID],
        continuation: AsyncStream<TaskResult>.Continuation
    ) async {
        // Implementation for listening to multiple tasks in order
    }
}
