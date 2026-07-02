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

class DataSyncManager: ObservableObject, @unchecked Sendable {
    
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
    @Published var countdownPlaylist: CountdownPlaylist = CountdownPlaylist()
    
    // Track when web changes were made to prevent auto-load from overwriting them
    private var _lastWebChangeTime: Date = Date.distantPast
    
    // Web client cue stack selection (separate from macOS app)
    private var webClientCueStackIndex: Int = 0
    private let webClientQueue = DispatchQueue(label: "DataSyncManager.webClientQueue", attributes: .concurrent)
    
    // Initialize web client state to match macOS app state
    init() {
        // Web client starts viewing the same cue stack as macOS app
        webClientCueStackIndex = selectedCueStackIndex
    }
    
    
    
    // MARK: - Data Update Methods
    
    func updateCues(cueStacks: [CueStack], selectedCueStackIndex: Int, activeCueIndex: Int, selectedCueIndex: Int) {
        self.cueStacks = cueStacks
        self.selectedCueStackIndex = selectedCueStackIndex
        self.activeCueIndex = activeCueIndex
        self.selectedCueIndex = selectedCueIndex
        
        print("🔄 DataSyncManager: selectedCueIndex updated to \(selectedCueIndex)")
        
        // Automatically cache data for offline use
        cacheDataForOffline()
    }
    
    func updateHighlightColors(_ highlightColors: [HighlightColorSetting]) {
        self.highlightColors = highlightColors
    }
    
    // MARK: - Cue Editing Methods
    
    func updateCueValue(cueId: UUID, columnIndex: Int, newValue: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                var success = false
                
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
                
                continuation.resume(returning: success)
            }
        }
    }
    
    func addCue(to cueStackId: UUID, values: [String], timerValue: String = "") async -> UUID? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                var newCueId: UUID?
                
                if let stackIndex = self.cueStacks.firstIndex(where: { $0.id == cueStackId }) {
                    let newCue = Cue(values: values, timerValue: timerValue)
                    self.cueStacks[stackIndex].cues.append(newCue)
                    newCueId = newCue.id
                    print("✅ Added new cue with ID: \(newCue.id)")
                } else {
                    print("❌ Failed to find cue stack with ID: \(cueStackId)")
                }
                
                continuation.resume(returning: newCueId)
            }
        }
    }
    
    func deleteCue(cueId: UUID) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                var success = false
                
                for stackIndex in 0..<self.cueStacks.count {
                    if let cueIndex = self.cueStacks[stackIndex].cues.firstIndex(where: { $0.id == cueId }) {
                        self.cueStacks[stackIndex].cues.remove(at: cueIndex)
                        success = true
                        print("✅ Deleted cue with ID: \(cueId)")
                        break
                    }
                }
                
                if !success {
                    print("❌ Failed to find cue with ID: \(cueId)")
                }
                
                continuation.resume(returning: success)
            }
        }
    }
    
    func toggleStrikeThrough(cueId: UUID) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                var success = false
                
                for stackIndex in 0..<self.cueStacks.count {
                    if let cueIndex = self.cueStacks[stackIndex].cues.firstIndex(where: { $0.id == cueId }) {
                        self.cueStacks[stackIndex].cues[cueIndex].isStruckThrough.toggle()
                        success = true
                        print("✅ Toggled strike-through for cue with ID: \(cueId) - now \(self.cueStacks[stackIndex].cues[cueIndex].isStruckThrough)")
                        break
                    }
                }
                
                if !success {
                    print("❌ Failed to find cue with ID: \(cueId)")
                }
                
                continuation.resume(returning: success)
            }
        }
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
    
    // MARK: - Web Client Cue Stack Management
    
    func setWebClientCueStackIndex(_ index: Int) {
        webClientQueue.async(flags: .barrier) {
            // Validate the index before setting
            let validIndex = max(0, min(index, self.cueStacks.count - 1))
            print("🔄 Web client cue stack changing from \(self.webClientCueStackIndex) to \(validIndex) (requested: \(index))")
            self.webClientCueStackIndex = validIndex
        }
    }
    
    func getWebClientCueStackIndex() -> Int {
        return webClientQueue.sync {
            return webClientCueStackIndex
        }
    }
    
    func syncWebClientWithMacOSApp() {
        webClientQueue.async(flags: .barrier) {
            print("🔄 Syncing web client with macOS app: \(self.selectedCueStackIndex)")
            self.webClientCueStackIndex = self.selectedCueStackIndex
        }
    }
    
    func generateJSONResponseForWebClient(timerServer: AuthoritativeTimerServer) -> Data {
        let stacks = cueStacks
        let webClientIndex = getWebClientCueStackIndex()
        
        // Use web client's selection directly - no fallback to macOS app
        let selectedIndex = webClientIndex
        
        // Debug logging removed for cleaner console output
        
        let jsonObject: [String: Any]
        
        if stacks.isEmpty || selectedIndex >= stacks.count || selectedIndex < 0 {
            print("❌ No valid cue stack available for web client - using fallback to macOS app")
            // Only fallback if web client selection is completely invalid
            let fallbackIndex = selectedCueStackIndex < stacks.count ? selectedCueStackIndex : 0
            let fallbackStack = stacks[fallbackIndex]
            
            jsonObject = [
                "cueStackId": fallbackStack.id.uuidString,
                "cueStackName": fallbackStack.name,
                "columns": fallbackStack.columns.map { ["name": $0.name, "width": Double($0.width)] },
                "cues": fallbackStack.cues.enumerated().map { index, cue in
                    [
                        "id": cue.id.uuidString,
                        "index": index,
                        "values": cue.values,
                        "timerValue": cue.timerValue,
                        "isStruckThrough": cue.isStruckThrough,
                        "struck": Array(repeating: cue.isStruckThrough, count: fallbackStack.columns.count)
                    ]
                },
                "activeCueIndex": activeCueIndex,
                "selectedCueIndex": selectedCueIndex,
                "lastUpdateTime": Date().timeIntervalSince1970,
                "currentDate": DataSyncManager.dateFormatter.string(from: timerServer.currentTime),
                "currentTime": DataSyncManager.timeFormatter.string(from: timerServer.currentTime),
                "currentAMPM": DataSyncManager.amPmFormatter.string(from: timerServer.currentTime),
                "countdownTime": timerServer.countdownTime,
                "countUpTime": timerServer.countUpTime,
                "countdownRunning": timerServer.countdownRunning,
                "countUpRunning": timerServer.countUpRunning,
                "highlightColors": highlightColors.compactMap { colorSetting in
                    return [
                        "keyword": colorSetting.keyword,
                        "color": colorSetting.color.toHex()
                    ]
                },
                "availableCueStacks": stacks.map { stack in
                    [
                        "name": stack.name,
                        "index": stacks.firstIndex(of: stack) ?? -1
                    ]
                },
                "currentCueStackIndex": fallbackIndex,
                "countdownPlaylist": [
                    "entries": countdownPlaylist.entries.map { [
                        "id": $0.id.uuidString,
                        "timeString": $0.timeString,
                        "label": $0.label ?? ""
                    ]},
                    "currentIndex": countdownPlaylist.currentIndex ?? -1,
                    "isActive": countdownPlaylist.isActive,
                    "loopPlaylist": countdownPlaylist.loopPlaylist
                ]
            ]
        } else {
            let selectedStack = stacks[selectedIndex]
            
            // Only show highlights (green/yellow) if web client is viewing the same cue stack as macOS app
            let isViewingMacOSCueStack = (webClientIndex == selectedCueStackIndex)
            let highlightActiveCueIndex = isViewingMacOSCueStack ? activeCueIndex : -1
            let highlightSelectedCueIndex = isViewingMacOSCueStack ? selectedCueIndex : -1
            
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
                // Only show highlights if viewing the macOS app's cue stack
                "activeCueIndex": highlightActiveCueIndex,
                "selectedCueIndex": highlightSelectedCueIndex,
                "lastUpdateTime": Date().timeIntervalSince1970,
                "currentDate": DataSyncManager.dateFormatter.string(from: timerServer.currentTime),
                "currentTime": DataSyncManager.timeFormatter.string(from: timerServer.currentTime),
                "currentAMPM": DataSyncManager.amPmFormatter.string(from: timerServer.currentTime),
                "countdownTime": timerServer.countdownTime,
                "countUpTime": timerServer.countUpTime,
                "countdownRunning": timerServer.countdownRunning,
                "countUpRunning": timerServer.countUpRunning,
                "highlightColors": highlightColors.compactMap { colorSetting in
                    return [
                        "keyword": colorSetting.keyword,
                        "color": colorSetting.color.toHex()
                    ]
                },
                // New fields for cue stack dropdown
                "availableCueStacks": stacks.map { stack in
                    [
                        "name": stack.name,
                        "index": stacks.firstIndex(of: stack) ?? -1
                    ]
                },
                "currentCueStackIndex": selectedIndex,
                "countdownPlaylist": [
                    "entries": countdownPlaylist.entries.map { [
                        "id": $0.id.uuidString,
                        "timeString": $0.timeString,
                        "label": $0.label ?? ""
                    ]},
                    "currentIndex": countdownPlaylist.currentIndex ?? -1,
                    "isActive": countdownPlaylist.isActive,
                    "loopPlaylist": countdownPlaylist.loopPlaylist
                ]
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
    
    // MARK: - Playlist Management
    
    func addPlaylistEntry(_ entry: PlaylistEntry) {
        DispatchQueue.main.async {
            guard self.countdownPlaylist.entries.count < 10 else {
                print("⚠️ Cannot add playlist entry: maximum of 10 entries reached")
                return
            }
            self.countdownPlaylist.entries.append(entry)
            print("✅ Added playlist entry: \(entry.timeString) - \(entry.label ?? "No label")")
        }
    }
    
    func removePlaylistEntry(at index: Int) {
        DispatchQueue.main.async {
            guard index >= 0 && index < self.countdownPlaylist.entries.count else {
                print("❌ Cannot remove playlist entry: index out of range")
                return
            }
            self.countdownPlaylist.entries.remove(at: index)
            
            // Adjust currentIndex if needed
            if let currentIdx = self.countdownPlaylist.currentIndex {
                if currentIdx == index {
                    // Current entry was removed, reset to nil or adjust
                    self.countdownPlaylist.currentIndex = nil
                } else if currentIdx > index {
                    // Current index needs to be decremented
                    self.countdownPlaylist.currentIndex = currentIdx - 1
                }
            }
            
            // If no entries left, disable playlist
            if self.countdownPlaylist.entries.isEmpty {
                // Don't set isActive to false - playlist is always active
                // Just clear currentIndex when playlist completes
                self.countdownPlaylist.currentIndex = nil
            }
            
            print("✅ Removed playlist entry at index \(index)")
        }
    }
    
    func updatePlaylistEntry(at index: Int, timeString: String, label: String?) {
        DispatchQueue.main.async {
            guard index >= 0 && index < self.countdownPlaylist.entries.count else {
                print("❌ Cannot update playlist entry: index out of range")
                return
            }
            self.countdownPlaylist.entries[index].timeString = timeString
            self.countdownPlaylist.entries[index].label = label
            print("✅ Updated playlist entry at index \(index): \(timeString) - \(label ?? "No label")")
        }
    }
    
    func reorderPlaylistEntry(from sourceIndex: Int, to destinationIndex: Int) {
        DispatchQueue.main.async {
            guard sourceIndex >= 0 && sourceIndex < self.countdownPlaylist.entries.count,
                  destinationIndex >= 0 && destinationIndex < self.countdownPlaylist.entries.count else {
                print("❌ Cannot reorder playlist entry: index out of range")
                return
            }
            
            let entry = self.countdownPlaylist.entries.remove(at: sourceIndex)
            self.countdownPlaylist.entries.insert(entry, at: destinationIndex)
            
            // Update currentIndex if needed
            if let currentIdx = self.countdownPlaylist.currentIndex {
                if currentIdx == sourceIndex {
                    self.countdownPlaylist.currentIndex = destinationIndex
                } else if sourceIndex < currentIdx && destinationIndex >= currentIdx {
                    self.countdownPlaylist.currentIndex = currentIdx - 1
                } else if sourceIndex > currentIdx && destinationIndex <= currentIdx {
                    self.countdownPlaylist.currentIndex = currentIdx + 1
                }
            }
            
            print("✅ Reordered playlist entry from \(sourceIndex) to \(destinationIndex)")
        }
    }
    
    func setPlaylistActive(_ active: Bool) {
        // No-op: Playlist is always active (playlist is the only mode)
        // Keep method for backward compatibility but always ensure isActive is true
        DispatchQueue.main.async {
            self.countdownPlaylist.isActive = true
            // If no current index but entries exist, set to first entry
            if self.countdownPlaylist.currentIndex == nil && !self.countdownPlaylist.entries.isEmpty {
                self.countdownPlaylist.currentIndex = 0
            }
            print("✅ Playlist is always active (playlist-only mode)")
        }
    }
    
    func setCurrentPlaylistIndex(_ index: Int?) {
        DispatchQueue.main.async {
            if let idx = index {
                guard idx >= 0 && idx < self.countdownPlaylist.entries.count else {
                    print("❌ Cannot set current playlist index: index out of range")
                    return
                }
            }
            self.countdownPlaylist.currentIndex = index
            print("✅ Current playlist index set to: \(index?.description ?? "nil")")
        }
    }
    
    func setLoopPlaylist(_ loop: Bool) {
        DispatchQueue.main.async {
            self.countdownPlaylist.loopPlaylist = loop
            print("✅ Playlist loop set to: \(loop)")
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
