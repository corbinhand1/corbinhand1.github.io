//
//  TimerBroadcaster.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 1/15/25.
//

import Foundation
import Combine

// MARK: - Timer Message Types
enum TimerMessageType: String, CaseIterable {
    case timerUpdate = "timer_update"
    case timerSync = "timer_sync"
    case timerCommand = "timer_command"
    case ping = "ping"
    case pong = "pong"
}

// MARK: - Timer Message Structure
struct TimerMessage {
    let type: TimerMessageType
    let data: TimerMessageData
    let sequenceNumber: UInt64
    let timestamp: TimeInterval
    
    init(type: TimerMessageType, data: TimerMessageData, sequenceNumber: UInt64, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.type = type
        self.data = data
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
    }
}

// MARK: - Timer Message Data
struct TimerMessageData: Codable {
    let messageType: String
    let currentTime: String?
    let countdownTime: Int?
    let countUpTime: Int?
    let countdownRunning: Bool?
    let countUpRunning: Bool?
    let action: String?
    let timestamp: TimeInterval?
    
    // Timer update initializer
    init(timerState: MasterTimerState) {
        self.messageType = "timerUpdate"
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        self.currentTime = formatter.string(from: timerState.currentTime)
        self.countdownTime = timerState.countdownTime
        self.countUpTime = timerState.countUpTime
        self.countdownRunning = timerState.countdownRunning
        self.countUpRunning = timerState.countUpRunning
        self.action = nil
        self.timestamp = timerState.timestamp
    }
    
    // Timer command initializer
    init(command: TimerCommand) {
        self.messageType = "timerCommand"
        self.currentTime = nil
        self.countdownTime = command.countdownTime
        self.countUpTime = command.countUpTime
        self.countdownRunning = nil
        self.countUpRunning = nil
        self.action = command.action
        self.timestamp = Date().timeIntervalSince1970
    }
    
    // Ping initializer
    init(pingTimestamp: TimeInterval) {
        self.messageType = "ping"
        self.currentTime = nil
        self.countdownTime = nil
        self.countUpTime = nil
        self.countdownRunning = nil
        self.countUpRunning = nil
        self.action = nil
        self.timestamp = pingTimestamp
    }
    
    // Pong initializer
    init(pongTimestamp: TimeInterval) {
        self.messageType = "pong"
        self.currentTime = nil
        self.countdownTime = nil
        self.countUpTime = nil
        self.countdownRunning = nil
        self.countUpRunning = nil
        self.action = nil
        self.timestamp = pongTimestamp
    }
}

// MARK: - Timer Broadcaster Protocol
protocol TimerBroadcasterProtocol: AnyObject {
    func broadcastTimerUpdate(_ timerState: MasterTimerState)
    func broadcastTimerCommand(_ command: TimerCommand)
    func broadcastPing()
    func broadcastPong()
}

// MARK: - Timer Broadcaster
class TimerBroadcaster: ObservableObject {
    
    // MARK: - Properties
    private let masterTimer: MasterTimerServer
    private weak var connectionManager: ConnectionManager?
    private var cancellables = Set<AnyCancellable>()
    private var lastBroadcastSequence: UInt64 = 0
    private var lastBroadcastTime: TimeInterval = 0
    
    // Message throttling settings
    private let minBroadcastInterval: TimeInterval = 1.0/60.0 // 60 FPS max
    private let maxSequenceGap: UInt64 = 10 // Don't broadcast if too many updates missed
    
    // Binary encoding for efficiency
    private let useBinaryEncoding: Bool = true
    
    // MARK: - Initialization
    init(masterTimer: MasterTimerServer, connectionManager: ConnectionManager? = nil) {
        self.masterTimer = masterTimer
        self.connectionManager = connectionManager
        setupTimerSubscriptions()
        print("📡 TimerBroadcaster initialized")
    }
    
    // MARK: - Timer Subscriptions
    private func setupTimerSubscriptions() {
        // Subscribe to timer state changes
        masterTimer.objectWillChange
            .sink { [weak self] in
                self?.handleTimerStateChange()
            }
            .store(in: &cancellables)
    }
    
    private func handleTimerStateChange() {
        let currentTime = Date().timeIntervalSince1970
        let timerState = masterTimer.getTimerState()
        
        // Throttle broadcasts to prevent excessive network traffic
        if currentTime - lastBroadcastTime >= minBroadcastInterval {
            // Check if sequence number is reasonable (not too far behind)
            if timerState.sequenceNumber - lastBroadcastSequence <= maxSequenceGap {
                broadcastTimerUpdate(timerState)
                lastBroadcastTime = currentTime
                lastBroadcastSequence = timerState.sequenceNumber
            }
        }
    }
    
    // MARK: - Broadcasting Methods
    
    func broadcastTimerUpdate(_ timerState: MasterTimerState) {
        let messageData = TimerMessageData(timerState: timerState)
        let message = TimerMessage(
            type: .timerUpdate,
            data: messageData,
            sequenceNumber: timerState.sequenceNumber,
            timestamp: timerState.timestamp
        )
        
        broadcastMessage(message)
    }
    
    func broadcastTimerCommand(_ command: TimerCommand) {
        let messageData = TimerMessageData(command: command)
        let message = TimerMessage(
            type: .timerCommand,
            data: messageData,
            sequenceNumber: masterTimer.getTimerState().sequenceNumber
        )
        
        broadcastMessage(message)
    }
    
    func broadcastPing() {
        let timestamp = Date().timeIntervalSince1970
        let messageData = TimerMessageData(pingTimestamp: timestamp)
        let message = TimerMessage(
            type: .ping,
            data: messageData,
            sequenceNumber: masterTimer.getTimerState().sequenceNumber
        )
        
        broadcastMessage(message)
    }
    
    func broadcastPong() {
        let timestamp = Date().timeIntervalSince1970
        let messageData = TimerMessageData(pongTimestamp: timestamp)
        let message = TimerMessage(
            type: .pong,
            data: messageData,
            sequenceNumber: masterTimer.getTimerState().sequenceNumber
        )
        
        broadcastMessage(message)
    }
    
    // MARK: - Message Broadcasting
    
    private func broadcastMessage(_ message: TimerMessage) {
        do {
            // For now, use simple JSON encoding of the data only
            let messageData = try JSONEncoder().encode(message.data)
            
            // Broadcast to all WebSocket connections via ConnectionManager
            connectionManager?.broadcastToAllConnections(messageData)
            print("📡 Broadcasting timer message: \(message.type.rawValue) (seq: \(message.sequenceNumber))")
            
        } catch {
            print("❌ Error encoding timer message: \(error)")
        }
    }
    
}

// MARK: - Supporting Data Structures

struct TimerCommandData: Codable {
    let action: String
    let countdownTime: Int?
    let countUpTime: Int?
    let adjustment: Int?
    let targetTimeString: String?
    
    init(from command: TimerCommand) {
        self.action = command.action
        self.countdownTime = command.countdownTime
        self.countUpTime = command.countUpTime
        self.adjustment = command.adjustment
        self.targetTimeString = command.targetTimeString
    }
}

struct PingData: Codable {
    let timestamp: TimeInterval
    
    init() {
        self.timestamp = Date().timeIntervalSince1970
    }
}

struct PongData: Codable {
    let timestamp: TimeInterval
    
    init() {
        self.timestamp = Date().timeIntervalSince1970
    }
}

// MARK: - Extensions

extension TimerBroadcaster {
    /// Get connection statistics
    func getConnectionStats() -> [String: Any] {
        return [
            "lastBroadcastSequence": lastBroadcastSequence,
            "lastBroadcastTime": lastBroadcastTime,
            "minBroadcastInterval": minBroadcastInterval,
            "useBinaryEncoding": useBinaryEncoding
        ]
    }
    
    /// Force broadcast current timer state
    func forceBroadcast() {
        let timerState = masterTimer.getTimerState()
        broadcastTimerUpdate(timerState)
    }
}
