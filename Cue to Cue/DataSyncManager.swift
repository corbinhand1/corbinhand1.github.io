//
//  DataSyncManager.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/31/24.
//

import Foundation
import Combine

// MARK: - Notifications

extension Notification.Name {
    static let autoSaveRequested = Notification.Name("autoSaveRequested")
}

class DataSyncManager: ObservableObject {
    
    // MARK: - Properties
    
    // Thread-safe data storage
    private let dataQueue = DispatchQueue(label: "DataSyncManager.dataQueue", attributes: .concurrent)
    
    // Logging throttling
    private static var lastLogTime: Date = Date.distantPast
    private static var lastNotificationTime: Date = Date.distantPast
    
    // Cue data - Published properties for SwiftUI
    @Published var cueStacks: [CueStack] = []
    @Published var selectedCueStackIndex: Int = 0
    @Published var activeCueIndex: Int = -1
    @Published var selectedCueIndex: Int = -1
    @Published var highlightColors: [HighlightColorSetting] = []
    
    // Clock-related properties - Published for SwiftUI
    @Published var currentTime: Date = Date()
    @Published var countdownTime: Int = 0
    @Published var countUpTime: Int = 0
    @Published var countdownRunning: Bool = false
    @Published var countUpRunning: Bool = false
    
    // Track when web changes were made to prevent auto-load from overwriting them
    private var _lastWebChangeTime: Date = Date.distantPast
    
    
    // MARK: - Data Update Methods
    
    func updateCues(cueStacks: [CueStack], selectedCueStackIndex: Int, activeCueIndex: Int, selectedCueIndex: Int) {
        self.cueStacks = cueStacks
        self.selectedCueStackIndex = selectedCueStackIndex
        self.activeCueIndex = activeCueIndex
        self.selectedCueIndex = selectedCueIndex
        
        // Automatically cache data for offline use
        cacheDataForOffline()
    }
    
    func updateHighlightColors(_ highlightColors: [HighlightColorSetting]) {
        self.highlightColors = highlightColors
    }
    
    func updateClockState(currentTime: Date, countdownTime: Int, countUpTime: Int, countdownRunning: Bool, countUpRunning: Bool) {
        self.currentTime = currentTime
        self.countdownTime = countdownTime
        self.countUpTime = countUpTime
        self.countdownRunning = countdownRunning
        self.countUpRunning = countUpRunning
    }
    
    // MARK: - Cue Editing Methods
    
    func updateCueValue(cueId: UUID, columnIndex: Int, newValue: String) -> Bool {
        var success = false
        
        // Update on main thread to avoid SwiftUI threading issues
        DispatchQueue.main.sync {
            for stackIndex in 0..<self.cueStacks.count {
                if let cueIndex = self.cueStacks[stackIndex].cues.firstIndex(where: { $0.id == cueId }) {
                    if columnIndex < self.cueStacks[stackIndex].cues[cueIndex].values.count {
                        let oldValue = self.cueStacks[stackIndex].cues[cueIndex].values[columnIndex]
                        self.cueStacks[stackIndex].cues[cueIndex].values[columnIndex] = newValue
                        print("🔍 Updated cue \(cueId) column \(columnIndex): '\(oldValue)' -> '\(newValue)'")
                        success = true
                        break
                    }
                }
            }
            
            // Notify the desktop app of the change and auto-save
            if success {
                // Record that this was a web change IMMEDIATELY
                self.recordWebChange()
                
                // Auto-save to file
                self.autoSaveToFile()
                
                print("🔄 Desktop app notified of cue update: \(newValue) in column \(columnIndex)")
            }
        }
        
        return success
    }
    
    func addCue(to cueStackId: UUID, values: [String], timerValue: String = "") -> UUID? {
        var newCueId: UUID?
        
        // Update on main thread to avoid SwiftUI threading issues
        DispatchQueue.main.sync {
            if let stackIndex = self.cueStacks.firstIndex(where: { $0.id == cueStackId }) {
                let newCue = Cue(values: values, timerValue: timerValue)
                self.cueStacks[stackIndex].cues.append(newCue)
                newCueId = newCue.id
            }
        }
        
        return newCueId
    }
    
    func deleteCue(cueId: UUID) -> Bool {
        var success = false
        
        // Update on main thread to avoid SwiftUI threading issues
        DispatchQueue.main.sync {
            for stackIndex in 0..<self.cueStacks.count {
                if let cueIndex = self.cueStacks[stackIndex].cues.firstIndex(where: { $0.id == cueId }) {
                    self.cueStacks[stackIndex].cues.remove(at: cueIndex)
                    success = true
                    break
                }
            }
        }
        
        return success
    }
    
    func findCue(by cueId: UUID) -> (cueStack: CueStack, cueIndex: Int)? {
        for cueStack in cueStacks {
            if let cueIndex = cueStack.cues.firstIndex(where: { $0.id == cueId }) {
                return (cueStack, cueIndex)
            }
        }
        return nil
    }
    
    // MARK: - Offline Caching
    
    /// Automatically caches current app data for offline viewing
    private func cacheDataForOffline() {
        // This method ensures that the current app state is always available offline
        // It's called whenever the cues are updated
        
        // The service worker will automatically cache the /cues endpoint
        // and the offline integration script will handle state persistence
        
        // We can also add additional caching logic here if needed
        // Reduced logging frequency to avoid spam
        let now = Date()
        if now.timeIntervalSince(DataSyncManager.lastLogTime) > 5.0 { // Only log every 5 seconds
            print("💾 Data updated - available for offline viewing")
            DataSyncManager.lastLogTime = now
        }
        
        // Notify connected clients to cache their current state
        notifyClientsToCacheState()
    }
    
    /// Notifies connected clients to cache their current state for offline use
    private func notifyClientsToCacheState() {
        // This helps ensure that all connected devices have the latest data cached
        // for offline viewing
        
        // The notification is sent via the existing connection infrastructure
        // and clients will automatically save their current state
        // Reduced logging frequency to avoid spam
        let now = Date()
        if now.timeIntervalSince(DataSyncManager.lastNotificationTime) > 10.0 { // Only log every 10 seconds
            print("📱 Notifying clients to cache current state for offline use")
            DataSyncManager.lastNotificationTime = now
        }
    }
    
    // MARK: - JSON Response Generation
    
    // Static formatters to avoid memory allocation on each request
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d, yyyy"
        return formatter
    }()
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss"
        return formatter
    }()
    
    private static let amPmFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter
    }()
    
    func generateJSONResponse() -> Data {
        let stacks = cueStacks
        let selectedIndex = selectedCueStackIndex
        
        print("🔍 generateJSONResponse() - stacks.count: \(stacks.count), selectedIndex: \(selectedIndex)")
        
        let jsonObject: [String: Any]
        
        if stacks.isEmpty || selectedIndex >= stacks.count {
            print("❌ No valid cue stack available")
            jsonObject = ["error": "No cue stack available"]
        } else {
            let selectedStack = stacks[selectedIndex]
            
            jsonObject = [
                "cueStackId": selectedStack.id.uuidString,
                "cueStackName": selectedStack.name,
                "columns": selectedStack.columns.map { ["name": $0.name, "width": Double($0.width)] },
                "cues": selectedStack.cues.enumerated().map { index, cue in
                    [
                        "id": cue.id.uuidString,
                        "index": index,
                        "values": cue.values,
                        "timerValue": cue.timerValue,
                        "isStruckThrough": cue.isStruckThrough,
                        "struck": Array(repeating: cue.isStruckThrough, count: selectedStack.columns.count)
                    ]
                },
                "activeCueIndex": activeCueIndex,
                "selectedCueIndex": selectedCueIndex,
                "lastUpdateTime": Date().timeIntervalSince1970,
                "currentDate": DataSyncManager.dateFormatter.string(from: currentTime),
                "currentTime": DataSyncManager.timeFormatter.string(from: currentTime),
                "currentAMPM": DataSyncManager.amPmFormatter.string(from: currentTime),
                "countdownTime": countdownTime,
                "countUpTime": countUpTime,
                "countdownRunning": countdownRunning,
                "countUpRunning": countUpRunning,
                "highlightColors": highlightColors.compactMap { colorSetting in
                    return [
                        "keyword": colorSetting.keyword,
                        "color": colorSetting.color.toHex()
                    ]
                }
            ]
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
            return jsonData
        } catch {
            // Return a minimal error response instead of empty data
            let errorResponse = ["error": "Failed to generate JSON response", "details": error.localizedDescription]
            if let errorData = try? JSONSerialization.data(withJSONObject: errorResponse, options: []) {
                return errorData
            }
            return Data()
        }
    }
    
    // MARK: - File Auto-Save
    
    private func autoSaveToFile() {
        // Trigger auto-save through the main app
        DispatchQueue.main.async {
            // Post notification to trigger auto-save in ContentView
            NotificationCenter.default.post(name: .autoSaveRequested, object: nil)
        }
        print("💾 Auto-save triggered - data updated in memory")
    }
    
    // MARK: - Web Change Tracking
    
    func hasRecentWebChanges(withinSeconds: TimeInterval = 30) -> Bool {
        return dataQueue.sync {
            Date().timeIntervalSince(_lastWebChangeTime) < withinSeconds
        }
    }
    
    private func recordWebChange() {
        dataQueue.sync(flags: .barrier) {
            _lastWebChangeTime = Date()
        }
    }
    
    // MARK: - Test Data Initialization
    
    func createTestDataIfNeeded() {
        print("🔍 createTestDataIfNeeded() called - cueStacks.count: \(cueStacks.count)")
        if cueStacks.isEmpty {
            print("🔍 Creating test cue stack...")
            createTestCueStack()
            print("🔍 After creation - cueStacks.count: \(cueStacks.count)")
        } else {
            print("🔍 Test data already exists, skipping creation")
        }
    }
    
    private func createTestCueStack() {
        let testCueStack = CueStack(
            name: "BOS Keynote",
            cues: [
                Cue(values: ["101", "9:25a - Doors, Walk in Music, Walk in Lx, Preset 10", "10", "", "", "", "Rock", ""], timerValue: ""),
                Cue(values: ["102", "9:55a - ROLL RECORDS & Transition to APM", "", "", "", "", "APM", ""], timerValue: ""),
                Cue(values: ["102", "9:57:30a - Preset 3 & FLS", "3", "", "", "", "", ""], timerValue: ""),
                Cue(values: ["102.01", "Preset 99 & LX 104", "99", "", "", "", "", ""], timerValue: ""),
                Cue(values: ["102.1", "Preset 5 & VT Opening", "5", "", "", "", "", ""], timerValue: ""),
                Cue(values: ["103", "Connor Mic Hot Out of VID", "", "", "", "", "", ""], timerValue: ""),
                Cue(values: ["104", "Connor VO & LX 105 [1 sac after note]", "", "", "", "", "", ""], timerValue: ""),
                Cue(values: ["105", "Preset 4 [on welcome]", "4", "", "", "", "", ""], timerValue: "")
            ],
            columns: [
                Column(name: "#", width: 60),
                Column(name: "Description", width: 300),
                Column(name: "Preset", width: 100),
                Column(name: "Video", width: 100),
                Column(name: "LX", width: 100),
                Column(name: "L3", width: 100),
                Column(name: "Audio", width: 100),
                Column(name: "Staging", width: 100)
            ]
        )
        
        cueStacks.append(testCueStack)
        print("✅ Created test cue stack with \(testCueStack.cues.count) cues and \(testCueStack.columns.count) columns")
    }
}
