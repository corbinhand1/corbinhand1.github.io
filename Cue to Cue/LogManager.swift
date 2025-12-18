//
//  LogManager.swift
//  Cue to Cue
//
//  Manages console log output for debug window
//

import Foundation
import Combine
import os.log

class LogManager: ObservableObject {
    static let shared = LogManager()
    
    @Published var logs: [LogEntry] = []
    @Published var isCapturing = true
    @Published var isPaused = false
    
    private var logLimit = 2000 // Maximum number of log entries to keep
    private var lastLogMessage: String?
    private var lastLogTime: Date?
    private let duplicateLogThreshold: TimeInterval = 1.0 // Suppress exact duplicates within 1 second
    private var recentLogMessages: [String] = [] // Track recent messages to detect patterns
    private let patternDetectionWindow: TimeInterval = 5.0 // Detect repeating patterns within 5 seconds
    private var messageSequence: [String] = [] // Track message sequences to detect loops
    private var messageSequenceTimestamps: [Date] = [] // Track timestamps for time-based suppression
    private var seenSequences: [(sequence: [String], firstSeen: Date, count: Int)] = [] // Track seen sequences with timestamps
    private let sequenceSuppressionWindow: TimeInterval = 30.0 // Suppress sequences that repeat within 30 seconds
    private let logQueue = DispatchQueue(label: "LogManager.queue", qos: .utility)
    
    private init() {
        // Start capturing immediately
        startCapturing()
    }
    
    func startCapturing() {
        isCapturing = true
        // Ensure print interceptor is running
        PrintInterceptor.shared.startIntercepting()
    }
    
    func stopCapturing() {
        isCapturing = false
        // Note: We don't stop the print interceptor here to keep capturing system output
    }
    
    func addLog(_ message: String, level: LogLevel = .info) {
        guard isCapturing && !isPaused else { return }
        
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        // Filter out spammy system messages
        if shouldFilterMessage(trimmedMessage) {
            return
        }
        
        // Suppress duplicate messages within threshold time
        let now = Date()
        if let lastMessage = lastLogMessage,
           let lastTime = lastLogTime,
           lastMessage == trimmedMessage,
           now.timeIntervalSince(lastTime) < duplicateLogThreshold {
            return // Skip duplicate log
        }
        
        // Detect repeating sync patterns and infinite loops
        if isRepeatingSyncPattern(trimmedMessage, now: now) {
            return // Skip if this is part of a repeating sync pattern
        }
        
        // Detect infinite loops by checking for repeating message sequences
        if isInfiniteLoop(trimmedMessage) {
            return // Skip if we're in an infinite loop
        }
        
        // Detect time-based repeating sequences
        if isTimeBasedRepeatingSequence(trimmedMessage, now: now) {
            return // Skip if this sequence has been seen recently
        }
        
        // Update tracking
        lastLogMessage = trimmedMessage
        lastLogTime = now
        
        // Track recent messages for pattern detection
        recentLogMessages.append(trimmedMessage)
        if recentLogMessages.count > 30 {
            recentLogMessages.removeFirst(15)
        }
        
        // Track message sequence for loop detection
        messageSequence.append(trimmedMessage)
        messageSequenceTimestamps.append(now)
        if messageSequence.count > 30 {
            messageSequence.removeFirst(15)
            messageSequenceTimestamps.removeFirst(15)
        }
        
        let entry = LogEntry(
            timestamp: Date(),
            message: trimmedMessage,
            level: level
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.logs.append(entry)
            
            // Limit log size
            if self.logs.count > self.logLimit {
                self.logs.removeFirst(self.logs.count - self.logLimit)
            }
        }
        
        // Also print to console for Xcode
        print(trimmedMessage)
    }
    
    private func shouldFilterMessage(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        
        // Only filter out truly spammy system messages, keep all useful debug info
        let spamPatterns = [
            "malloc: nano zone abandoned",
            "nw_path_evaluator_evaluate",
            "nw_path_create_evaluator",
            "nw_listener_start_on_queue",
            "tcp_output",
            "cfbundletyperole",
            "info.plist warning",
            "address already in use",
            "layoutsubtreeifneeded",
            "necp_client_action_add",
            "flags=[r.]",
            "attributegraph: cycle detected",
            "nsapplication(nswindowrestoration) restorewindow",
            // OSLog system messages
            "oslog-",
            "viewbridge to remoteviewservice",
            "nsviewbridgeerror",
            "textinputui",
            "remoteviewservice terminated",
            // Only filter very routine timer messages
            "🕐 timer server synchronized"
        ]
        
        for pattern in spamPatterns {
            if lowercased.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    func pause() {
        isPaused = true
    }
    
    func resume() {
        isPaused = false
    }
    
    func togglePause() {
        isPaused.toggle()
    }
    
    private func isRepeatingSyncPattern(_ message: String, now: Date) -> Bool {
        let lowercased = message.lowercased()
        
        // Expanded keywords to catch all repeating patterns from user's log output
        let syncKeywords = [
            "sync", "cue stack", "github", "repository", "metadata", "loadlastfile", "autosync",
            "loadlastfile() called", "found lastsavedurl", "file exists, loading", "loaded", "cue stacks",
            "first stack:", "file has valid data", "loaded last file:", "createtestdataifneeded",
            "test data already exists", "timer broadcasting", "autosyncifenabled", "auto-sync enabled",
            "syncCueData called", "cue stacks count:", "selected cue stack index:", "starting sync process",
            "github token configured", "preparing cue data", "cue data prepared", "sending data to github",
            "github api url:", "got sha for", "using existing sha", "request body prepared",
            "http response for", "file cuetocue", "already up-to-date", "sync successful",
            "file cuetocue/cuetocue-data.json", "file cuetocue/metadata.json"
        ]
        let isSyncMessage = syncKeywords.contains { lowercased.contains($0) }
        
        if isSyncMessage {
            // Count how many similar sync messages we've seen recently
            let similarCount = recentLogMessages.filter { msg in
                let msgLower = msg.lowercased()
                return syncKeywords.contains { msgLower.contains($0) }
            }.count
            
            // Lowered threshold from 10+ to 5+ to be more aggressive in suppressing loops
            if similarCount > 5 {
                return true
            }
        }
        
        return false
    }
    
    private func isInfiniteLoop(_ message: String) -> Bool {
        // Check if the last messages form a repeating pattern
        guard messageSequence.count >= 10 else { return false }
        
        // Check for 5-message repeating patterns
        let last10 = Array(messageSequence.suffix(10))
        let last5 = Array(last10.suffix(5))
        let previous5 = Array(last10.prefix(5))
        
        // Check if last 5 messages match previous 5 (indicating a loop)
        if last5 == previous5 {
            return true
        }
        
        // Check for 10-message repeating patterns (expanded detection)
        if messageSequence.count >= 20 {
            let last20 = Array(messageSequence.suffix(20))
            let last10 = Array(last20.suffix(10))
            let previous10 = Array(last20.prefix(10))
            
            // Check if last 10 messages match previous 10 (indicating a longer loop)
            if last10 == previous10 {
                return true
            }
        }
        
        // Also check for exact duplicate sequences (3 identical 5-message sequences)
        if messageSequence.count >= 15 {
            let last15 = Array(messageSequence.suffix(15))
            let seq1 = Array(last15.prefix(5))
            let seq2 = Array(last15[5..<10])
            let seq3 = Array(last15.suffix(5))
            
            if seq1 == seq2 && seq2 == seq3 {
                return true
            }
        }
        
        // Check for 3 identical 10-message sequences (expanded detection)
        if messageSequence.count >= 30 {
            let last30 = Array(messageSequence.suffix(30))
            let seq1 = Array(last30.prefix(10))
            let seq2 = Array(last30[10..<20])
            let seq3 = Array(last30.suffix(10))
            
            if seq1 == seq2 && seq2 == seq3 {
                return true
            }
        }
        
        return false
    }
    
    private func isTimeBasedRepeatingSequence(_ message: String, now: Date) -> Bool {
        // Check if we have enough messages to form a sequence
        guard messageSequence.count >= 10 else { return false }
        
        // Get the last 10 messages as a potential repeating sequence
        let lastSequence = Array(messageSequence.suffix(10))
        let sequenceKey = lastSequence.joined(separator: "|||") // Use a delimiter that won't appear in messages
        
        // Clean up old sequences outside the suppression window
        seenSequences = seenSequences.filter { sequence, firstSeen, _ in
            now.timeIntervalSince(firstSeen) < sequenceSuppressionWindow
        }
        
        // Check if we've seen this exact sequence before
        if let existingIndex = seenSequences.firstIndex(where: { $0.sequence.joined(separator: "|||") == sequenceKey }) {
            let existing = seenSequences[existingIndex]
            
            // If this sequence was seen within the suppression window, suppress it
            if now.timeIntervalSince(existing.firstSeen) < sequenceSuppressionWindow {
                // Increment the count
                seenSequences[existingIndex].count += 1
                return true // Suppress this repeating sequence
            } else {
                // Sequence is old, update it with new timestamp
                seenSequences[existingIndex].firstSeen = now
                seenSequences[existingIndex].count = 1
                return false
            }
        } else {
            // First time seeing this sequence, record it
            seenSequences.append((sequence: lastSequence, firstSeen: now, count: 1))
            
            // Limit the number of tracked sequences to prevent memory issues
            if seenSequences.count > 50 {
                seenSequences.removeFirst(25)
            }
            
            return false
        }
    }
    
    // Convenience methods for different log levels
    func log(_ message: String) {
        addLog(message, level: .info)
    }
    
    func logWarning(_ message: String) {
        addLog(message, level: .warning)
    }
    
    func logError(_ message: String) {
        addLog(message, level: .error)
    }
    
    func logDebug(_ message: String) {
        addLog(message, level: .debug)
    }
    
    func clearLogs() {
        DispatchQueue.main.async { [weak self] in
            self?.logs.removeAll()
        }
    }
    
    func exportLogs() -> String {
        return logs.map { $0.formattedString }.joined(separator: "\n")
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let level: LogLevel
    let formattedTimestamp: String // Store formatted timestamp to prevent live updates
    
    // Static formatter to avoid recreating it
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX") // Ensure consistent formatting
        return formatter
    }()
    
    init(timestamp: Date, message: String, level: LogLevel) {
        // id is already initialized in the property declaration
        self.timestamp = timestamp
        self.message = message
        self.level = level
        
        // Format timestamp once at creation time using static formatter
        self.formattedTimestamp = Self.timestampFormatter.string(from: timestamp)
    }
    
    var formattedString: String {
        let levelString = level.emoji
        return "[\(formattedTimestamp)] \(levelString) \(message)"
    }
}

enum LogLevel {
    case info
    case warning
    case error
    case debug
    
    var emoji: String {
        switch self {
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .debug: return "🔍"
        }
    }
    
    var color: String {
        switch self {
        case .info: return "blue"
        case .warning: return "orange"
        case .error: return "red"
        case .debug: return "gray"
        }
    }
}

