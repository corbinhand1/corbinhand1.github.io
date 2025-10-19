//
//  WebsiteSyncSettingsView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 1/15/25.
//

import SwiftUI

struct WebsiteSyncSettingsView: View {
    @StateObject private var syncManager = WebsiteSyncManager()
    @State private var githubToken: String = ""
    @State private var autoSyncEnabled: Bool = false
    @State private var showTokenAlert: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("GitHub Configuration")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GitHub Token")
                            .font(.headline)
                        
                        SecureField("Enter your GitHub token", text: $githubToken)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Text("Get a token from: https://github.com/settings/tokens")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Required permissions: 'repo' (Full control of private repositories)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Sync Options")) {
                    Toggle("Auto-sync when cue data changes", isOn: $autoSyncEnabled)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-sync will automatically send cue data to your website when:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("• You open a new cue file")
                        Text("• You edit cue data")
                        Text("• You switch between cue stacks")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Section(header: Text("Sync Status")) {
                    HStack {
                        Text("Last Sync:")
                        Spacer()
                        if let lastSync = syncManager.lastSyncTime {
                            Text(lastSync, style: .relative)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Never")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Last File:")
                        Spacer()
                        Text(syncManager.lastSyncFilename ?? "None")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Status:")
                        Spacer()
                        syncStatusView
                    }
                }
                
                Section(header: Text("Manual Sync")) {
                    Button("Sync Now") {
                        // This would trigger a manual sync
                        // You'll need to pass the current cue data
                        syncManager.syncCueData(
                            cueStacks: [], // Pass actual cue stacks
                            selectedCueStackIndex: 0,
                            filename: "Manual Sync"
                        )
                    }
                    .disabled(syncManager.isSyncing || githubToken.isEmpty)
                }
            }
            .navigationTitle("Website Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                    .disabled(githubToken.isEmpty)
                }
            }
            .onAppear {
                loadSettings()
            }
        }
    }
    
    @ViewBuilder
    private var syncStatusView: some View {
        switch syncManager.syncStatus {
        case .idle:
            Text("Ready")
                .foregroundColor(.secondary)
        case .syncing:
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Syncing...")
                    .foregroundColor(.blue)
            }
        case .success:
            Text("Success")
                .foregroundColor(.green)
        case .failed(let error):
            Text("Failed: \(error)")
                .foregroundColor(.red)
        }
    }
    
    private func loadSettings() {
        githubToken = syncManager.githubTokenFromSettings ?? ""
        autoSyncEnabled = syncManager.isAutoSyncEnabled
    }
    
    private func saveSettings() {
        syncManager.configure(githubToken: githubToken, autoSyncEnabled: autoSyncEnabled)
    }
}

#Preview {
    WebsiteSyncSettingsView()
}


