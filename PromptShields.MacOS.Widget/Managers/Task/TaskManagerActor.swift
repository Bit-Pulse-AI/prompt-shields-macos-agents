import Foundation
import SwiftData

public typealias SafePersistentModel = PersistentModel & Sendable

/// Internal actor that handles the actual task execution
public actor TaskManagerActor {
    // MARK: - Properties
    
    private let maxConcurrentTasks: Int
    private var currentTasks: [UUID: Task<Sendable, Error>] = [:]
    private var pendingTasks: [TaskItem] = []
    private var completedTasks: [UUID: TaskResult] = [:]
    private var taskCounter: Int = 0
    private var isProcessing = false
    
    // Results stream
    private let resultsStreamContinuation: AsyncStream<(UUID, TaskResult)>.Continuation
    private let resultsStream: AsyncStream<(UUID, TaskResult)>
    
    // MARK: - Initialization
    
    init(maxConcurrentTasks: Int) {
        self.maxConcurrentTasks = maxConcurrentTasks
        
        let (stream, continuation) = AsyncStream.makeStream(of: (UUID, TaskResult).self)
        self.resultsStream = stream
        self.resultsStreamContinuation = continuation
        
        // Start processing tasks
        Task { await startProcessing() }
    }
    
    deinit {
        resultsStreamContinuation.finish()
    }
    
    // MARK: - Public Methods
    
    func addTask(_ task: @escaping @Sendable () async throws -> any PersistentModel) -> UUID {
        taskCounter += 1
        let taskItem = TaskItem(order: taskCounter, task: task)
        pendingTasks.append(taskItem)
        
        // Start processing if not already processing
        if !isProcessing {
            Task { await processPendingTasks() }
        }
        
        return taskItem.id
    }
    
    func getStats() -> TaskManagerStats {
        return TaskManagerStats(
            pendingCount: pendingTasks.count,
            runningCount: currentTasks.count,
            completedCount: completedTasks.count,
            maxConcurrent: maxConcurrentTasks
        )
    }
    
    func cancelAllTasks() {
        // Cancel running tasks
        for (_, task) in currentTasks {
            task.cancel()
        }
        currentTasks.removeAll()
        
        // Clear pending tasks
        pendingTasks.removeAll()
    }
    
    func waitForAllTasks() async {
        // Wait for all running tasks to complete
        await withTaskGroup(of: Void.self) { group in
            for (_, task) in currentTasks {
                group.addTask {
                    _ = try? await task.value
                }
            }
        }
        
        // Process any remaining pending tasks
        await processPendingTasks()
    }
    
    // MARK: - Private Methods
    
    private func startProcessing() async {
        isProcessing = true
        await processPendingTasks()
    }
    
    private func processPendingTasks() async {
        while !pendingTasks.isEmpty && currentTasks.count < maxConcurrentTasks {
            let taskItem = pendingTasks.removeFirst()
            
            let task = Task<Sendable, Error> {
                let startTime = Date()
                do {
                    let result = try await taskItem.task()
                    let endTime = Date()
                    let executionTime = endTime.timeIntervalSince(startTime)
                    
                    let taskResult = TaskResult(
                        id: taskItem.id,
                        order: taskItem.order,
                        result: .success(result),
                        executionTime: executionTime,
                        timestamp: endTime
                    )
                    
                    await self.handleTaskCompletion(taskId: taskItem.id, result: taskResult)
                    return result
                } catch {
                    let endTime = Date()
                    let executionTime = endTime.timeIntervalSince(startTime)
                    
                    let taskResult = TaskResult(
                        id: taskItem.id,
                        order: taskItem.order,
                        result: .failure(error),
                        executionTime: executionTime,
                        timestamp: endTime
                    )
                    
                    await self.handleTaskCompletion(taskId: taskItem.id, result: taskResult)
                    throw error
                }
            }
            
            currentTasks[taskItem.id] = task
        }
    }
    
    private func handleTaskCompletion(taskId: UUID, result: TaskResult) async {
        // Remove from current tasks
        currentTasks.removeValue(forKey: taskId)
        
        // Store completed result
        completedTasks[taskId] = result
        
        // Send result through stream
        resultsStreamContinuation.yield((taskId, result))
        
        // Process more pending tasks if available
        if !pendingTasks.isEmpty {
            await processPendingTasks()
        }
    }
}

// MARK: - Statistics

/// Statistics about the task manager's current state
public struct TaskManagerStats: Sendable {
    public let pendingCount: Int
    public let runningCount: Int
    public let completedCount: Int
    public let maxConcurrent: Int
    
    public var totalTasks: Int {
        pendingCount + runningCount + completedCount
    }
}

// MARK: - Usage Examples and Extensions

extension TaskManager {
    public func processBatch<Input: SafePersistentModel, Output: SafePersistentModel>(
        _ items: [Input],
        transform: @escaping @Sendable (Input) async throws -> Output
    ) -> AsyncStream<TaskResult> {
        let tasks = items.map { item in
            { @Sendable in
                try await transform(item)
            }
        }
        
        return addTasks(tasks)
    }
}
