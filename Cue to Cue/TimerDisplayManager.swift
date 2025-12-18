//
//  TimerDisplayManager.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 1/15/25.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Display Update Strategy
enum DisplayUpdateStrategy {
    case smooth      // 60 FPS smooth interpolation
    case efficient   // 30 FPS for better performance
    case minimal     // 10 FPS for low-power devices
}

// MARK: - Timer Display Manager
class TimerDisplayManager: ObservableObject {
    
    // MARK: - Published Display Properties
    @Published var displayCurrentTime: Date = Date()
    @Published var displayCountdownTime: Int = 0
    @Published var displayCountUpTime: Int = 0
    @Published var displayCountdownRunning: Bool = false
    @Published var displayCountUpRunning: Bool = false
    
    // MARK: - Private Properties
    private let masterTimer: MasterTimerServer
    private var cancellables = Set<AnyCancellable>()
    private var displayTimer: Timer?
    private var lastUpdateTime: TimeInterval = 0
    
    // Display settings
    private var updateStrategy: DisplayUpdateStrategy = .smooth
    private var targetFrameRate: Int = 60
    
    // Smooth interpolation
    private var interpolationFactor: Double = 0.0
    private var lastMasterState: MasterTimerState?
    private var targetState: MasterTimerState?
    
    // MARK: - Initialization
    init(masterTimer: MasterTimerServer) {
        self.masterTimer = masterTimer
        setupMasterTimerSubscriptions()
        startDisplayUpdates()
        print("🖥️ TimerDisplayManager initialized")
    }
    
    deinit {
        stopDisplayUpdates()
    }
    
    // MARK: - Master Timer Subscriptions
    private func setupMasterTimerSubscriptions() {
        // Subscribe to master timer state changes
        masterTimer.objectWillChange
            .sink { [weak self] in
                self?.updateTargetState()
            }
            .store(in: &cancellables)
        
        // Initial state
        updateTargetState()
    }
    
    private func updateTargetState() {
        targetState = masterTimer.getTimerState()
        interpolationFactor = 0.0
    }
    
    // MARK: - Display Updates
    
    private func startDisplayUpdates() {
        let interval = 1.0 / Double(targetFrameRate)
        displayTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
        
        print("🔄 Started display updates at \(targetFrameRate) FPS")
    }
    
    private func stopDisplayUpdates() {
        displayTimer?.invalidate()
        displayTimer = nil
        print("⏹️ Stopped display updates")
    }
    
    private func updateDisplay() {
        let currentTime = Date().timeIntervalSince1970
        
        // Throttle updates based on strategy
        let updateInterval = getUpdateInterval()
        if currentTime - lastUpdateTime < updateInterval {
            return
        }
        
        lastUpdateTime = currentTime
        
        switch updateStrategy {
        case .smooth:
            updateWithSmoothInterpolation()
        case .efficient:
            updateDirectly()
        case .minimal:
            updateMinimally()
        }
    }
    
    private func updateWithSmoothInterpolation() {
        guard let target = targetState else { return }
        
        // Smooth interpolation between current and target state
        interpolationFactor = min(1.0, interpolationFactor + 0.1)
        
        // Interpolate countdown time
        let currentCountdown = Double(displayCountdownTime)
        let targetCountdown = Double(target.countdownTime)
        displayCountdownTime = Int(currentCountdown + (targetCountdown - currentCountdown) * interpolationFactor)
        
        // Interpolate count-up time
        let currentCountUp = Double(displayCountUpTime)
        let targetCountUp = Double(target.countUpTime)
        displayCountUpTime = Int(currentCountUp + (targetCountUp - currentCountUp) * interpolationFactor)
        
        // Update boolean states immediately
        displayCountdownRunning = target.countdownRunning
        displayCountUpRunning = target.countUpRunning
        
        // Update current time
        displayCurrentTime = target.currentTime
        
        // Reset interpolation when close to target
        if interpolationFactor >= 1.0 {
            interpolationFactor = 0.0
            lastMasterState = target
        }
    }
    
    private func updateDirectly() {
        guard let target = targetState else { return }
        
        displayCurrentTime = target.currentTime
        displayCountdownTime = target.countdownTime
        displayCountUpTime = target.countUpTime
        displayCountdownRunning = target.countdownRunning
        displayCountUpRunning = target.countUpRunning
    }
    
    private func updateMinimally() {
        guard let target = targetState else { return }
        
        // Only update if there's a significant change
        if abs(displayCountdownTime - target.countdownTime) > 1 ||
           abs(displayCountUpTime - target.countUpTime) > 1 ||
           displayCountdownRunning != target.countdownRunning ||
           displayCountUpRunning != target.countUpRunning {
            
            displayCurrentTime = target.currentTime
            displayCountdownTime = target.countdownTime
            displayCountUpTime = target.countUpTime
            displayCountdownRunning = target.countdownRunning
            displayCountUpRunning = target.countUpRunning
        }
    }
    
    // MARK: - Update Strategy Management
    
    private func getUpdateInterval() -> TimeInterval {
        switch updateStrategy {
        case .smooth:
            return 1.0/60.0  // 60 FPS
        case .efficient:
            return 1.0/30.0  // 30 FPS
        case .minimal:
            return 1.0/10.0  // 10 FPS
        }
    }
    
    func setUpdateStrategy(_ strategy: DisplayUpdateStrategy) {
        updateStrategy = strategy
        
        switch strategy {
        case .smooth:
            targetFrameRate = 60
        case .efficient:
            targetFrameRate = 30
        case .minimal:
            targetFrameRate = 10
        }
        
        // Restart display link with new frame rate
        stopDisplayUpdates()
        startDisplayUpdates()
        
        print("🔄 Updated display strategy to \(strategy)")
    }
    
    // MARK: - Public API
    
    /// Force immediate display update
    func forceUpdate() {
        updateTargetState()
        updateDirectly()
    }
    
    /// Get current display state
    func getDisplayState() -> MasterTimerState {
        return MasterTimerState(
            currentTime: displayCurrentTime,
            countdownTime: displayCountdownTime,
            countUpTime: displayCountUpTime,
            countdownRunning: displayCountdownRunning,
            countUpRunning: displayCountUpRunning,
            sequenceNumber: masterTimer.getTimerState().sequenceNumber
        )
    }
    
    /// Check if display is synchronized with master timer
    func isSynchronized() -> Bool {
        let masterState = masterTimer.getTimerState()
        return displayCountdownTime == masterState.countdownTime &&
               displayCountUpTime == masterState.countUpTime &&
               displayCountdownRunning == masterState.countdownRunning &&
               displayCountUpRunning == masterState.countUpRunning
    }
    
    /// Get synchronization statistics
    func getSyncStats() -> [String: Any] {
        let masterState = masterTimer.getTimerState()
        return [
            "isSynchronized": isSynchronized(),
            "displayCountdownTime": displayCountdownTime,
            "masterCountdownTime": masterState.countdownTime,
            "displayCountUpTime": displayCountUpTime,
            "masterCountUpTime": masterState.countUpTime,
            "updateStrategy": updateStrategy,
            "targetFrameRate": targetFrameRate,
            "interpolationFactor": interpolationFactor
        ]
    }
}

// MARK: - Extensions

extension TimerDisplayManager {
    /// Format time for display with smooth transitions
    func formatDisplayTime(_ seconds: Int) -> String {
        return masterTimer.formatTime(seconds)
    }
    
    /// Execute a timer command
    func executeTimerCommand(_ command: TimerCommand) {
        masterTimer.executeCommand(command)
    }
    
    /// Get display performance metrics
    func getPerformanceMetrics() -> [String: Any] {
        let currentTime = Date().timeIntervalSince1970
        return [
            "lastUpdateTime": lastUpdateTime,
            "timeSinceLastUpdate": currentTime - lastUpdateTime,
            "updateStrategy": updateStrategy,
            "targetFrameRate": targetFrameRate,
            "interpolationFactor": interpolationFactor
        ]
    }
}
