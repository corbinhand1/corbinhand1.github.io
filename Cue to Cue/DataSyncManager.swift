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

    /// Monotonic version for LAN WebSocket clients to detect missed updates.
    private(set) var dataVersion: UInt64 = 0
    /// Monotonic version for cue selection / follow-state (independent of sheet data).
    private(set) var showVersion: UInt64 = 0
    weak var broadcastHub: LANBroadcastHub?

    /// Cached LAN JSON snapshot — main thread only.
    private var lastWebClientJSON: Data?
    private var lastWebClientJSONVersion: UInt64 = UInt64.max

    /// Suppress duplicate debounced snapshots right after an explicit LAN broadcast.
    private(set) var lastLANBroadcastTime: Date = .distantPast

    func invalidateWebClientJSONCache() {
        lastWebClientJSONVersion = UInt64.max
    }

    func bumpShowVersion() {
        showVersion += 1
    }

    /// Playback state for LAN `show_state` messages (green/yellow row highlights).
    func buildShowStatePayload() -> [String: Any]? {
        let webIndex = getWebClientCueStackIndex()
        let stacks = cueStacks
        guard webIndex >= 0, webIndex < stacks.count else { return nil }

        let isViewingMacStack = webIndex == selectedCueStackIndex
        let selected = isViewingMacStack ? selectedCueIndex : -1
        let upNext = isViewingMacStack
            ? (stacks[webIndex].cues.nextPlayableIndex(after: selected) ?? -1)
            : -1

        return [
            "selectedCueIndex": selected,
            "activeCueIndex": selected,
            "upNextCueIndex": upNext,
            "currentCueStackIndex": webIndex,
            "cueStackId": stacks[webIndex].id.uuidString,
            "cueStackName": stacks[webIndex].name
        ]
    }
    
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

        recordLANChange(kind: .snapshot)
        cacheDataForOffline()
    }

    func updateHighlightColors(_ highlightColors: [HighlightColorSetting]) {
        self.highlightColors = highlightColors
        recordLANChange(kind: .snapshot)
    }

    /// Bump data version and notify LAN WebSocket clients. Call on main thread.
    func recordLANChange(kind: LANChangeKind, patch: LANCuePatch? = nil) {
        dataVersion += 1
        lastLANBroadcastTime = Date()
        broadcastHub?.notifyChange(version: dataVersion, kind: kind, patch: patch)
        if kind == .stackChanged {
            broadcastHub?.broadcastShowStateIfNeeded()
        }
    }

    /// Push a full snapshot when the Mac app mutates cue stacks (debounced observer).
    func publishLANSnapshotFromMacIfNeeded() {
        guard let hub = broadcastHub, hub.webSocketClientCount > 0 else { return }
        if Date().timeIntervalSince(lastLANBroadcastTime) < 0.35 { return }
        recordLANChange(kind: .snapshot)
    }

    /// Push a single-cell edit from the Mac UI (data already updated in memory).
    func recordMacCueValueChange(cueId: UUID, columnIndex: Int, newValue: String) {
        guard let hub = broadcastHub, hub.webSocketClientCount > 0 else { return }
        recordLANChange(
            kind: .cuePatch,
            patch: LANCuePatch(cueId: cueId, columnIndex: columnIndex, newValue: newValue)
        )
    }
    
    // MARK: - Cue Editing Methods
    
    func updateCueValue(cueId: UUID, columnIndex: Int, newValue: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume(returning: self.updateCueValueSync(
                    cueId: cueId,
                    columnIndex: columnIndex,
                    newValue: newValue
                ))
            }
        }
    }

    /// Main-thread cue update used by the LAN HTTP server.
    func updateCueValueSync(cueId: UUID, columnIndex: Int, newValue: String) -> Bool {
        var success = false

        for stackIndex in 0..<cueStacks.count {
            if let cueIndex = cueStacks[stackIndex].cues.firstIndex(where: { $0.id == cueId }) {
                if columnIndex < cueStacks[stackIndex].cues[cueIndex].values.count {
                    let oldValue = cueStacks[stackIndex].cues[cueIndex].values[columnIndex]
                    cueStacks[stackIndex].cues[cueIndex].values[columnIndex] = newValue
                    print("🔍 Updated cue \(cueId) column \(columnIndex): '\(oldValue)' -> '\(newValue)'")
                    success = true
                } else {
                    print("❌ Column index \(columnIndex) out of range for cue \(cueId)")
                }
                break
            }
        }

        if !success {
            print("❌ Cue not found for update: \(cueId)")
        }

        if success {
            recordWebChange()
            autoSaveToFile()
            recordLANChange(
                kind: .cuePatch,
                patch: LANCuePatch(cueId: cueId, columnIndex: columnIndex, newValue: newValue)
            )
            print("🔄 Desktop app notified of cue update: \(newValue) in column \(columnIndex)")
        }

        return success
    }
    
    func addCue(to cueStackId: UUID, values: [String], timerValue: String = "") async -> UUID? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume(returning: self.addCueSync(
                    to: cueStackId,
                    values: values,
                    timerValue: timerValue
                ))
            }
        }
    }

    func addCueSync(to cueStackId: UUID, values: [String], timerValue: String = "") -> UUID? {
        guard let stackIndex = cueStacks.firstIndex(where: { $0.id == cueStackId }) else {
            print("❌ Failed to find cue stack with ID: \(cueStackId)")
            return nil
        }

        let newCue = Cue(values: values, timerValue: timerValue)
        cueStacks[stackIndex].cues.append(newCue)
        print("✅ Added new cue with ID: \(newCue.id)")
        recordLANChange(kind: .snapshot)
        return newCue.id
    }
    
    func deleteCue(cueId: UUID) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume(returning: self.deleteCueSync(cueId: cueId))
            }
        }
    }

    func deleteCueSync(cueId: UUID) -> Bool {
        for stackIndex in 0..<cueStacks.count {
            if let cueIndex = cueStacks[stackIndex].cues.firstIndex(where: { $0.id == cueId }) {
                cueStacks[stackIndex].cues.remove(at: cueIndex)
                print("✅ Deleted cue with ID: \(cueId)")
                recordLANChange(kind: .snapshot)
                return true
            }
        }

        print("❌ Failed to find cue with ID: \(cueId)")
        return false
    }
    
    func toggleStrikeThrough(cueId: UUID) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                var success = false
                
                for stackIndex in 0..<self.cueStacks.count {
                    if let cueIndex = self.cueStacks[stackIndex].cues.firstIndex(where: { $0.id == cueId }) {
                        self.cueStacks[stackIndex].cues[cueIndex].isStruckThrough.toggle()
                        success = true
                        self.recordLANChange(kind: .snapshot)
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
        webClientQueue.sync(flags: .barrier) {
            let maxIndex = max(0, self.cueStacks.count - 1)
            let validIndex = max(0, min(index, maxIndex))
            self.webClientCueStackIndex = validIndex
        }
        DispatchQueue.main.async {
            self.bumpShowVersion()
            self.recordLANChange(kind: .stackChanged)
        }
    }
    
    func getWebClientCueStackIndex() -> Int {
        return webClientQueue.sync {
            return webClientCueStackIndex
        }
    }
    
    func syncWebClientWithMacOSApp() {
        webClientQueue.sync(flags: .barrier) {
            let maxIndex = max(0, self.cueStacks.count - 1)
            let validIndex = max(0, min(self.selectedCueStackIndex, maxIndex))
            self.webClientCueStackIndex = validIndex
        }
    }

    private func sheetJSONObject(
        stack: CueStack,
        stackIndex: Int,
        stacks: [CueStack],
        timerServer: AuthoritativeTimerServer
    ) -> [String: Any] {
        [
            "dataVersion": dataVersion,
            "cueStackId": stack.id.uuidString,
            "cueStackName": stack.name,
            "columns": stack.columns.map { ["name": $0.name, "width": Double($0.width)] },
            "cues": stack.cues.enumerated().map { index, cue in
                [
                    "id": cue.id.uuidString,
                    "index": index,
                    "values": cue.values,
                    "timerValue": cue.timerValue,
                    "isStruckThrough": cue.isStruckThrough,
                    "struck": Array(repeating: cue.isStruckThrough, count: stack.columns.count)
                ]
            },
            "lastUpdateTime": Date().timeIntervalSince1970,
            "currentDate": DataSyncManager.dateFormatter.string(from: timerServer.currentTime),
            "currentTime": DataSyncManager.timeFormatter.string(from: timerServer.currentTime),
            "currentAMPM": DataSyncManager.amPmFormatter.string(from: timerServer.currentTime),
            "highlightColors": highlightColors.compactMap { colorSetting in
                [
                    "keyword": colorSetting.keyword,
                    "color": colorSetting.color.toHex()
                ]
            },
            "availableCueStacks": stacks.enumerated().map { index, stack in
                [
                    "id": stack.id.uuidString,
                    "name": stack.name,
                    "index": index,
                    "cueCount": stack.cues.count
                ]
            },
            "currentCueStackIndex": stackIndex,
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
    
    /// One stack by id, for a viewer browsing a stack other than the one the
    /// Mac is running (GET /stack/<id>). Read-only; doesn't change what other
    /// viewers see. nil when no stack has that id.
    func webClientJSON(forStackID id: String, timerServer: AuthoritativeTimerServer) -> Data? {
        let stacks = cueStacks
        guard let index = stacks.firstIndex(where: { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }) else { return nil }
        let object = sheetJSONObject(stack: stacks[index], stackIndex: index, stacks: stacks, timerServer: timerServer)
        return try? JSONSerialization.data(withJSONObject: object, options: [])
    }

    func generateJSONResponseForWebClient(timerServer: AuthoritativeTimerServer) -> Data {
        if lastWebClientJSONVersion == dataVersion, let cached = lastWebClientJSON, !cached.isEmpty {
            return cached
        }

        let stacks = cueStacks
        let webClientIndex = getWebClientCueStackIndex()
        let selectedIndex = webClientIndex

        let jsonObject: [String: Any]

        if stacks.isEmpty {
            jsonObject = minimalWebClientJSON(timerServer: timerServer, stacks: stacks)
        } else if selectedIndex >= stacks.count || selectedIndex < 0 {
            print("❌ No valid cue stack available for web client - using fallback to macOS app")
            let fallbackIndex = selectedCueStackIndex < stacks.count ? selectedCueStackIndex : 0
            jsonObject = sheetJSONObject(
                stack: stacks[fallbackIndex],
                stackIndex: fallbackIndex,
                stacks: stacks,
                timerServer: timerServer
            )
        } else {
            jsonObject = sheetJSONObject(
                stack: stacks[selectedIndex],
                stackIndex: selectedIndex,
                stacks: stacks,
                timerServer: timerServer
            )
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
            lastWebClientJSON = jsonData
            lastWebClientJSONVersion = dataVersion
            return jsonData
        } catch {
            if let cached = lastWebClientJSON, !cached.isEmpty {
                return cached
            }
            let errorResponse = ["error": "Failed to generate JSON response", "details": error.localizedDescription]
            if let errorData = try? JSONSerialization.data(withJSONObject: errorResponse, options: []) {
                return errorData
            }
            return Data()
        }
    }

    private func minimalWebClientJSON(timerServer: AuthoritativeTimerServer, stacks: [CueStack]) -> [String: Any] {
        [
            "dataVersion": dataVersion,
            "cueStackId": "",
            "cueStackName": "",
            "columns": [],
            "cues": [],
            "lastUpdateTime": Date().timeIntervalSince1970,
            "currentDate": DataSyncManager.dateFormatter.string(from: timerServer.currentTime),
            "currentTime": DataSyncManager.timeFormatter.string(from: timerServer.currentTime),
            "currentAMPM": DataSyncManager.amPmFormatter.string(from: timerServer.currentTime),
            "highlightColors": highlightColors.compactMap { colorSetting in
                [
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
            "currentCueStackIndex": 0,
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
        if cueStacks.isEmpty {
            createTestCueStack()
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
        print("📋 Created default cue stack: \(testCueStack.name) (\(testCueStack.cues.count) cues)")
    }
}

// MARK: - Structural edits from LAN remotes (insert, move, strike, timer, delete, columns)

enum RemoteOpError: Error {
    case invalid(String)
    case notFound(String)

    var message: String {
        switch self {
        case .invalid(let m), .notFound(let m): return m
        }
    }
}

extension DataSyncManager {
    /// Stack a remote op targets, used by the HTTP layer for permission checks.
    func stackIDForRemoteOp(_ op: [String: Any]) -> UUID? {
        if let s = op["cueStackId"] as? String, let id = UUID(uuidString: s) { return id }
        let ids = ((op["cueIds"] as? [String]) ?? (op["cueId"] as? String).map { [$0] } ?? [])
            .compactMap(UUID.init(uuidString:))
        for id in ids { if let found = findCue(by: id) { return found.cueStack.id } }
        return nil
    }

    /// Column operations change the sheet's shape, so only admins may use them.
    static func isColumnOp(_ name: String) -> Bool {
        ["addColumn", "renameColumn", "deleteColumn", "moveColumn"].contains(name)
    }

    /// Applies one structural edit. Main thread only. Returns the new cue's id for inserts.
    /// The live/selected cue keeps pointing at the same cue even when others move around it.
    func applyRemoteOpSync(_ op: [String: Any]) -> Result<UUID?, RemoteOpError> {
        func uuid(_ k: String) -> UUID? { (op[k] as? String).flatMap(UUID.init(uuidString:)) }
        func uuids(_ k: String) -> [UUID] { ((op[k] as? [String]) ?? []).compactMap(UUID.init(uuidString:)) }
        func locate(_ id: UUID) -> (stack: Int, cue: Int)? {
            for s in cueStacks.indices {
                if let c = cueStacks[s].cues.firstIndex(where: { $0.id == id }) { return (s, c) }
            }
            return nil
        }
        func stackIndex() -> Int? { uuid("cueStackId").flatMap { id in cueStacks.firstIndex { $0.id == id } } }

        guard let name = op["op"] as? String else { return .failure(.invalid("Missing op")) }

        // Remember which cues are live/selected so we can re-find them after shifting rows.
        let liveStack = cueStacks.indices.contains(selectedCueStackIndex) ? selectedCueStackIndex : nil
        let activeID = liveStack.flatMap { s in
            cueStacks[s].cues.indices.contains(activeCueIndex) ? cueStacks[s].cues[activeCueIndex].id : nil }
        let selectedID = liveStack.flatMap { s in
            cueStacks[s].cues.indices.contains(selectedCueIndex) ? cueStacks[s].cues[selectedCueIndex].id : nil }

        var newID: UUID?

        switch name {
        case "insert":
            guard let s = stackIndex() else { return .failure(.notFound("Cue stack not found")) }
            let columnCount = cueStacks[s].columns.count
            var values = (op["values"] as? [String]) ?? []
            if values.count < columnCount { values += Array(repeating: "", count: columnCount - values.count) }
            else if values.count > columnCount { values = Array(values.prefix(columnCount)) }
            let cue = Cue(id: uuid("cueId") ?? UUID(), values: values,
                          timerValue: op["timerValue"] as? String ?? "",
                          isStruckThrough: op["isStruckThrough"] as? Bool ?? false)
            if locate(cue.id) != nil { return .failure(.invalid("A cue with that id already exists")) }
            let count = cueStacks[s].cues.count
            let index = min(max((op["index"] as? Int) ?? count, 0), count)
            cueStacks[s].cues.insert(cue, at: index)
            newID = cue.id

        case "move":
            guard let id = uuid("cueId"), let to = op["toIndex"] as? Int else { return .failure(.invalid("cueId and toIndex required")) }
            guard let at = locate(id) else { return .failure(.notFound("Cue not found")) }
            let cue = cueStacks[at.stack].cues.remove(at: at.cue)
            let index = min(max(to, 0), cueStacks[at.stack].cues.count)
            cueStacks[at.stack].cues.insert(cue, at: index)

        case "strike":
            guard let struck = op["struck"] as? Bool else { return .failure(.invalid("struck required")) }
            var found = false
            for id in uuids("cueIds") {
                if let at = locate(id) { cueStacks[at.stack].cues[at.cue].isStruckThrough = struck; found = true }
            }
            if !found { return .failure(.notFound("Cue not found")) }

        case "timer":
            guard let id = uuid("cueId"), let value = op["timerValue"] as? String else { return .failure(.invalid("cueId and timerValue required")) }
            guard let at = locate(id) else { return .failure(.notFound("Cue not found")) }
            cueStacks[at.stack].cues[at.cue].timerValue = value

        case "delete":
            var found = false
            for id in uuids("cueIds") {
                if let at = locate(id) { cueStacks[at.stack].cues.remove(at: at.cue); found = true }
            }
            if !found { return .failure(.notFound("Cue not found")) }

        case "addColumn":
            guard let s = stackIndex() else { return .failure(.notFound("Cue stack not found")) }
            guard let title = (op["name"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty else {
                return .failure(.invalid("Column name required")) }
            let count = cueStacks[s].columns.count
            let index = min(max((op["index"] as? Int) ?? count, 0), count)
            let width = (op["width"] as? Double).map { CGFloat($0) } ?? 100
            cueStacks[s].columns.insert(Column(name: title, width: width), at: index)
            for c in cueStacks[s].cues.indices {
                let at = min(index, cueStacks[s].cues[c].values.count)
                cueStacks[s].cues[c].values.insert("", at: at)
            }

        case "renameColumn":
            guard let s = stackIndex() else { return .failure(.notFound("Cue stack not found")) }
            guard let i = op["columnIndex"] as? Int, cueStacks[s].columns.indices.contains(i) else { return .failure(.invalid("columnIndex out of range")) }
            guard let title = (op["name"] as? String)?.trimmingCharacters(in: .whitespaces), !title.isEmpty else {
                return .failure(.invalid("Column name required")) }
            cueStacks[s].columns[i].name = title

        case "deleteColumn":
            guard let s = stackIndex() else { return .failure(.notFound("Cue stack not found")) }
            guard let i = op["columnIndex"] as? Int, cueStacks[s].columns.indices.contains(i) else { return .failure(.invalid("columnIndex out of range")) }
            guard cueStacks[s].columns.count > 1 else { return .failure(.invalid("A stack needs at least one column")) }
            cueStacks[s].columns.remove(at: i)
            for c in cueStacks[s].cues.indices where cueStacks[s].cues[c].values.indices.contains(i) {
                cueStacks[s].cues[c].values.remove(at: i)
            }

        case "moveColumn":
            guard let s = stackIndex() else { return .failure(.notFound("Cue stack not found")) }
            guard let from = op["from"] as? Int, let to = op["to"] as? Int,
                  cueStacks[s].columns.indices.contains(from) else { return .failure(.invalid("from/to out of range")) }
            let dest = min(max(to, 0), cueStacks[s].columns.count - 1)
            let col = cueStacks[s].columns.remove(at: from)
            cueStacks[s].columns.insert(col, at: dest)
            for c in cueStacks[s].cues.indices where cueStacks[s].cues[c].values.indices.contains(from) {
                let v = cueStacks[s].cues[c].values.remove(at: from)
                cueStacks[s].cues[c].values.insert(v, at: min(dest, cueStacks[s].cues[c].values.count))
            }

        default:
            return .failure(.invalid("Unknown op '\(name)'"))
        }

        // Keep the live and selected cue on the same cue after rows shifted.
        if let s = liveStack, cueStacks.indices.contains(s) {
            let cues = cueStacks[s].cues
            if let id = activeID { activeCueIndex = cues.firstIndex { $0.id == id } ?? min(activeCueIndex, cues.count - 1) }
            if let id = selectedID { selectedCueIndex = cues.firstIndex { $0.id == id } ?? min(selectedCueIndex, cues.count - 1) }
        }

        recordWebChange()
        autoSaveToFile()
        recordLANChange(kind: .snapshot)
        return .success(newID)
    }
}
