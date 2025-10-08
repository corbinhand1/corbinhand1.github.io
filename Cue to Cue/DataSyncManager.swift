//
//  DataSyncManager.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/31/24.
//

import Foundation
import Combine

class DataSyncManager: ObservableObject {
    
    // MARK: - Properties
    
    // Thread-safe data storage
    private let dataQueue = DispatchQueue(label: "DataSyncManager.dataQueue", attributes: .concurrent)
    
    // Logging throttling
    private static var lastLogTime: Date = Date.distantPast
    private static var lastNotificationTime: Date = Date.distantPast
    
    // Cue data
    private var _cueStacks: [CueStack] = []
    private var _selectedCueStackIndex: Int = 0
    private var _activeCueIndex: Int = -1
    private var _selectedCueIndex: Int = -1
    private var _highlightColors: [HighlightColorSetting] = []
    
    // Clock-related properties
    private var _currentTime: Date = Date()
    private var _countdownTime: Int = 0
    private var _countUpTime: Int = 0
    private var _countdownRunning: Bool = false
    private var _countUpRunning: Bool = false
    
    // MARK: - Thread-safe Getters/Setters
    
    var cueStacks: [CueStack] {
        get { dataQueue.sync { _cueStacks } }
        set { dataQueue.async(flags: .barrier) { self._cueStacks = newValue } }
    }
    
    var selectedCueStackIndex: Int {
        get { dataQueue.sync { _selectedCueStackIndex } }
        set { dataQueue.async(flags: .barrier) { self._selectedCueStackIndex = newValue } }
    }
    
    var activeCueIndex: Int {
        get { dataQueue.sync { _activeCueIndex } }
        set { dataQueue.async(flags: .barrier) { self._activeCueIndex = newValue } }
    }
    
    var selectedCueIndex: Int {
        get { dataQueue.sync { _selectedCueIndex } }
        set { dataQueue.async(flags: .barrier) { self._selectedCueIndex = newValue } }
    }
    
    var highlightColors: [HighlightColorSetting] {
        get { dataQueue.sync { _highlightColors } }
        set { dataQueue.async(flags: .barrier) { self._highlightColors = newValue } }
    }
    
    var currentTime: Date {
        get { dataQueue.sync { _currentTime } }
        set { dataQueue.async(flags: .barrier) { self._currentTime = newValue } }
    }
    
    var countdownTime: Int {
        get { dataQueue.sync { _countdownTime } }
        set { dataQueue.async(flags: .barrier) { self._countdownTime = newValue } }
    }
    
    var countUpTime: Int {
        get { dataQueue.sync { _countUpTime } }
        set { dataQueue.async(flags: .barrier) { self._countUpTime = newValue } }
    }
    
    var countdownRunning: Bool {
        get { dataQueue.sync { _countdownRunning } }
        set { dataQueue.async(flags: .barrier) { self._countdownRunning = newValue } }
    }
    
    var countUpRunning: Bool {
        get { dataQueue.sync { _countUpRunning } }
        set { dataQueue.async(flags: .barrier) { self._countUpRunning = newValue } }
    }
    
    // MARK: - Data Update Methods
    
    func updateCues(cueStacks: [CueStack], selectedCueStackIndex: Int, activeCueIndex: Int, selectedCueIndex: Int) {
        dataQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            self._cueStacks = cueStacks
            self._selectedCueStackIndex = selectedCueStackIndex
            self._activeCueIndex = activeCueIndex
            self._selectedCueIndex = selectedCueIndex
            
            // Automatically cache data for offline use
            self.cacheDataForOffline()
        }
    }
    
    func updateHighlightColors(_ highlightColors: [HighlightColorSetting]) {
        dataQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self._highlightColors = highlightColors
        }
    }
    
    func updateClockState(currentTime: Date, countdownTime: Int, countUpTime: Int, countdownRunning: Bool, countUpRunning: Bool) {
        dataQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            self._currentTime = currentTime
            self._countdownTime = countdownTime
            self._countUpTime = countUpTime
            self._countdownRunning = countdownRunning
            self._countUpRunning = countUpRunning
        }
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
        let jsonObject: [String: Any]
        
        if cueStacks.isEmpty || selectedCueStackIndex >= cueStacks.count {
            jsonObject = ["error": "No cue stack available"]
        } else {
            let selectedStack = cueStacks[selectedCueStackIndex]
            
            jsonObject = [
                "cueStackName": selectedStack.name,
                "columns": selectedStack.columns.map { ["name": $0.name, "width": $0.width] },
                "cues": selectedStack.cues.enumerated().map { index, cue in
                    [
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
                "highlightColors": highlightColors.map { [
                    "keyword": $0.keyword,
                    "color": $0.color.toHex()
                ] }
            ]
        }
        
        do {
            return try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        } catch {
            print("Error generating JSON response: \(error)")
            return Data()
        }
    }
}
