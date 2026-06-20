//
//  TopSectionView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/12/24.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Sync Notification Types

enum SyncNotificationType {
    case success
    case failure
    case info
}

// MARK: - Temporary WebsiteSyncManager (until added to Xcode project)

class WebsiteSyncManager: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncFilename: String?
    
    enum SyncStatus {
        case idle
        case syncing
        case success
        case failed(String)
    }
    
    init() {
        // TODO: Load configuration from settings
    }
    
    func syncCueData(cueStacks: [CueStack], selectedCueStackIndex: Int, filename: String, settingsManager: SettingsManager, completion: @escaping (Bool, String?) -> Void = { _, _ in }) {
        print("🚀 syncCueData called with filename: \(filename)")
        print("📊 Cue stacks count: \(cueStacks.count)")
        print("🎯 Selected cue stack index: \(selectedCueStackIndex)")
        
        guard !isSyncing else { 
            print("⚠️ Sync already in progress, skipping")
            completion(false, "Sync already in progress")
            return 
        }
        
        isSyncing = true
        syncStatus = .syncing
        print("🔄 Starting sync process...")
        
        // Get GitHub configuration from UserDefaults
        let githubToken = UserDefaults.standard.string(forKey: "githubToken") ?? ""
        let repoOwner = UserDefaults.standard.string(forKey: "repoOwner") ?? "corbinhand1"
        let repoName = UserDefaults.standard.string(forKey: "repoName") ?? "corbinhand1.github.io"
        
        print("🔑 GitHub token configured: \(!githubToken.isEmpty)")
        print("📁 Repository: \(repoOwner)/\(repoName)")
        
        guard !githubToken.isEmpty else {
            print("❌ GitHub token not configured")
            DispatchQueue.main.async {
                self.isSyncing = false
                self.syncStatus = .failed("GitHub token not configured")
                completion(false, "GitHub token not configured")
            }
            return
        }
        
        // Prepare cue data for web viewer
        print("📝 Preparing cue data for web viewer...")
        let cueData = prepareCueDataForWeb(cueStacks: cueStacks, selectedCueStackIndex: selectedCueStackIndex, filename: filename, settingsManager: settingsManager)
        print("✅ Cue data prepared successfully")
        
        // Send to GitHub via repository_dispatch
        print("🌐 Sending data to GitHub...")
        sendToGitHub(cueData: cueData, githubToken: githubToken, repoOwner: repoOwner, repoName: repoName) { success, error in
            DispatchQueue.main.async {
                self.isSyncing = false
                if success {
                    print("✅ Sync successful!")
                    self.syncStatus = .success
                    self.lastSyncTime = Date()
                    self.lastSyncFilename = filename
                    completion(true, nil)
                } else {
                    print("❌ Sync failed: \(error ?? "Unknown error")")
                    self.syncStatus = .failed(error ?? "Unknown error")
                    completion(false, error)
                }
            }
        }
    }
    
    func autoSyncIfEnabled(cueStacks: [CueStack], selectedCueStackIndex: Int, filename: String, settingsManager: SettingsManager) {
        // Check if auto-sync is enabled
        let autoSyncEnabled = UserDefaults.standard.bool(forKey: "autoSyncEnabled")
        print("🔄 autoSyncIfEnabled called - enabled: \(autoSyncEnabled)")
        
        if autoSyncEnabled {
            print("🚀 Auto-sync enabled, triggering sync...")
            syncCueData(cueStacks: cueStacks, selectedCueStackIndex: selectedCueStackIndex, filename: filename, settingsManager: settingsManager)
        } else {
            print("⏸️ Auto-sync disabled, skipping")
        }
    }
    
    // MARK: - Helper Functions
    
    private func prepareCueDataForWeb(cueStacks: [CueStack], selectedCueStackIndex: Int, filename: String, settingsManager: SettingsManager) -> [String: Any] {
        // Get column structure from first stack
        let columns = cueStacks.first?.columns ?? []
        
        // Convert cue stacks to web format
        var availableCueStacks: [[String: Any]] = []
        
        for stack in cueStacks {
            var cues: [[String: Any]] = []
            
            for cue in stack.cues {
                // Map cue values to column names
                var cueData: [String: Any] = [:]
                
                for (index, column) in columns.enumerated() {
                    let columnName = column.name
                    let value = index < cue.values.count ? cue.values[index] : ""
                    cueData[columnName] = value
                }
                
                // Add additional cue properties
                cueData["timerValue"] = cue.timerValue
                cueData["isStruckThrough"] = cue.isStruckThrough
                
                cues.append(cueData)
            }
            
            availableCueStacks.append([
                "id": stack.id.uuidString,
                "name": stack.name,
                "cues": cues
            ])
        }
        
        // Convert columns to web format
        var webColumns: [[String: Any]] = []
        for column in columns {
            webColumns.append([
                "id": column.id.uuidString,
                "name": column.name,
                "width": column.width
            ])
        }
        
        // Convert highlight colors to web format
        var webHighlightColors: [[String: Any]] = []
        for highlight in settingsManager.settings.highlightColors {
            webHighlightColors.append([
                "keyword": highlight.keyword,
                "color": highlight.color.toHex()
            ])
        }
        
        // Create metadata - always include current timestamp to force update
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Always include a unique sync timestamp to ensure GitHub detects a change
        let syncTimestamp = now.timeIntervalSince1970
        
        let metadata: [String: Any] = [
            "filename": filename,
            "lastUpdated": formatter.string(from: now),
            "selectedCueStackIndex": selectedCueStackIndex,
            "totalCueStacks": cueStacks.count,
            "syncTimestamp": syncTimestamp // Unique timestamp ensures content is always different
        ]
        
        print("📝 Metadata prepared: filename=\(filename), lastUpdated=\(formatter.string(from: now)), syncTimestamp=\(syncTimestamp)")
        
        return [
            "cueData": [
                "availableCueStacks": availableCueStacks,
                "allCues": availableCueStacks, // For backward compatibility
                "columns": webColumns,
                "highlightColors": webHighlightColors
            ],
            "metadata": metadata
        ]
    }
    
    private func sendToGitHub(cueData: [String: Any], githubToken: String, repoOwner: String, repoName: String, completion: @escaping (Bool, String?) -> Void) {
        // Use direct file update instead of repository_dispatch
        updateGitHubFiles(cueData: cueData, githubToken: githubToken, repoOwner: repoOwner, repoName: repoName, completion: completion)
    }
    
    private func updateGitHubFiles(cueData: [String: Any], githubToken: String, repoOwner: String, repoName: String, completion: @escaping (Bool, String?) -> Void) {
        let group = DispatchGroup()
        var success = true
        var errorMessage: String?
        
        // Update cuetocue-data.json
        group.enter()
        updateGitHubFile(
            path: "cuetocue/cuetocue-data.json",
            content: cueData["cueData"] as Any,
            githubToken: githubToken,
            repoOwner: repoOwner,
            repoName: repoName
        ) { fileSuccess, fileError in
            if !fileSuccess {
                success = false
                errorMessage = fileError
            }
            group.leave()
        }
        
        // Update metadata.json
        group.enter()
        updateGitHubFile(
            path: "cuetocue/metadata.json",
            content: cueData["metadata"] as Any,
            githubToken: githubToken,
            repoOwner: repoOwner,
            repoName: repoName
        ) { fileSuccess, fileError in
            if !fileSuccess {
                success = false
                errorMessage = fileError
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            completion(success, errorMessage)
        }
    }
    
    private func updateGitHubFile(path: String, content: Any, githubToken: String, repoOwner: String, repoName: String, completion: @escaping (Bool, String?) -> Void) {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/contents/\(path)")!
        print("🌐 GitHub API URL: \(url)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: content, options: .prettyPrinted)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            let base64Content = Data(jsonString.utf8).base64EncodedString()
            
            let payload: [String: Any] = [
                "message": "Update \(path) from macOS app",
                "content": base64Content,
                "sha": "" // We'll get this from the API first
            ]
            
            // First, get the current file to get the SHA
            getFileSHA(path: path, githubToken: githubToken, repoOwner: repoOwner, repoName: repoName) { sha in
                var finalPayload = payload
                if let sha = sha {
                    finalPayload["sha"] = sha
                    print("📋 Using existing SHA for \(path): \(sha.prefix(8))...")
                } else {
                    print("⚠️ No SHA found for \(path) - will create/update file without SHA (may fail if file exists)")
                    // If file exists but we don't have SHA, GitHub API will reject the update
                    // This is OK for new files, but for existing files we need the SHA
                }
                
                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: finalPayload)
                    print("✅ Request body prepared for \(path) (SHA: \(sha != nil ? "present" : "missing"))")
                    
                    URLSession.shared.dataTask(with: request) { data, response, error in
                        if let error = error {
                            print("❌ Network error for \(path): \(error)")
                            completion(false, "Network error: \(error.localizedDescription)")
                            return
                        }
                        
                        if let httpResponse = response as? HTTPURLResponse {
                            print("📡 HTTP Response for \(path): \(httpResponse.statusCode)")
                            
                            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                                print("✅ File \(path) updated successfully!")
                                completion(true, nil)
                            } else if httpResponse.statusCode == 409 {
                                // 409 means content was identical - but for metadata, we always want to update
                                // So we'll treat it as a warning but still success
                                if path.contains("metadata.json") {
                                    print("⚠️ Metadata file returned 409 - content may be identical, but this is OK")
                                    print("💡 If filename/timestamp is wrong, try syncing again to force update")
                                } else {
                                    print("✅ File \(path) already up-to-date (no changes needed)")
                                }
                                completion(true, nil)
                            } else if httpResponse.statusCode == 401 {
                                // Enhanced 401 error handling
                                var errorMessage = "HTTP 401: Authentication failed"
                                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let message = json["message"] as? String {
                                    errorMessage = "HTTP 401: \(message)"
                                }
                                print("❌ GitHub API authentication error for \(path): \(errorMessage)")
                                print("💡 Make sure your GitHub token is valid and has 'repo' scope permissions")
                                completion(false, errorMessage)
                            } else {
                                var errorMessage = "HTTP \(httpResponse.statusCode)"
                                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let message = json["message"] as? String {
                                    errorMessage = "HTTP \(httpResponse.statusCode): \(message)"
                                }
                                print("❌ GitHub API error for \(path): \(errorMessage)")
                                completion(false, errorMessage)
                            }
                        } else {
                            print("❌ Invalid response for \(path)")
                            completion(false, "Invalid response")
                        }
                    }.resume()
                } catch {
                    print("❌ Failed to serialize request body for \(path): \(error)")
                    completion(false, "Failed to serialize request body: \(error.localizedDescription)")
                }
            }
        } catch {
            print("❌ Failed to prepare content for \(path): \(error)")
            completion(false, "Failed to prepare content: \(error.localizedDescription)")
        }
    }
    
    private func getFileSHA(path: String, githubToken: String, repoOwner: String, repoName: String, completion: @escaping (String?) -> Void) {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/contents/\(path)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    print("❌ Authentication failed when getting SHA for \(path)")
                    print("💡 Check your GitHub token in Settings > Website Sync")
                    completion(nil)
                    return
                }
            }
            
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sha = json["sha"] as? String {
                print("📋 Got SHA for \(path): \(sha)")
                completion(sha)
            } else {
                print("⚠️ Could not get SHA for \(path), will create new file")
                completion(nil)
            }
        }.resume()
    }
}

struct TopSectionView: View {
    @Binding var currentTime: Date
    @Binding var countdownTime: Int
    @Binding var countdownRunning: Bool
    @Binding var countUpTime: Int
    @Binding var countUpRunning: Bool
    var timerServer: AuthoritativeTimerServer

    // "Countdown to a specific time" states:
    @State private var targetTimeString: String = "10:00:00"
    @State private var targetDate: Date? = nil
    @State private var isEditingCountdownToTime = false
    @Binding var showPlaylistEditor: Bool

    @Binding var showSettings: Bool
    @Binding var showConnectionMonitor: Bool
    @Binding var showUserManagement: Bool
    @Binding var currentFileName: String
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var websiteSyncManager: WebsiteSyncManager
    @EnvironmentObject var dataSyncManager: DataSyncManager
    var updateWebClients: () -> Void

    // For editing the regular countdown time in a TextField
    @State private var isEditingCountdown = false
    @State private var editableCountdownTime = ""
    
    // Sync notification state
    @State private var showSyncNotification = false
    @State private var syncNotificationMessage = ""
    @State private var syncNotificationType: SyncNotificationType = .success

    /// Shared height for all three clock panels so they stay aligned.
    private var clockPanelHeight: CGFloat {
        let fontSize = settingsManager.settings.clockFontSize
        let playlistExtra: CGFloat = dataSyncManager.countdownPlaylist.entries.isEmpty ? 0 : 24
        return fontSize + 88 + playlistExtra
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Timer displays in horizontal row
            currentTimeView
            countdownView(time: countdownTime, running: countdownRunning)
            countdownToTimeView()
            
            // Buttons in vertical stack
            VStack(spacing: 15) {
                networkButton
                userManagementButton
                syncButton
                settingsButton
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(20)
        .shadow(color: settingsManager.settings.fontColor.opacity(0.3), radius: 10, x: 0, y: 5)
        .onAppear {
            if countdownRunning {
                startCountdownTimer()
            }
            // Get target time string from server
            updateTargetTimeString()
        }
        // Listen for the custom reset notification from ContentView.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ResetCountdown"))) { notification in
            if let newTime = notification.object as? Int {
                resetCountdown(with: newTime)
            }
        }
        .onChange(of: countdownRunning) { oldValue, newValue in
            if newValue {
                startCountdownTimer()
            }
        }
        // Update target time string when playlist changes
        .onChange(of: dataSyncManager.countdownPlaylist) { oldValue, newValue in
            updateTargetTimeString()
        }
        // Update when playlist advances
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PlaylistAdvanced"))) { _ in
            updateTargetTimeString()
        }
        // Update target time string periodically to reflect current target
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            updateTargetTimeString()
        }
    }

    // MARK: - Timer Management
    
    // Timer updates are now handled entirely by AuthoritativeTimerServer
    // TopSectionView bindings automatically update when @Published properties change
    // No manual timer management needed here

    // MARK: - Regular Countdown Controls (Now delegate to AuthoritativeTimerServer)

    private func startCountdownTimer() {
        let command = TimerCommand(action: "start", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(command)
    }

    private func pauseCountdownTimer() {
        let command = TimerCommand(action: "pause", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(command)
    }

    private func resetCountdownTimer() {
        let command = TimerCommand(action: "reset", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(command)
    }

    /// Resets the regular countdown when a new cue timer is selected.
    private func resetCountdown(with newTime: Int) {
        timerServer.resetCountdown(with: newTime)
    }

    private func adjustCountdownTime(by seconds: Int) {
        let command = TimerCommand(action: "adjust", countdownTime: nil, countUpTime: nil, adjustment: seconds, targetTimeString: nil)
        timerServer.executeCommand(command)
    }

    // MARK: - "Countdown to Time" Controls (Now delegate to AuthoritativeTimerServer)
    
    private func updateTargetTimeString() {
        // If playlist has a current entry, show that entry's time
        if let currentIdx = dataSyncManager.countdownPlaylist.currentIndex,
           currentIdx < dataSyncManager.countdownPlaylist.entries.count {
            let entry = dataSyncManager.countdownPlaylist.entries[currentIdx]
            targetTimeString = entry.timeString
        } else {
            // Otherwise use the timer server's target time
            targetTimeString = timerServer.getTargetTimeString()
        }
    }

    private func startCountdownToTime() {
        let command = TimerCommand(action: "startCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(command)
    }

    private func pauseCountdownToTime() {
        let command = TimerCommand(action: "pauseCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(command)
    }
    
    private var hasNextPlaylistEntry: Bool {
        let playlist = dataSyncManager.countdownPlaylist
        guard !playlist.entries.isEmpty else { return false }
        
        if let currentIdx = playlist.currentIndex {
            // Check if there's a next entry or if looping is enabled
            return currentIdx < playlist.entries.count - 1 || playlist.loopPlaylist
        } else {
            // No current index, so we can go to first entry
            return true
        }
    }
    
    private func nextPlaylistEntry() {
        let command = TimerCommand(action: "nextPlaylistEntry", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(command)
    }
    
    private func selectPlaylistEntry(at index: Int) {
        guard index >= 0 && index < dataSyncManager.countdownPlaylist.entries.count else { return }
        
        // Set the current index in DataSyncManager
        dataSyncManager.setCurrentPlaylistIndex(index)
        
        // Sync playlist state to timer server (this will update the target)
        timerServer.syncPlaylistState(dataSyncManager.countdownPlaylist)
        
        // Start countdown to the selected entry immediately
        let startCommand = TimerCommand(action: "startCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(startCommand)
    }

    // MARK: - Subviews

    private var currentTimeView: some View {
        timeBox {
            VStack(alignment: .center, spacing: 4) {
                Text(dateFormatter.string(from: currentTime).uppercased())
                    .font(.custom("Digital-7Mono", size: settingsManager.settings.clockFontSize * 0.4))
                    .foregroundColor(settingsManager.settings.dateTimeColor)

                Text("Current Time")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(currentTime, formatter: timeFormatter)
                        .font(.custom("Digital-7Mono", size: settingsManager.settings.clockFontSize))
                    Text(currentTime, formatter: amPmFormatter)
                        .font(.custom("Digital-7Mono", size: settingsManager.settings.clockFontSize / 2))
                }
                .foregroundColor(settingsManager.settings.dateTimeColor)
            }
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
        }
    }

    private func countdownView(time: Int, running: Bool) -> some View {
        timeBox {
            VStack(alignment: .center, spacing: 5) {
                Text("Countdown")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                if isEditingCountdown {
                    TextField("", text: $editableCountdownTime, onCommit: {
                        if let newTime = parseTimeString(editableCountdownTime) {
                            let command = TimerCommand(action: "setCountdownTime", countdownTime: newTime, countUpTime: nil, adjustment: nil, targetTimeString: nil)
                            timerServer.executeCommand(command)
                        }
                        isEditingCountdown = false
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 150)
                    .multilineTextAlignment(.center)
                } else {
                    Text(timeString(time: time, isRunning: running))
                        .font(.custom("Digital-7Mono", size: settingsManager.settings.clockFontSize))
                        .foregroundColor(settingsManager.settings.countdownColor)
                        .onTapGesture {
                            editableCountdownTime = timeString(time: time, isRunning: false)
                            isEditingCountdown = true
                        }
                }
                HStack(spacing: 10) {
                    TimerButton(title: "Start", action: startCountdownTimer)
                    TimerButton(title: "Pause", action: pauseCountdownTimer)
                    TimerButton(title: "Reset", action: resetCountdownTimer)
                }
                HStack(spacing: 10) {
                    TimerButton(title: "-1 min", action: { adjustCountdownTime(by: -60) })
                    TimerButton(title: "+1 min", action: { adjustCountdownTime(by: 60) })
                }
            }
        }
    }

    private func countdownToTimeView() -> some View {
        timeBox {
            VStack(alignment: .center, spacing: 4) {
                // Countdown to time with label
                HStack(spacing: 4) {
                    Text("Countdown to \(targetTimeString.isEmpty ? "00:00:00" : targetTimeString)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    
                    // Show label if available
                    if let currentIdx = dataSyncManager.countdownPlaylist.currentIndex,
                       currentIdx < dataSyncManager.countdownPlaylist.entries.count,
                       let label = dataSyncManager.countdownPlaylist.entries[currentIdx].label,
                       !label.isEmpty {
                        Text("— \(label)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                if isEditingCountdownToTime {
                    VStack(spacing: 4) {
                        TextField("HH:mm:ss", text: $targetTimeString, onCommit: {
                            // If playlist has current entry, update it in DataSyncManager
                            if let currentIdx = dataSyncManager.countdownPlaylist.currentIndex,
                               currentIdx < dataSyncManager.countdownPlaylist.entries.count {
                                // Update the playlist entry in DataSyncManager
                                let currentEntry = dataSyncManager.countdownPlaylist.entries[currentIdx]
                                dataSyncManager.updatePlaylistEntry(
                                    at: currentIdx,
                                    timeString: targetTimeString,
                                    label: currentEntry.label
                                )
                                // Sync the updated playlist to timer server
                                timerServer.syncPlaylistState(dataSyncManager.countdownPlaylist)
                            }
                            
                            // Set the countdown target time
                            let command = TimerCommand(action: "setCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: targetTimeString)
                            timerServer.executeCommand(command)
                            isEditingCountdownToTime = false
                        })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 150)
                        .multilineTextAlignment(.center)
                        if let currentIdx = dataSyncManager.countdownPlaylist.currentIndex,
                           currentIdx < dataSyncManager.countdownPlaylist.entries.count {
                            Text("Editing playlist entry")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                } else {
                    Text(countUpRunning ? timeString(time: countUpTime, isRunning: countUpRunning) : "--:--:--")
                        .font(.custom("Digital-7Mono", size: settingsManager.settings.clockFontSize))
                        .foregroundColor(countUpRunning ? settingsManager.settings.countdownColor : settingsManager.settings.countdownColor.opacity(0.4))
                        .onTapGesture {
                            // If playlist has current entry, get that entry's time
                            if let currentIdx = dataSyncManager.countdownPlaylist.currentIndex,
                               currentIdx < dataSyncManager.countdownPlaylist.entries.count {
                                targetTimeString = dataSyncManager.countdownPlaylist.entries[currentIdx].timeString
                            } else {
                                // Otherwise use current target time or default
                                updateTargetTimeString()
                                if targetTimeString.isEmpty {
                                    targetTimeString = "10:00:00"
                                }
                            }
                            isEditingCountdownToTime = true
                        }
                }
                HStack(spacing: 10) {
                    TimerButton(title: "Start", action: startCountdownToTime)
                    TimerButton(title: "Pause", action: pauseCountdownToTime, isEnabled: countUpRunning)
                    TimerButton(title: "Next", action: nextPlaylistEntry, isEnabled: hasNextPlaylistEntry)
                    TimerButton(title: "Playlist", action: { showPlaylistEditor = true })
                }
                
                // Tiny playlist bar at bottom
                if !dataSyncManager.countdownPlaylist.entries.isEmpty {
                    GeometryReader { geometry in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 3) {
                                ForEach(Array(dataSyncManager.countdownPlaylist.entries.enumerated()), id: \.element.id) { index, entry in
                                    let isCurrent = dataSyncManager.countdownPlaylist.currentIndex == index
                                    PlaylistMiniCard(
                                        time: entry.timeString,
                                        label: entry.label,
                                        isCurrent: isCurrent,
                                        onTap: {
                                            selectPlaylistEntry(at: index)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 1)
                            .frame(minWidth: geometry.size.width)
                        }
                    }
                    .frame(height: 18)
                    .padding(.top, 2)
                }
            }
        }
    }

    private var settingsButton: some View {
        Button(action: { showSettings.toggle() }) {
            Image(systemName: "gear")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(settingsManager.settings.fontColor)
        }
    }
    
    private var networkButton: some View {
        Button(action: { showConnectionMonitor.toggle() }) {
            Image(systemName: "network")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(settingsManager.settings.fontColor)
        }
    }
    
    private var userManagementButton: some View {
        Button(action: { showUserManagement.toggle() }) {
            Image(systemName: "person.2")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(settingsManager.settings.fontColor)
        }
    }
    
    private var syncButton: some View {
        Button(action: {
            // Trigger sync to GitHub Pages
            websiteSyncManager.syncCueData(
                cueStacks: dataSyncManager.cueStacks,
                selectedCueStackIndex: dataSyncManager.selectedCueStackIndex,
                filename: currentFileName,
                settingsManager: settingsManager
            ) { success, error in
                if success {
                    showSyncSuccess()
                } else {
                    let errorMessage = error ?? "Unknown error"
                    showSyncFailure(errorMessage)
                    print("❌ Sync failed: \(errorMessage)")
                }
            }
        }) {
            Image(systemName: websiteSyncManager.isSyncing ? "arrow.clockwise" : "cloud")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(websiteSyncManager.isSyncing ? .orange : settingsManager.settings.fontColor)
        }
        .disabled(websiteSyncManager.isSyncing)
        .overlay(
            // Sync notification popup
            syncNotificationOverlay,
            alignment: .topTrailing
        )
    }
    
    // MARK: - Sync Notification Views and Methods
    
    private var syncNotificationOverlay: some View {
        Group {
            if showSyncNotification {
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 8) {
                        // Apple-style icon with subtle background
                        ZStack {
                            Circle()
                                .fill(syncNotificationType == .success ? Color.green : Color.red)
                                .frame(width: 20, height: 20)
                            
                            Image(systemName: syncNotificationType == .success ? "checkmark" : "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        Text(syncNotificationMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(syncNotificationType == .success ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
                    )
                }
                .offset(x: -80, y: -5)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity).combined(with: .offset(y: -10)),
                    removal: .scale(scale: 0.8).combined(with: .opacity).combined(with: .offset(y: -10))
                ))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSyncNotification)
            }
        }
    }
    
    private func showSyncSuccess() {
        syncNotificationMessage = "Sync completed"
        syncNotificationType = .success
        showSyncNotification = true
        
        // Auto-hide after 2.5 seconds (Apple's recommended duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showSyncNotification = false
        }
    }
    
    private func showSyncFailure(_ errorMessage: String) {
        syncNotificationMessage = "Sync failed"
        syncNotificationType = .failure
        showSyncNotification = true
        
        // Auto-hide after 4 seconds (longer for errors)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            showSyncNotification = false
        }
    }

    // MARK: - Utility Methods

    private func timeBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: clockPanelHeight, maxHeight: clockPanelHeight, alignment: .top)
            .background(settingsManager.settings.backgroundColor.opacity(0.2))
            .cornerRadius(15)
    }

    private func timeString(time: Int, isRunning: Bool) -> String {
        let isNegative = time < 0
        let absTime = abs(time)
        let hours = absTime / 3600
        let minutes = (absTime % 3600) / 60
        let seconds = absTime % 60
        if isRunning {
            var parts: [String] = []
            if hours > 0 {
                parts.append("\(hours)")
                parts.append(String(format: "%02d", minutes))
            } else if minutes > 0 {
                parts.append("\(minutes)")
            } else {
                parts.append("00")
            }
            parts.append(String(format: "%02d", seconds))
            let str = parts.joined(separator: ":")
            return isNegative ? "-\(str)" : str
        } else {
            let str = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            return isNegative ? "-\(str)" : str
        }
    }

    private func parseTimeString(_ timeString: String) -> Int? {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    /// Parses an input in "HH:mm:ss" format and returns a Date representing the next occurrence of that time.
    private func parseAsTodayTime(_ input: String) -> Date? {
        let parts = input.split(separator: ":").map { String($0) }
        guard parts.count == 3,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              let second = Int(parts[2]) else {
            return nil
        }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = second
        if let date = calendar.date(from: components) {
            // If the time has already passed today, assume the next day.
            if date < Date() {
                return calendar.date(byAdding: .day, value: 1, to: date)
            }
            return date
        }
        return nil
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d, yyyy"
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss"
        return formatter
    }()

    private let amPmFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "a"
        return formatter
    }()
}

struct TimerButton: View {
    let title: String
    let action: () -> Void
    var isEnabled: Bool = true
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(isEnabled ? settingsManager.settings.fontColor : settingsManager.settings.fontColor.opacity(0.4))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .disabled(!isEnabled)
        .background(settingsManager.settings.backgroundColor.opacity(isEnabled ? 0.3 : 0.15))
        .cornerRadius(8)
    }
}

// MARK: - Playlist Mini Card

struct PlaylistMiniCard: View {
    let time: String
    let label: String?
    let isCurrent: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 2) {
                Text(time)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(isCurrent ? .white : .white.opacity(0.6))
                
                if let label = label, !label.isEmpty {
                    Text("•")
                        .font(.system(size: 7))
                        .foregroundColor(.white.opacity(0.4))
                    Text(label)
                        .font(.system(size: 7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(isCurrent ? .white.opacity(0.8) : .white.opacity(0.5))
                        .frame(maxWidth: 40) // Limit label width to keep cards small
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle()) // Make entire area tappable
        }
        .buttonStyle(PlainButtonStyle())
        .background(isCurrent ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.08))
        .cornerRadius(2)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(isCurrent ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 0.5)
        )
        .help("Tap to countdown to this time")
    }
}

