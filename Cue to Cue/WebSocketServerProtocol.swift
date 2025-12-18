//
//  WebSocketServerProtocol.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 1/19/25.
//

import Foundation

// MARK: - WebSocket Server Protocol

protocol WebSocketServerProtocol: AnyObject {
    func notifyCueNavigation(cueIndex: Int, cueId: String?)
    func notifyFileChanged(filename: String, lastUpdated: Date)
    func notifyTimerSync(timerData: [String: Any])
    func notifyTimerCommand(command: String, data: [String: Any])
    func notifyTimerUpdate(timerData: [String: Any])
}

// MARK: - Protocol Extensions for Common Functionality

extension WebSocketServerProtocol {
    func notifyCueNavigation(cueIndex: Int, cueId: String?) {
        // Default implementation - can be overridden by conforming types
    }
    
    func notifyFileChanged(filename: String, lastUpdated: Date = Date()) {
        // Default implementation - can be overridden by conforming types
    }
    
    func notifyTimerSync(timerData: [String: Any]) {
        // Default implementation - can be overridden by conforming types
    }
    
    func notifyTimerCommand(command: String, data: [String: Any] = [:]) {
        // Default implementation - can be overridden by conforming types
    }
    
    func notifyTimerUpdate(timerData: [String: Any]) {
        // Default implementation - can be overridden by conforming types
    }
}
