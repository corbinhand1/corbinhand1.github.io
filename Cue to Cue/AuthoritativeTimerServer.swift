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
    /// Clock source; injectable so tests can control time.
    private let now: () -> Date
    /// Exact time left when the countdown was paused, so pause/resume never
    /// loses the fraction of a second the Int display hides.
    private var pausedCountdownRemaining: TimeInterval?
    private var countdownTarget: Date?
    private var countUpTarget: Date?
    private var targetTimeString: String = "10:00:00"
    
    // Playlist state
    private var playlistState: CountdownPlaylist = CountdownPlaylist()
    
    // MARK: - Initialization
    
    init(now: @escaping () -> Date = Date.init, startTicking: Bool = true) {
        self.now = now
        currentTime = now()
        // Initialize countdown-to-time with default target (but don't start it)
        targetTimeString = "10:00:00"
        if let date = parseAsTodayTime(targetTimeString) {
            countUpTarget = date
            // Set initial countUpTime for display, but don't start running
            countUpTime = Self.secondsRemaining(until: date, from: now())
        }
        // countUpRunning starts as false - user must click Start

        if startTicking {
            startTimerBroadcast()
        }
        print("🚀 Timer server ready (countdown-to-time target: \(targetTimeString))")
    }

    /// Whole seconds left until `target`, rounded UP: a countdown shows 10
    /// for the whole first second and reaches 0 exactly at the target,
    /// like a stage clock. (Rounding down showed 0 up to a second early.)
    static func secondsRemaining(until target: Date, from now: Date) -> Int {
        max(0, Int(ceil(target.timeIntervalSince(now) - 0.000_001)))
    }
    
    deinit {
        timer?.invalidate()
    }
    
    // MARK: - Timer Broadcasting
    
    private func startTimerBroadcast() {
        // Update every 100ms for smooth display.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateTimers()
        }
        timer.tolerance = 0.02
        // .common keeps the clocks (and LAN timer pushes) running while the
        // user scrolls the cue list, holds a menu open, or an alert/sheet is
        // up. A plain scheduledTimer runs only in .default mode and froze.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// One tick of the clock. Called by the run-loop timer; tests call it
    /// directly with an injected clock.
    func updateTimers() {
        let now = self.now()

        // Time of day: publish when the wall-clock second changes, so the
        // Mac clock flips in step with real time (and with browser clocks).
        if Int(now.timeIntervalSince1970.rounded(.down)) != Int(currentTime.timeIntervalSince1970.rounded(.down)) {
            currentTime = now
        }

        // Update countdown timer
        if let target = countdownTarget {
            let remaining = Self.secondsRemaining(until: target, from: now)
            // Always update countdownTime when running to ensure @Published fires
            // This ensures web clients get updates even if the value hasn't changed by a full second
            if countdownTime != remaining {
                countdownTime = remaining
                // Force objectWillChange to fire for web client updates
                objectWillChange.send()
                // Countdown updates silently - no logging needed
            }
            if remaining == 0 {
                countdownRunning = false
                countdownTarget = nil
                objectWillChange.send()
                print("⏰ Countdown reached zero")
            }
        } else if countdownRunning {
            // If countdownRunning is true but countdownTarget is nil, something went wrong
            // Reset the running state to prevent stuck timers
            print("⚠️ Countdown running but no target set - resetting")
            countdownRunning = false
            objectWillChange.send()
        }
        
        // Update count-up timer (only when running)
        if countUpRunning, let target = countUpTarget {
            let remaining = Self.secondsRemaining(until: target, from: now)
            // Update countUpTime when running
            if countUpTime != remaining {
                countUpTime = remaining
            }
            if remaining == 0 {
                countUpRunning = false
                
                // Check if we should auto-advance playlist (always check if entries exist)
                if !playlistState.entries.isEmpty {
                    if advanceToNextPlaylistEntry() {
                        // Successfully advanced, timer will continue with new target
                        return
                    }
                }
                
                countUpTarget = nil
            }
        } else if countUpRunning && countUpTarget == nil {
            // If countUpRunning is true but countUpTarget is nil, something went wrong
            // Reset the running state to prevent stuck timers
            print("⚠️ Count-up running but no target set - resetting")
            countUpRunning = false
        } else if !countUpRunning && countUpTarget != nil {
            // Timer is paused - keep the current countUpTime value (don't update it)
            // This allows pause to work properly
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
        case "nextPlaylistEntry":
            _ = advanceToNextPlaylistEntryManually()
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
        // Only start if we have a valid countdown time
        guard countdownTime > 0 else {
            print("⚠️ Cannot start countdown timer: countdownTime is 0")
            return
        }
        countdownRunning = true
        let remaining = pausedCountdownRemaining ?? TimeInterval(countdownTime)
        pausedCountdownRemaining = nil
        countdownTarget = now().addingTimeInterval(remaining)
        print("▶️ Countdown timer started: \(countdownTime) seconds, target: \(countdownTarget?.description ?? "nil")")
    }
    
    private func pauseCountdownTimer() {
        if countdownRunning, let target = countdownTarget {
            let exact = max(0, target.timeIntervalSince(now()))
            pausedCountdownRemaining = exact
            countdownTime = Self.secondsRemaining(until: target, from: now())
        }
        countdownRunning = false
        countdownTarget = nil
        print("⏸️ Countdown timer paused")
    }
    
    private func resetCountdownTimer() {
        pausedCountdownRemaining = nil
        countdownRunning = false
        countdownTime = 0
        countdownTarget = nil
        print("🔄 Countdown timer reset")
    }
    
    private func setCountdownTime(_ time: Int) {
        pausedCountdownRemaining = nil
        countdownTime = time
        if countdownRunning {
            countdownTarget = now().addingTimeInterval(TimeInterval(time))
        }
    }
    
    private func adjustCountdownTime(by seconds: Int) {
        // Adjust the exact remaining time, so +1 min while running adds
        // exactly 60 s instead of also snapping to a whole second.
        if countdownRunning, let target = countdownTarget {
            let exact = max(0, target.timeIntervalSince(now()) + TimeInterval(seconds))
            countdownTarget = now().addingTimeInterval(exact)
            countdownTime = Self.secondsRemaining(until: countdownTarget!, from: now())
            if exact == 0 { countdownTarget = nil; countdownRunning = false }
        } else {
            let base = pausedCountdownRemaining ?? TimeInterval(countdownTime)
            let exact = max(0, base + TimeInterval(seconds))
            pausedCountdownRemaining = exact
            countdownTime = Int(ceil(exact - 0.000_001))
        }
        let newTime = countdownTime
        print("➕➖ Countdown adjusted by \(seconds) seconds to \(newTime)")
    }
    
    // MARK: - Countdown to Time Controls
    
    private func setCountdownToTime(_ timeString: String) {
        let isNewTarget = timeString != targetTimeString
        targetTimeString = timeString
        if let date = parseAsTodayTime(timeString) {
            countUpTarget = date
            if countUpRunning {
                // updateTimers() keeps countUpTime in sync while running.
            } else if isNewTarget || countUpTime == 0 {
                countUpTime = Self.secondsRemaining(until: date, from: now())
            }

            if isNewTarget {
                print("🎯 Countdown to time: \(timeString)")
            }

            if let currentIdx = playlistState.currentIndex,
               currentIdx < playlistState.entries.count {
                playlistState.entries[currentIdx].timeString = timeString
            }
        } else {
            print("❌ Invalid time string: \(timeString)")
        }
    }
    
    private func startCountdownToTime() {
        // Always use playlist if it has entries
        if !playlistState.entries.isEmpty {
            // If no current index set, start with first entry
            let currentIdx: Int
            if let idx = playlistState.currentIndex, idx < playlistState.entries.count {
                currentIdx = idx
            } else {
                // Set to first entry if not set
                currentIdx = 0
                playlistState.currentIndex = 0
                // Notify DataSyncManager to update its state
                NotificationCenter.default.post(
                    name: Notification.Name("PlaylistIndexChanged"),
                    object: nil,
                    userInfo: ["newIndex": 0]
                )
            }
            
            let entry = playlistState.entries[currentIdx]
            if let date = parseAsTodayTime(entry.timeString) {
                countUpTarget = date
                countUpRunning = true
                countUpTime = Self.secondsRemaining(until: date, from: now())
                targetTimeString = entry.timeString
                print("▶️ Countdown to time started (playlist entry \(currentIdx + 1)): \(entry.timeString) - \(countUpTime) seconds remaining")
                return
            } else {
                print("❌ Invalid time in playlist entry \(currentIdx + 1): \(entry.timeString)")
            }
        }
        
        // If playlist is empty, cannot start
        print("❌ Cannot start countdown-to-time: playlist is empty. Add entries via Playlist button.")
    }
    
    private func pauseCountdownToTime() {
        if countUpRunning {
            countUpRunning = false
            objectWillChange.send()
            // Keep countUpTarget and countUpTime so we can resume later
            print("⏸️ Countdown to time paused at \(countUpTime) seconds")
        } else {
            print("⏸️ Countdown to time already paused")
        }
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
        let now = self.now()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = second
        
        if let date = calendar.date(from: components) {
            // If the time has already passed today, assume the next day
            if date < now {
                return calendar.date(byAdding: .day, value: 1, to: date)
            }
            return date
        }
        return nil
    }
    
    // MARK: - Public API
    
    func getTimerState() -> TimerState {
        return TimerState(
            currentTime: 0, // Not used - current time is handled locally by web client
            countdownTime: countdownTime,
            countUpTime: countUpTime,
            countdownRunning: countdownRunning,
            countUpRunning: countUpRunning,
            timestamp: now().timeIntervalSince1970 * 1000, // Convert to milliseconds
            countdownTarget: countdownTarget?.timeIntervalSince1970,
            countUpTarget: countUpTarget?.timeIntervalSince1970
        )
    }
    
    func getTargetTimeString() -> String {
        return targetTimeString
    }
    
    /// Selecting a cue with a timer value restarts the countdown from it.
    func resetCountdown(with newTime: Int) {
        pausedCountdownRemaining = nil
        countdownTime = newTime
        countdownTarget = now().addingTimeInterval(TimeInterval(newTime))
        countdownRunning = true
        print("🔄 Countdown reset: \(newTime)s")
    }
    
    // MARK: - Playlist Management
    
    func syncPlaylistState(_ playlist: CountdownPlaylist) {
        playlistState = playlist

        let entryLabel: String
        if let idx = playlist.currentIndex, idx < playlist.entries.count {
            let entry = playlist.entries[idx]
            entryLabel = entry.label.map { " — \($0)" } ?? ""
            setCountdownToTime(entry.timeString)
        } else {
            entryLabel = ""
        }
        print("🔄 Playlist: \(playlist.entries.count) entries, current: \(playlist.currentIndex?.description ?? "none")\(entryLabel)")
    }
    
    func getCurrentPlaylistEntry() -> PlaylistEntry? {
        guard let currentIdx = playlistState.currentIndex,
              currentIdx < playlistState.entries.count else {
            return nil
        }
        return playlistState.entries[currentIdx]
    }
    
    // Public method to manually advance to next playlist entry
    func advanceToNextPlaylistEntryManually() -> Bool {
        guard let currentIdx = playlistState.currentIndex else {
            // If no current index, set to first entry
            if !playlistState.entries.isEmpty {
                playlistState.currentIndex = 0
                let firstEntry = playlistState.entries[0]
                if let firstDate = parseAsTodayTime(firstEntry.timeString) {
                    countUpTarget = firstDate
                    countUpTime = Self.secondsRemaining(until: firstDate, from: now())
                    targetTimeString = firstEntry.timeString
                    countUpRunning = true
                    
                    NotificationCenter.default.post(
                        name: Notification.Name("PlaylistAdvanced"),
                        object: nil,
                        userInfo: ["newIndex": 0]
                    )
                    
                    print("⏭️ Manually advanced to first entry: \(firstEntry.timeString)")
                    return true
                }
            }
            return false
        }
        
        // Check if there's a next entry
        if currentIdx < playlistState.entries.count - 1 {
            let nextIdx = currentIdx + 1
            playlistState.currentIndex = nextIdx
            let nextEntry = playlistState.entries[nextIdx]
            
            if let nextDate = parseAsTodayTime(nextEntry.timeString) {
                countUpTarget = nextDate
                countUpTime = Self.secondsRemaining(until: nextDate, from: now())
                targetTimeString = nextEntry.timeString
                countUpRunning = true
                
                NotificationCenter.default.post(
                    name: Notification.Name("PlaylistAdvanced"),
                    object: nil,
                    userInfo: ["newIndex": nextIdx]
                )
                
                print("⏭️ Manually advanced to entry \(nextIdx + 1): \(nextEntry.timeString)")
                return true
            }
        } else if playlistState.loopPlaylist && !playlistState.entries.isEmpty {
            // Loop to first entry
            playlistState.currentIndex = 0
            let firstEntry = playlistState.entries[0]
            
            if let firstDate = parseAsTodayTime(firstEntry.timeString) {
                countUpTarget = firstDate
                countUpTime = Self.secondsRemaining(until: firstDate, from: now())
                targetTimeString = firstEntry.timeString
                countUpRunning = true
                
                NotificationCenter.default.post(
                    name: Notification.Name("PlaylistAdvanced"),
                    object: nil,
                    userInfo: ["newIndex": 0]
                )
                
                print("🔁 Manually looped to first entry: \(firstEntry.timeString)")
                return true
            }
        }
        
        return false
    }
    
    private func advanceToNextPlaylistEntry() -> Bool {
        guard let currentIdx = playlistState.currentIndex else {
            return false
        }
        
        // Check if there's a next entry
        if currentIdx < playlistState.entries.count - 1 {
            // Advance to next entry
            let nextIdx = currentIdx + 1
            playlistState.currentIndex = nextIdx
            let nextEntry = playlistState.entries[nextIdx]
            
            if let nextDate = parseAsTodayTime(nextEntry.timeString) {
                countUpTarget = nextDate
                countUpTime = Self.secondsRemaining(until: nextDate, from: now())
                targetTimeString = nextEntry.timeString
                countUpRunning = true
                
                // Notify DataSyncManager to update its playlist state
                NotificationCenter.default.post(
                    name: Notification.Name("PlaylistAdvanced"),
                    object: nil,
                    userInfo: ["newIndex": nextIdx]
                )
                
                print("⏭️ Playlist advanced to entry \(nextIdx + 1): \(nextEntry.timeString)")
                return true
            } else {
                print("❌ Invalid time in playlist entry \(nextIdx + 1): \(nextEntry.timeString)")
                return false
            }
        } else if playlistState.loopPlaylist && !playlistState.entries.isEmpty {
            // Loop to first entry
            playlistState.currentIndex = 0
            let firstEntry = playlistState.entries[0]
            
            if let firstDate = parseAsTodayTime(firstEntry.timeString) {
                countUpTarget = firstDate
                countUpTime = Self.secondsRemaining(until: firstDate, from: now())
                targetTimeString = firstEntry.timeString
                countUpRunning = true
                
                // Notify DataSyncManager to update its playlist state
                NotificationCenter.default.post(
                    name: Notification.Name("PlaylistAdvanced"),
                    object: nil,
                    userInfo: ["newIndex": 0]
                )
                
                print("🔁 Playlist looped to first entry: \(firstEntry.timeString)")
                return true
            } else {
                print("❌ Invalid time in first playlist entry: \(firstEntry.timeString)")
                return false
            }
        } else {
            // No more entries, stop at end (but keep currentIndex for reference)
            playlistState.currentIndex = nil
            
            // Notify DataSyncManager
            NotificationCenter.default.post(
                name: Notification.Name("PlaylistCompleted"),
                object: nil
            )
            
            print("✅ Playlist completed")
            return false
        }
    }
}
