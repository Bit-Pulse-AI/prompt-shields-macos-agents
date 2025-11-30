import Foundation

// MARK: - Pausable Timer

/// A thread-safe, pausable timer using Swift concurrency
/// Optimized for performance with configurable intervals and backoff
actor PausableTimer {
    
    // MARK: - State
    
    private enum State {
        case idle
        case running
        case paused
        case stopped
    }
    
    // MARK: - Properties
    
    private var interval: Duration
    private var state: State = .idle
    private var task: Task<Void, Never>?
    
    /// Minimum interval to prevent excessive CPU usage
    private let minimumInterval: Duration = .milliseconds(100)
    
    /// Pause check interval
    private let pauseCheckInterval: Duration = .milliseconds(100)
    
    // MARK: - Initialization
    
    init(interval: Duration) {
        self.interval = max(interval, minimumInterval)
    }
    
    // MARK: - Public Methods
    
    /// Starts the timer with the specified action
    /// - Parameter action: The async action to perform on each tick
    func start(action: @escaping @Sendable () async -> Void) {
        // Cancel any existing task
        task?.cancel()
        state = .running
        
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                
                let currentState = await self.getState()
                
                switch currentState {
                case .paused:
                    // Wait briefly before checking again
                    try? await Task.sleep(for: self.pauseCheckInterval)
                    continue
                    
                case .stopped, .idle:
                    return
                    
                case .running:
                    // Execute the action
                    await action()
                    
                    // Sleep for the interval
                    let sleepInterval = await self.getInterval()
                    try? await Task.sleep(for: sleepInterval)
                }
            }
        }
    }
    
    /// Pauses the timer
    func pause() {
        guard state == .running else { return }
        state = .paused
    }
    
    /// Resumes the timer
    func resume() {
        guard state == .paused else { return }
        state = .running
    }
    
    /// Stops the timer completely
    func stop() {
        state = .stopped
        task?.cancel()
        task = nil
    }
    
    /// Updates the timer interval
    /// - Parameter newInterval: The new interval
    func updateInterval(_ newInterval: Duration) {
        interval = max(newInterval, minimumInterval)
    }
    
    /// Returns whether the timer is currently running
    var isRunning: Bool {
        state == .running
    }
    
    /// Returns whether the timer is paused
    var isPaused: Bool {
        state == .paused
    }
    
    // MARK: - Private Methods
    
    private func getState() -> State {
        state
    }
    
    private func getInterval() -> Duration {
        interval
    }
}

// MARK: - Adaptive Timer

/// A timer that adapts its interval based on activity
/// Useful for reducing CPU usage when the app is idle
actor AdaptiveTimer {
    
    // MARK: - Properties
    
    private let baseInterval: Duration
    private let maxInterval: Duration
    private let backoffMultiplier: Double
    
    private var currentInterval: Duration
    private var consecutiveIdleTicks: Int = 0
    private var timer: PausableTimer?
    
    // MARK: - Initialization
    
    /// Creates an adaptive timer
    /// - Parameters:
    ///   - baseInterval: The initial interval
    ///   - maxInterval: The maximum interval when idle
    ///   - backoffMultiplier: How much to increase interval on idle ticks
    init(
        baseInterval: Duration,
        maxInterval: Duration = .seconds(5),
        backoffMultiplier: Double = 1.5
    ) {
        self.baseInterval = baseInterval
        self.maxInterval = maxInterval
        self.backoffMultiplier = backoffMultiplier
        self.currentInterval = baseInterval
    }
    
    // MARK: - Public Methods
    
    /// Starts the adaptive timer
    /// - Parameter action: The action to perform, returns true if there was activity
    func start(action: @escaping @Sendable () async -> Bool) {
        timer = PausableTimer(interval: currentInterval)
        
        Task {
            await timer?.start { [weak self] in
                guard let self = self else { return }
                
                let hadActivity = await action()
                await self.adjustInterval(hadActivity: hadActivity)
            }
        }
    }
    
    /// Stops the timer
    func stop() async {
        await timer?.stop()
        timer = nil
    }
    
    /// Resets the interval to base
    func resetInterval() {
        currentInterval = baseInterval
        consecutiveIdleTicks = 0
        Task {
            await timer?.updateInterval(currentInterval)
        }
    }
    
    // MARK: - Private Methods
    
    private func adjustInterval(hadActivity: Bool) {
        if hadActivity {
            // Reset to base interval on activity
            currentInterval = baseInterval
            consecutiveIdleTicks = 0
        } else {
            // Increase interval on idle
            consecutiveIdleTicks += 1
            
            if consecutiveIdleTicks > 3 {
                let newInterval = Double(currentInterval.components.seconds) * backoffMultiplier
                let newDuration = Duration.seconds(newInterval)
                currentInterval = min(newDuration, maxInterval)
            }
        }
        
        Task {
            await timer?.updateInterval(currentInterval)
        }
    }
}
