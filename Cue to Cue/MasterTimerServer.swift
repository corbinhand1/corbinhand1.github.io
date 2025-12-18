//
//  MasterTimerServer.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 1/15/25.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Master Timer State
struct MasterTimerState {
    let currentTime: Date
    let countdownTime: Int
    let countUpTime: Int
    let countdownRunning: Bool
    let countUpRunning: Bool
    let sequenceNumber: UInt64
    let timestamp: TimeInterval
    
    init(currentTime: Date = Date(), countdownTime: Int = 0, countUpTime: Int = 0, countdownRunning: Bool = false, countUpRunning: Bool = false, sequenceNumber: UInt64 = 0) {
        self.currentTime = currentTime
        self.countdownTime = countdownTime
        self.countUpTime = countUpTime
        self.countdownRunning = countdownRunning
        self.countUpRunning = countUpRunning
        self.sequenceNumber = sequenceNumber
        self.timestamp = Date().timeIntervalSince1970
    }
}

// MARK: - Timer Command
struct TimerCommand {
    let action: String
    let countdownTime: Int?
    let countUpTime: Int?
    let adjustment: Int?
    let targetTimeString: String?
    
    init(action: String, countdownTime: Int? = nil, countUpTime: Int? = nil, adjustment: Int? = nil, targetTimeString: String? = nil) {
        self.action = action
        self.countdownTime = countdownTime
        self.countUpTime = countUpTime
        self.adjustment = adjustment
        self.targetTimeString = targetTimeString
    }
}

// MARK: - Master Timer Server
class MasterTimerServer: ObservableObject {
    
    // MARK: - Published Properties (Single Source of Truth)
    @Published var currentTime: Date = Date()
    @Published var countdownTime: Int = 0
    @Published var countUpTime: Int = 0
    @Published var countdownRunning: Bool = false
    @Published var countUpRunning: Bool = false
    
    // MARK: - Private Properties
    private var sequenceNumber: UInt64 = 0
    private var timer: Timer?
    private var displayTimer: Timer?
    private let updateInterval: TimeInterval = 1.0/60.0 // 60 FPS
    private var lastUpdateTime: TimeInterval = 0
    
    // Target time for countdown-to-time functionality
    private var targetTime: Date?
    private var targetTimeString: String = "10:00:00"
    
    // MARK: - Initialization
    init() {
        print("🕐 MasterTimerServer initialized")
        startHighFrequencyUpdates()
    }
    
    deinit {
        stopUpdates()
    }
    
    // MARK: - High-Frequency Updates (60 FPS)
    private func startHighFrequencyUpdates() {
        // Use Timer for smooth 60 FPS updates on macOS
        displayTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
        
        print("🔄 Started 60 FPS timer updates")
    }
    
    private func stopHighFrequencyUpdates() {
        displayTimer?.invalidate()
        displayTimer = nil
        print("⏹️ Stopped 60 FPS timer updates")
    }
    
    private func updateTimer() {
        let now = Date()
        let currentTimeInterval = now.timeIntervalSince1970
        
        // Update current time every frame for smooth display
        currentTime = now
        
        // Update countdown timer if running
        if countdownRunning {
            countdownTime = max(0, countdownTime - 1) // Decrement by 1 second per update
            if countdownTime <= 0 {
                countdownRunning = false
                print("⏰ Countdown timer finished")
            }
        }
        
        // Update count-up timer if running
        if countUpRunning {
            countUpTime += 1 // Increment by 1 second per update
        }
        
        // Increment sequence number for message ordering
        sequenceNumber += 1
        
        // Throttle updates to prevent excessive processing
        if currentTimeInterval - lastUpdateTime >= updateInterval {
            lastUpdateTime = currentTimeInterval
            // Notify observers of state change
            objectWillChange.send()
        }
    }
    
    private func stopUpdates() {
        displayTimer?.invalidate()
        displayTimer = nil
        timer?.invalidate()
        timer = nil
        print("⏹️ Stopped timer updates")
    }
    
    // MARK: - Public API
    
    /// Get current timer state
    func getTimerState() -> MasterTimerState {
        return MasterTimerState(
            currentTime: currentTime,
            countdownTime: countdownTime,
            countUpTime: countUpTime,
            countdownRunning: countdownRunning,
            countUpRunning: countUpRunning,
            sequenceNumber: sequenceNumber
        )
    }
    
    /// Execute timer command
    func executeCommand(_ command: TimerCommand) {
        print("🎯 Executing timer command: \(command.action)")
        
        switch command.action {
        case "start":
            countdownRunning = true
        case "pause":
            countdownRunning = false
        case "reset":
            countdownTime = 0
            countdownRunning = false
        case "setCountdownTime":
            if let time = command.countdownTime {
                countdownTime = time
            }
        case "adjust":
            if let adjustment = command.adjustment {
                countdownTime = max(0, countdownTime + adjustment)
            }
        case "startCountdownToTime":
            countUpRunning = true
        case "pauseCountdownToTime":
            countUpRunning = false
        case "resetCountdownToTime":
            countUpTime = 0
            countUpRunning = false
        case "setCountdownToTime":
            if let timeString = command.targetTimeString {
                targetTimeString = timeString
                // Parse and set target time
                if let target = parseTimeString(timeString) {
                    targetTime = target
                }
            }
        default:
            print("⚠️ Unknown timer command: \(command.action)")
        }
    }
    
    /// Reset countdown with specific time (for cue selection)
    func resetCountdown(with newTime: Int) {
        countdownTime = newTime
        countdownRunning = false
        print("🔄 Reset countdown to \(newTime) seconds")
    }
    
    /// Get target time string
    func getTargetTimeString() -> String {
        return targetTimeString
    }
    
    // MARK: - Helper Methods
    
    private func parseTimeString(_ timeString: String) -> Date? {
        let components = timeString.split(separator: ":").compactMap { Int($0) }
        
        guard components.count >= 2 else { return nil }
        
        let calendar = Calendar.current
        let now = Date()
        
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
        
        if components.count == 3 {
            // HH:MM:SS format
            dateComponents.hour = components[0]
            dateComponents.minute = components[1]
            dateComponents.second = components[2]
        } else if components.count == 2 {
            // MM:SS format
            dateComponents.hour = components[0]
            dateComponents.minute = components[1]
            dateComponents.second = 0
        }
        
        return calendar.date(from: dateComponents)
    }
}

// MARK: - Extensions

extension MasterTimerServer {
    /// Format time for display
    func formatTime(_ seconds: Int) -> String {
        let isNegative = seconds < 0
        let absSeconds = abs(seconds)
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        let remainingSeconds = absSeconds % 60
        
        if hours > 0 {
            return String(format: "%@%d:%02d:%02d", isNegative ? "-" : "", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%@%02d:%02d", isNegative ? "-" : "", minutes, remainingSeconds)
        }
    }
}
