//
//  AuthoritativeTimerServer.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 1/15/25.
//

import Foundation
import Combine

// MARK: - Notification Names

extension Notification.Name {
    static let dragOperationStarted = Notification.Name("dragOperationStarted")
    static let dragOperationEnded = Notification.Name("dragOperationEnded")
}

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
    
    // Drag operation state tracking
    private var isDragOperationActive = false
    private var dragOperationStartTime: Date?
    
    // Playlist state
    private var playlistState: CountdownPlaylist = CountdownPlaylist()
    
    // MARK: - Initialization
    
    init() {
        // Initialize countdown-to-time with default target (but don't start it)
        targetTimeString = "10:00:00"
        if let date = parseAsTodayTime(targetTimeString) {
            countUpTarget = date
            // Set initial countUpTime for display, but don't start running
            countUpTime = max(0, Int(date.timeIntervalSince(Date())))
        }
        // countUpRunning starts as false - user must click Start
        
        startNTPSync()
        startTimerBroadcast()
        setupDragOperationObservers()
        print("🚀 AuthoritativeTimerServer initialized with countdown-to-time target: \(targetTimeString) (not running)")
    }
    
    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Drag Operation Observers
    
    private func setupDragOperationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDragOperationStarted),
            name: .dragOperationStarted,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDragOperationEnded),
            name: .dragOperationEnded,
            object: nil
        )
    }
    
    @objc private func handleDragOperationStarted() {
        startDragOperation()
    }
    
    @objc private func handleDragOperationEnded() {
        endDragOperation()
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
        
        // Always update currentTime every second for consistent web client updates
        let newCurrentTime = now
        if abs(newCurrentTime.timeIntervalSince(currentTime)) >= 1.0 {
            currentTime = newCurrentTime
        }
        
        // Update countdown timer
        if let target = countdownTarget {
            let remaining = max(0, Int(target.timeIntervalSince(now)))
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
            let remaining = max(0, Int(target.timeIntervalSince(now)))
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
    
    // MARK: - Drag Operation Management
    
    func startDragOperation() {
        isDragOperationActive = true
        dragOperationStartTime = Date()
        print("🔄 Timer server: Drag operation started - reducing update frequency")
    }
    
    func endDragOperation() {
        isDragOperationActive = false
        dragOperationStartTime = nil
        print("✅ Timer server: Drag operation ended - resuming normal update frequency")
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
        countdownTarget = Date().addingTimeInterval(TimeInterval(countdownTime))
        print("▶️ Countdown timer started: \(countdownTime) seconds, target: \(countdownTarget?.description ?? "nil")")
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
            // Only update countUpTime if not running (if running, let updateTimers handle it)
            // If paused or stopped, update the time display
            if !countUpRunning {
                countUpTime = max(0, Int(date.timeIntervalSince(Date())))
            }
            print("🎯 Countdown to time set to: \(timeString)")
            
            // If updating current entry, update the playlist state
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
                countUpTime = max(0, Int(date.timeIntervalSince(Date())))
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
            currentTime: 0, // Not used - current time is handled locally by web client
            countdownTime: countdownTime,
            countUpTime: countUpTime,
            countdownRunning: countdownRunning,
            countUpRunning: countUpRunning,
            timestamp: Date().timeIntervalSince1970 * 1000, // Convert to milliseconds
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
    
    // MARK: - Playlist Management
    
    func syncPlaylistState(_ playlist: CountdownPlaylist) {
        playlistState = playlist
        print("🔄 Playlist state synced: \(playlist.entries.count) entries, current: \(playlist.currentIndex?.description ?? "nil")")
        
        // If playlist has a current index, update the target (but don't start automatically)
        if let idx = playlist.currentIndex,
           idx < playlist.entries.count {
            let entry = playlist.entries[idx]
            setCountdownToTime(entry.timeString)
            // Don't set countUpRunning = true here - user must click Start
        }
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
                    countUpTime = max(0, Int(firstDate.timeIntervalSince(Date())))
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
                countUpTime = max(0, Int(nextDate.timeIntervalSince(Date())))
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
                countUpTime = max(0, Int(firstDate.timeIntervalSince(Date())))
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
                countUpTime = max(0, Int(nextDate.timeIntervalSince(Date())))
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
                countUpTime = max(0, Int(firstDate.timeIntervalSince(Date())))
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
