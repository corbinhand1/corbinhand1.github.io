//
//  TopSectionView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/12/24.
//



import SwiftUI
import AppKit

// MARK: - Temporary WebsiteSyncSettingsView (until added to Xcode project)

struct WebsiteSyncSettingsView: View {
    @State private var githubToken: String = ""
    @State private var autoSyncEnabled: Bool = false
    @State private var showTokenField: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // GitHub Configuration Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("GitHub Configuration")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GitHub Token")
                            .font(.headline)
                        
                        if showTokenField {
                            VStack(spacing: 8) {
                                TextField("Enter your GitHub token", text: $githubToken)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .onChange(of: githubToken) {
                                        saveSettings()
                                    }
                                
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
                            Button(action: {
                                showTokenField = true
                            }) {
                                HStack {
                                    Image(systemName: "key.fill")
                                    Text("Click to enter GitHub token")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                            }
                        }
                        
                        if !githubToken.isEmpty {
                            Text("✅ Token configured")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Get a token from:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Link("https://github.com/settings/tokens", destination: URL(string: "https://github.com/settings/tokens")!)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Divider()
                
                // Sync Options Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sync Options")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Auto-sync when cue data changes", isOn: $autoSyncEnabled)
                            .onChange(of: autoSyncEnabled) {
                                saveSettings()
                            }
                        
                        Text("Auto-sync will automatically send cue data to your website when you open or edit cue files.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Divider()
                
                // Manual Sync Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Manual Sync")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Button("Sync Now") {
                        // Manual sync would go here
                    }
                    .disabled(githubToken.isEmpty)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(githubToken.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                    .foregroundColor(githubToken.isEmpty ? .gray : .white)
                    .cornerRadius(8)
                }
                
                // Status Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Status")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Configuration Status:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Image(systemName: githubToken.isEmpty ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundColor(githubToken.isEmpty ? .red : .green)
                            Text(githubToken.isEmpty ? "GitHub token required" : "Ready to sync")
                                .font(.caption)
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        githubToken = UserDefaults.standard.string(forKey: "githubToken") ?? ""
        autoSyncEnabled = UserDefaults.standard.bool(forKey: "autoSyncEnabled")
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(githubToken, forKey: "githubToken")
        UserDefaults.standard.set(autoSyncEnabled, forKey: "autoSyncEnabled")
    }
}

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.presentationMode) var presentationMode

    @State private var newKeyword: String = ""
    @State private var newColor: Color = .white

    var body: some View {
        VStack {
            Text("Settings")
                .font(.title)
                .bold()
                .padding()

            TabView {
                // General settings tab
                Form {
                    HStack {
                        Text("Font Size")
                        Slider(value: $settingsManager.settings.fontSize, in: 10...24, step: 1)
                    }
                    .padding()
                    ColorPicker("Font Color", selection: $settingsManager.settings.fontColor)
                        .padding()
                    ColorPicker("Window Background Color", selection: $settingsManager.settings.backgroundColor)
                        .padding()
                    ColorPicker("Row Background Color", selection: $settingsManager.settings.tableBackgroundColor)
                        .padding()
                }
                .tabItem {
                    Text("General")
                }

                // Timer settings tab
                Form {
                    HStack {
                        Text("Clock Font Size")
                        Slider(value: $settingsManager.settings.clockFontSize, in: 70...90, step: 2)
                            .padding(.horizontal)
                    }
                    .padding()
                    
                    ColorPicker("Date and Time Color", selection: $settingsManager.settings.dateTimeColor)
                        .padding()
                    
                    ColorPicker("Countdown Color", selection: $settingsManager.settings.countdownColor)
                        
                    
                    Toggle(isOn: $settingsManager.settings.stopAtZero) {
                        Text("Stop at Zero")
                    }
                    .padding()
                }
                .tabItem {
                    Text("Clock & Timers")
                }

                // Row Highlights settings tab
                Form {
                    ForEach($settingsManager.settings.highlightColors) { $highlightColor in
                        HStack {
                            TextField("Keyword", text: $highlightColor.keyword)
                            ColorPicker("Color", selection: $highlightColor.color)
                        }
                        .padding()
                    }
                    HStack {
                        TextField("New Keyword", text: $newKeyword)
                        ColorPicker("Color", selection: $newColor)
                        Button(action: addNewHighlightColor) {
                            Text("Add")
                        }
                    }
                    .padding()
                }
                .tabItem {
                    Text("Row Text Highlight")
                }
                
                // Website Sync settings tab
                WebsiteSyncSettingsView()
                    .tabItem {
                        Text("Website Sync")
                    }
            }

            Spacer()
            Button("Close") {
                presentationMode.wrappedValue.dismiss()
            }
            .padding()
        }
        .padding()
        .frame(width: 500)
    }

    private func addNewHighlightColor() {
        guard !newKeyword.isEmpty else { return }
        let newHighlightColor = HighlightColorSetting(keyword: newKeyword, color: newColor)
        settingsManager.settings.highlightColors.append(newHighlightColor)
        newKeyword = ""
        newColor = .white
    }
}
