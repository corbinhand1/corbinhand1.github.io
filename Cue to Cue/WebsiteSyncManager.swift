//
//  WebsiteSyncManager.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 1/15/25.
//

import Foundation
import Combine

// MARK: - Website Sync Manager

class WebsiteSyncManager: ObservableObject {
    
    // MARK: - Properties
    
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncFilename: String?
    
    // Configuration
    private let githubToken: String
    private let repoOwner: String
    private let repoName: String
    private let baseURL = "https://api.github.com/repos"
    
    // MARK: - Sync Status
    
    enum SyncStatus {
        case idle
        case syncing
        case success
        case failed(String)
    }
    
    // MARK: - Initialization
    
    init() {
        // TODO: Load these from Settings or environment variables
        self.githubToken = "your_github_token_here" // Replace with actual token
        self.repoOwner = "corbinhand1"
        self.repoName = "corbinhand1.github.io"
    }
    
    // MARK: - Public Methods
    
    /// Sync cue data to website
    func syncCueData(cueStacks: [CueStack], selectedCueStackIndex: Int, filename: String) {
        guard !isSyncing else { return }
        
        isSyncing = true
        syncStatus = .syncing
        
        Task {
            do {
                try await performSync(cueStacks: cueStacks, selectedCueStackIndex: selectedCueStackIndex, filename: filename)
                
                await MainActor.run {
                    self.isSyncing = false
                    self.syncStatus = .success
                    self.lastSyncTime = Date()
                    self.lastSyncFilename = filename
                }
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                    self.syncStatus = .failed(error.localizedDescription)
                }
            }
        }
    }
    
    /// Auto-sync when cue data changes
    func autoSyncIfEnabled(cueStacks: [CueStack], selectedCueStackIndex: Int, filename: String) {
        // Check if auto-sync is enabled (you can add this to Settings)
        let autoSyncEnabled = UserDefaults.standard.bool(forKey: "autoSyncEnabled")
        
        if autoSyncEnabled {
            syncCueData(cueStacks: cueStacks, selectedCueStackIndex: selectedCueStackIndex, filename: filename)
        }
    }
    
    // MARK: - Private Methods
    
    private func performSync(cueStacks: [CueStack], selectedCueStackIndex: Int, filename: String) async throws {
        // Convert cue data to web format
        let webData = convertToWebFormat(cueStacks: cueStacks, selectedCueStackIndex: selectedCueStackIndex, filename: filename)
        
        // Create metadata
        let metadata = createMetadata(filename: filename)
        
        // Send to GitHub
        try await sendToGitHub(cueData: webData, metadata: metadata)
    }
    
    private func convertToWebFormat(cueStacks: [CueStack], selectedCueStackIndex: Int, filename: String) -> [String: Any] {
        let cueStack = cueStacks[selectedCueStackIndex]
        let now = Date()
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE MMM d, yyyy"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm:ss"
        
        let amPmFormatter = DateFormatter()
        amPmFormatter.dateFormat = "a"
        
        let webCues = cueStack.cues.enumerated().map { index, cue in
            [
                "id": cue.id.uuidString,
                "index": index,
                "values": cue.values,
                "timerValue": cue.timerValue,
                "isStruckThrough": cue.isStruckThrough,
                "struck": Array(repeating: cue.isStruckThrough, count: cueStack.columns.count)
            ]
        }
        
        let webColumns = cueStack.columns.map { column in
            [
                "name": column.name,
                "width": Double(column.width)
            ]
        }
        
        let availableCueStacks = cueStacks.enumerated().map { index, stack in
            [
                "name": stack.name,
                "index": index
            ]
        }
        
        return [
            "cueStackId": cueStack.id.uuidString,
            "cueStackName": cueStack.name,
            "filename": filename,
            "columns": webColumns,
            "cues": webCues,
            "activeCueIndex": -1,
            "selectedCueIndex": -1,
            "lastUpdateTime": now.timeIntervalSince1970,
            "currentDate": dateFormatter.string(from: now),
            "currentTime": timeFormatter.string(from: now),
            "currentAMPM": amPmFormatter.string(from: now),
            "countdownTime": 0,
            "countUpTime": 0,
            "countdownRunning": false,
            "countUpRunning": false,
            "availableCueStacks": availableCueStacks,
            "currentCueStackIndex": selectedCueStackIndex
        ]
    }
    
    private func createMetadata(filename: String) -> [String: Any] {
        return [
            "filename": filename,
            "lastUpdated": ISO8601DateFormatter().string(from: Date()),
            "source": "macOS Cue to Cue App",
            "syncMethod": "GitHub Actions"
        ]
    }
    
    private func sendToGitHub(cueData: [String: Any], metadata: [String: Any]) async throws {
        let url = URL(string: "\(baseURL)/\(repoOwner)/\(repoName)/dispatches")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = [
            "event_type": "cue-data-update",
            "client_payload": [
                "cueData": cueData,
                "metadata": metadata
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }
        
        if httpResponse.statusCode != 204 {
            throw SyncError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case invalidToken
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .invalidToken:
            return "Invalid GitHub token"
        }
    }
}

// MARK: - Settings Integration

extension WebsiteSyncManager {
    
    /// Check if auto-sync is enabled
    var isAutoSyncEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "autoSyncEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "autoSyncEnabled")
        }
    }
    
    /// Get GitHub token from settings
    var githubTokenFromSettings: String? {
        get {
            UserDefaults.standard.string(forKey: "githubToken")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "githubToken")
        }
    }
    
    /// Configure sync settings
    func configure(githubToken: String, autoSyncEnabled: Bool) {
        self.githubTokenFromSettings = githubToken
        self.isAutoSyncEnabled = autoSyncEnabled
    }
}


