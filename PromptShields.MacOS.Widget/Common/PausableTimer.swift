actor PausableTimer {
    private var interval: Duration
    private var isPaused = false
    private var task: Task<Void, Never>?
    
    init(interval: Duration) {
        self.interval = interval
    }
    
    func start(action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                if isPaused {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s check
                    continue
                }
                await action()
                try? await Task.sleep(for: interval)
            }
        }
    }
    
    func pause() {
        isPaused = true
    }
    
    func resume() {
        isPaused = false
    }
    
    func stop() {
        task?.cancel()
        task = nil
    }
}
