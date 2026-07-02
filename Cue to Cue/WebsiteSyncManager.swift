//
//  WebsiteSyncManager.swift
//  Cue to Cue
//

import Foundation
import Combine

enum SyncNotificationType {
    case success
    case failure
    case info
}

enum WebsiteSyncSettingsKeys {
    static let githubToken = "githubToken"
    static let repoOwner = "repoOwner"
    static let repoName = "repoName"
    static let autoSyncEnabled = "autoSyncEnabled"

    static let defaultRepoOwner = "corbinhand1"
    static let defaultRepoName = "corbinhand1.github.io"
}

final class WebsiteSyncManager: ObservableObject {

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

    func syncCueData(
        cueStacks: [CueStack],
        selectedCueStackIndex: Int,
        filename: String,
        settingsManager: SettingsManager,
        completion: @escaping (Bool, String?) -> Void = { _, _ in }
    ) {
        guard !isSyncing else {
            completion(false, "Sync already in progress")
            return
        }

        let githubToken = UserDefaults.standard.string(forKey: WebsiteSyncSettingsKeys.githubToken) ?? ""
        let repoOwner = UserDefaults.standard.string(forKey: WebsiteSyncSettingsKeys.repoOwner)
            ?? WebsiteSyncSettingsKeys.defaultRepoOwner
        let repoName = UserDefaults.standard.string(forKey: WebsiteSyncSettingsKeys.repoName)
            ?? WebsiteSyncSettingsKeys.defaultRepoName

        guard !githubToken.isEmpty else {
            DispatchQueue.main.async {
                self.syncStatus = .failed("GitHub token not configured")
                completion(false, "GitHub token not configured")
            }
            return
        }

        isSyncing = true
        syncStatus = .syncing

        let cueData = prepareCueDataForWeb(
            cueStacks: cueStacks,
            selectedCueStackIndex: selectedCueStackIndex,
            filename: filename,
            settingsManager: settingsManager
        )

        sendToGitHub(
            cueData: cueData,
            githubToken: githubToken,
            repoOwner: repoOwner,
            repoName: repoName
        ) { success, error in
            DispatchQueue.main.async {
                self.isSyncing = false
                if success {
                    self.syncStatus = .success
                    self.lastSyncTime = Date()
                    self.lastSyncFilename = filename
                    completion(true, nil)
                } else {
                    let message = error ?? "Unknown error"
                    self.syncStatus = .failed(message)
                    completion(false, message)
                }
            }
        }
    }

    func autoSyncIfEnabled(
        cueStacks: [CueStack],
        selectedCueStackIndex: Int,
        filename: String,
        settingsManager: SettingsManager
    ) {
        guard UserDefaults.standard.bool(forKey: WebsiteSyncSettingsKeys.autoSyncEnabled) else { return }

        syncCueData(
            cueStacks: cueStacks,
            selectedCueStackIndex: selectedCueStackIndex,
            filename: filename,
            settingsManager: settingsManager
        )
    }

    // MARK: - Settings

    var isAutoSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: WebsiteSyncSettingsKeys.autoSyncEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: WebsiteSyncSettingsKeys.autoSyncEnabled) }
    }

    func loadConfiguration() -> (githubToken: String, repoOwner: String, repoName: String, autoSyncEnabled: Bool) {
        (
            githubToken: UserDefaults.standard.string(forKey: WebsiteSyncSettingsKeys.githubToken) ?? "",
            repoOwner: UserDefaults.standard.string(forKey: WebsiteSyncSettingsKeys.repoOwner)
                ?? WebsiteSyncSettingsKeys.defaultRepoOwner,
            repoName: UserDefaults.standard.string(forKey: WebsiteSyncSettingsKeys.repoName)
                ?? WebsiteSyncSettingsKeys.defaultRepoName,
            autoSyncEnabled: isAutoSyncEnabled
        )
    }

    func saveConfiguration(githubToken: String, repoOwner: String, repoName: String, autoSyncEnabled: Bool) {
        UserDefaults.standard.set(githubToken, forKey: WebsiteSyncSettingsKeys.githubToken)
        UserDefaults.standard.set(repoOwner, forKey: WebsiteSyncSettingsKeys.repoOwner)
        UserDefaults.standard.set(repoName, forKey: WebsiteSyncSettingsKeys.repoName)
        isAutoSyncEnabled = autoSyncEnabled
    }

    // MARK: - Private

    private func prepareCueDataForWeb(
        cueStacks: [CueStack],
        selectedCueStackIndex: Int,
        filename: String,
        settingsManager: SettingsManager
    ) -> [String: Any] {
        var availableCueStacks: [[String: Any]] = []

        for stack in cueStacks {
            let stackColumns = stack.columns
            var cues: [[String: Any]] = []

            for cue in stack.cues {
                var cueData: [String: Any] = [
                    "id": cue.id.uuidString,
                    "timerValue": cue.timerValue,
                    "isStruckThrough": cue.isStruckThrough,
                ]

                for (index, column) in stackColumns.enumerated() {
                    let value = index < cue.values.count ? cue.values[index] : ""
                    cueData[column.name] = value
                }

                cues.append(cueData)
            }

            let webStackColumns = stackColumns.map { column in
                [
                    "id": column.id.uuidString,
                    "name": column.name,
                    "width": column.width,
                ] as [String: Any]
            }

            availableCueStacks.append([
                "id": stack.id.uuidString,
                "name": stack.name,
                "columns": webStackColumns,
                "cues": cues,
            ])
        }

        let primaryColumns = cueStacks.indices.contains(selectedCueStackIndex)
            ? cueStacks[selectedCueStackIndex].columns
            : (cueStacks.first?.columns ?? [])

        let webColumns = primaryColumns.map { column in
            [
                "id": column.id.uuidString,
                "name": column.name,
                "width": column.width,
            ] as [String: Any]
        }

        let webHighlightColors = settingsManager.settings.highlightColors.map { highlight in
            [
                "keyword": highlight.keyword,
                "color": highlight.color.toHex(),
            ] as [String: Any]
        }

        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let metadata: [String: Any] = [
            "filename": filename,
            "lastUpdated": formatter.string(from: now),
            "selectedCueStackIndex": selectedCueStackIndex,
            "totalCueStacks": cueStacks.count,
            "syncTimestamp": now.timeIntervalSince1970,
        ]

        return [
            "cueData": [
                "availableCueStacks": availableCueStacks,
                "allCues": availableCueStacks,
                "columns": webColumns,
                "highlightColors": webHighlightColors,
                "selectedCueStackIndex": selectedCueStackIndex,
            ],
            "metadata": metadata,
        ]
    }

    private func sendToGitHub(
        cueData: [String: Any],
        githubToken: String,
        repoOwner: String,
        repoName: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        updateGitHubFiles(
            cueData: cueData,
            githubToken: githubToken,
            repoOwner: repoOwner,
            repoName: repoName,
            completion: completion
        )
    }

    private func updateGitHubFiles(
        cueData: [String: Any],
        githubToken: String,
        repoOwner: String,
        repoName: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        // Update cue data first, then metadata — avoids reporting success when
        // parallel writes race on stale SHAs (GitHub 409).
        updateGitHubFile(
            path: "cuetocue/cuetocue-data.json",
            content: cueData["cueData"] as Any,
            githubToken: githubToken,
            repoOwner: repoOwner,
            repoName: repoName
        ) { cueSuccess, cueError in
            guard cueSuccess else {
                completion(false, cueError)
                return
            }

            self.updateGitHubFile(
                path: "cuetocue/metadata.json",
                content: cueData["metadata"] as Any,
                githubToken: githubToken,
                repoOwner: repoOwner,
                repoName: repoName
            ) { metadataSuccess, metadataError in
                completion(metadataSuccess, metadataError)
            }
        }
    }

    private func updateGitHubFile(
        path: String,
        content: Any,
        githubToken: String,
        repoOwner: String,
        repoName: String,
        retryCount: Int = 0,
        completion: @escaping (Bool, String?) -> Void
    ) {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/contents/\(path)")!

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: content, options: .prettyPrinted)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            let base64Content = Data(jsonString.utf8).base64EncodedString()

            getFileSHA(path: path, githubToken: githubToken, repoOwner: repoOwner, repoName: repoName) { sha in
                var payload: [String: Any] = [
                    "message": "Update \(path) from macOS app",
                    "content": base64Content,
                ]
                if let sha {
                    payload["sha"] = sha
                }

                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    URLSession.shared.dataTask(with: request) { data, response, error in
                        if let error {
                            completion(false, "Network error: \(error.localizedDescription)")
                            return
                        }

                        guard let httpResponse = response as? HTTPURLResponse else {
                            completion(false, "Invalid response")
                            return
                        }

                        switch httpResponse.statusCode {
                        case 200, 201:
                            completion(true, nil)
                        case 409 where retryCount < 3:
                            self.updateGitHubFile(
                                path: path,
                                content: content,
                                githubToken: githubToken,
                                repoOwner: repoOwner,
                                repoName: repoName,
                                retryCount: retryCount + 1,
                                completion: completion
                            )
                        case 409:
                            completion(false, "HTTP 409: Could not update \(path) — file changed on GitHub. Try syncing again.")
                        case 401:
                            var message = "HTTP 401: Authentication failed"
                            if let data,
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let apiMessage = json["message"] as? String {
                                message = "HTTP 401: \(apiMessage)"
                            }
                            completion(false, message)
                        default:
                            var message = "HTTP \(httpResponse.statusCode)"
                            if let data,
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let apiMessage = json["message"] as? String {
                                message = "HTTP \(httpResponse.statusCode): \(apiMessage)"
                            }
                            completion(false, message)
                        }
                    }.resume()
                } catch {
                    completion(false, "Failed to serialize request body: \(error.localizedDescription)")
                }
            }
        } catch {
            completion(false, "Failed to prepare content: \(error.localizedDescription)")
        }
    }

    private func getFileSHA(
        path: String,
        githubToken: String,
        repoOwner: String,
        repoName: String,
        completion: @escaping (String?) -> Void
    ) {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/contents/\(path)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                completion(nil)
                return
            }

            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sha = json["sha"] as? String {
                completion(sha)
            } else {
                completion(nil)
            }
        }.resume()
    }
}
