//
//  WebsiteSyncSettingsView.swift
//  Cue to Cue
//

import SwiftUI
import AppKit

struct WebsiteSyncSettingsView: View {
    @EnvironmentObject private var websiteSyncManager: WebsiteSyncManager

    @State private var githubToken: String = ""
    @State private var repoOwner: String = WebsiteSyncSettingsKeys.defaultRepoOwner
    @State private var repoName: String = WebsiteSyncSettingsKeys.defaultRepoName
    @State private var autoSyncEnabled: Bool = false
    @State private var showTokenField: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                githubSection
                Divider()
                repositorySection
                Divider()
                syncOptionsSection
                Divider()
                statusSection
            }
            .padding()
        }
        .onAppear(perform: loadSettings)
    }

    private var githubSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub Configuration")
                .font(.title2)
                .fontWeight(.semibold)

            Text("GitHub Token")
                .font(.headline)

            if showTokenField {
                VStack(spacing: 8) {
                    SecureField("Enter your GitHub token", text: $githubToken)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: githubToken) { saveSettings() }

                    HStack {
                        Button("Paste from Clipboard") {
                            if let clipboardContent = NSPasteboard.general.string(forType: .string) {
                                githubToken = clipboardContent
                                saveSettings()
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Clear") {
                            githubToken = ""
                            saveSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Button {
                    showTokenField = true
                } label: {
                    HStack {
                        Image(systemName: "key.fill")
                        Text(githubToken.isEmpty ? "Click to enter GitHub token" : "Token configured — click to edit")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            if !githubToken.isEmpty {
                Text("Token saved")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Link("Create a token at github.com/settings/tokens", destination: URL(string: "https://github.com/settings/tokens")!)
                .font(.caption)
        }
    }

    private var repositorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repository")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Owner (username or org)", text: $repoOwner)
                .textFieldStyle(.roundedBorder)
                .onChange(of: repoOwner) { saveSettings() }

            TextField("Repository name", text: $repoName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: repoName) { saveSettings() }

            Text("Files are written to cuetocue/cuetocue-data.json and cuetocue/metadata.json in this repo.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var syncOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync Options")
                .font(.title2)
                .fontWeight(.semibold)

            Toggle("Auto-sync when cue data changes", isOn: $autoSyncEnabled)
                .onChange(of: autoSyncEnabled) { saveSettings() }

            Text("Auto-sync runs when you open or edit a show file. Use the cloud button in the toolbar for manual sync.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.title2)
                .fontWeight(.semibold)

            HStack {
                Text("Configuration")
                Spacer()
                Label(
                    githubToken.isEmpty ? "Token required" : "Ready",
                    systemImage: githubToken.isEmpty ? "xmark.circle.fill" : "checkmark.circle.fill"
                )
                .foregroundColor(githubToken.isEmpty ? .red : .green)
                .font(.caption)
            }

            HStack {
                Text("Last sync")
                Spacer()
                if let lastSync = websiteSyncManager.lastSyncTime {
                    Text(lastSync, style: .relative)
                        .foregroundColor(.secondary)
                } else {
                    Text("Never")
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Last file")
                Spacer()
                Text(websiteSyncManager.lastSyncFilename ?? "None")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Sync state")
                Spacer()
                syncStatusLabel
            }
        }
    }

    @ViewBuilder
    private var syncStatusLabel: some View {
        switch websiteSyncManager.syncStatus {
        case .idle:
            Text("Ready").foregroundColor(.secondary)
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Syncing…").foregroundColor(.blue)
            }
        case .success:
            Text("Success").foregroundColor(.green)
        case .failed(let error):
            Text(error)
                .foregroundColor(.red)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    private func loadSettings() {
        let config = websiteSyncManager.loadConfiguration()
        githubToken = config.githubToken
        repoOwner = config.repoOwner
        repoName = config.repoName
        autoSyncEnabled = config.autoSyncEnabled
        showTokenField = !githubToken.isEmpty
    }

    private func saveSettings() {
        websiteSyncManager.saveConfiguration(
            githubToken: githubToken,
            repoOwner: repoOwner.trimmingCharacters(in: .whitespacesAndNewlines),
            repoName: repoName.trimmingCharacters(in: .whitespacesAndNewlines),
            autoSyncEnabled: autoSyncEnabled
        )
    }
}
