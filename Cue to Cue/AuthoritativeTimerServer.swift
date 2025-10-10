//
//  AuthoritativeTimerServer.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 1/15/25.
//

import Foundation
import Combine

// MARK: - Timer State Models

struct TimerState: Codable {
    let currentTime: TimeInterval
    let countdownTime: Int
    let countUpTime: Int
    let countdownRunning: Bool
    let countUpRunning: Bool
    let timestamp: TimeInterval
    let countdownTarget: TimeInterval?
    let countUpTarget: TimeInterval?
}

struct TimerCommand: Codable {
    let action: String // "start", "pause", "reset", "adjust", "setCountdownToTime"
    let countdownTime: Int?
    let countUpTime: Int?
    let adjustment: Int? // for +/- buttons
    let targetTimeString: String? // for countdown to time
}

// MARK: - Authoritative Timer Server

class AuthoritativeTimerServer: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentTime: Date = Date()
    @Published var countdownTime: Int = 0
    @Published var countUpTime: Int = 0
    @Published var countdownRunning: Bool = false
    @Published var countUpRunning: Bool = false
    
    // MARK: - Private Properties
    
    private var timer: Timer?
    private var countdownTarget: Date?
    private var countUpTarget: Date?
    private var targetTimeString: String = "10:00:00"
    private var timeOffset: TimeInterval = 0
    
    // MARK: - Initialization
    
    init() {
        // Initialize countdown-to-time with default target
        targetTimeString = "10:00:00"
        if let date = parseAsTodayTime(targetTimeString) {
            countUpTarget = date
        }
        
        startNTPSync()
        startTimerBroadcast()
        print("🚀 AuthoritativeTimerServer initialized with countdown-to-time target: \(targetTimeString)")
    }
    
    deinit {
        timer?.invalidate()
    }
    
    // MARK: - NTP Synchronization
    
    private func startNTPSync() {
        // For now, we'll use system time with a placeholder for NTP
        // In production, integrate with actual NTP client
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            // TODO: Implement actual NTP synchronization
            // For now, we'll use system time which is usually accurate enough
            self.timeOffset = 0
            print("🕐 Timer server synchronized with system time")
        }
    }
    
    // MARK: - Timer Broadcasting
    
    private func startTimerBroadcast() {
        // Update every 100ms for smooth display
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.updateTimers()
        }
    }
    
    private func updateTimers() {
        let now = Date().addingTimeInterval(timeOffset)
        currentTime = now
        
        // Update countdown timer
        if let target = countdownTarget {
            let remaining = max(0, Int(target.timeIntervalSince(now)))
            countdownTime = remaining
            if remaining == 0 {
                countdownRunning = false
                countdownTarget = nil
            }
        }
        
        // Update count-up timer
        if let target = countUpTarget {
            let remaining = max(0, Int(target.timeIntervalSince(now)))
            countUpTime = remaining
            if remaining == 0 {
                countUpRunning = false
                countUpTarget = nil
            }
        }
    }
    
    // MARK: - Timer Commands
    
    func executeCommand(_ command: TimerCommand) {
        switch command.action {
        case "start":
            startCountdownTimer()
        case "pause":
            pauseCountdownTimer()
        case "reset":
            resetCountdownTimer()
        case "adjust":
            if let adjustment = command.adjustment {
                adjustCountdownTime(by: adjustment)
            }
        case "setCountdownToTime":
            if let timeString = command.targetTimeString {
                setCountdownToTime(timeString)
            }
        case "startCountdownToTime":
            startCountdownToTime()
        case "pauseCountdownToTime":
            pauseCountdownToTime()
        case "resetCountdownToTime":
            resetCountdownToTime()
        case "setCountdownTime":
            if let time = command.countdownTime {
                setCountdownTime(time)
            }
        default:
            print("❌ Unknown timer command: \(command.action)")
        }
    }
    
    // MARK: - Regular Countdown Controls
    
    private func startCountdownTimer() {
        countdownRunning = true
        countdownTarget = Date().addingTimeInterval(TimeInterval(countdownTime))
        print("▶️ Countdown timer started: \(countdownTime) seconds")
    }
    
    private func pauseCountdownTimer() {
        countdownRunning = false
        countdownTarget = nil
        print("⏸️ Countdown timer paused")
    }
    
    private func resetCountdownTimer() {
        countdownRunning = false
        countdownTime = 0
        countdownTarget = nil
        print("🔄 Countdown timer reset")
    }
    
    private func setCountdownTime(_ time: Int) {
        countdownTime = time
        if countdownRunning {
            countdownTarget = Date().addingTimeInterval(TimeInterval(time))
        }
        print("⏱️ Countdown time set to: \(time) seconds")
    }
    
    private func adjustCountdownTime(by seconds: Int) {
        let newTime = max(0, countdownTime + seconds)
        countdownTime = newTime
        if countdownRunning {
            countdownTarget = Date().addingTimeInterval(TimeInterval(newTime))
        }
        print("➕➖ Countdown adjusted by \(seconds) seconds to \(newTime)")
    }
    
    // MARK: - Countdown to Time Controls
    
    private func setCountdownToTime(_ timeString: String) {
        targetTimeString = timeString
        if let date = parseAsTodayTime(timeString) {
            countUpTarget = date
            print("🎯 Countdown to time set to: \(timeString)")
        } else {
            print("❌ Invalid time string: \(timeString)")
        }
    }
    
    private func startCountdownToTime() {
        guard let target = countUpTarget else { 
            print("❌ Cannot start countdown-to-time: no target date set")
            return 
        }
        countUpRunning = true
        countUpTime = max(0, Int(target.timeIntervalSince(Date())))
        print("▶️ Countdown to time started: \(countUpTime) seconds remaining")
    }
    
    private func pauseCountdownToTime() {
        countUpRunning = false
        print("⏸️ Countdown to time paused")
    }
    
    private func resetCountdownToTime() {
        countUpRunning = false
        countUpTime = 0
        countUpTarget = nil
        targetTimeString = "10:00:00"
        if let date = parseAsTodayTime(targetTimeString) {
            countUpTarget = date
        }
        print("🔄 Countdown to time reset to default: \(targetTimeString)")
    }
    
    // MARK: - Utility Functions
    
    private func parseAsTodayTime(_ timeString: String) -> Date? {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3,
              let hour = parts.first,
              let minute = parts.dropFirst().first,
              let second = parts.last else {
            return nil
        }
        
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = second
        
        if let date = calendar.date(from: components) {
            // If the time has already passed today, assume the next day
            if date < Date() {
                return calendar.date(byAdding: .day, value: 1, to: date)
            }
            return date
        }
        return nil
    }
    
    // MARK: - Public API
    
    func getTimerState() -> TimerState {
        return TimerState(
            currentTime: currentTime.timeIntervalSince1970,
            countdownTime: countdownTime,
            countUpTime: countUpTime,
            countdownRunning: countdownRunning,
            countUpRunning: countUpRunning,
            timestamp: Date().timeIntervalSince1970,
            countdownTarget: countdownTarget?.timeIntervalSince1970,
            countUpTarget: countUpTarget?.timeIntervalSince1970
        )
    }
    
    func getTargetTimeString() -> String {
        return targetTimeString
    }
    
    func resetCountdown(with newTime: Int) {
        countdownRunning = false
        countdownTime = newTime
        countdownTarget = Date().addingTimeInterval(TimeInterval(newTime))
        countdownRunning = true
        print("🔄 Countdown reset with new time: \(newTime) seconds")
    }
}
