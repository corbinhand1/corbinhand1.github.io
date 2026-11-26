//
//  TopSectionView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/12/24.
//

import SwiftUI

struct TopSectionView: View {
    /// Observed here (not in ContentView) so timer ticks redraw only this
    /// header, not the whole window and cue table.
    @ObservedObject var timerServer: AuthoritativeTimerServer
    private var currentTime: Date { timerServer.currentTime }
    private var countdownTime: Int { timerServer.countdownTime }
    private var countdownRunning: Bool { timerServer.countdownRunning }
    private var countUpTime: Int { timerServer.countUpTime }
    private var countUpRunning: Bool { timerServer.countUpRunning }

    // "Countdown to a specific time" states:
    @State private var targetTimeString: String = "10:00:00"
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
        let playlistExtra: CGFloat = dataSyncManager.countdownPlaylist.entries.isEmpty ? 0 : 26
        return fontSize + 96 + playlistExtra
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.8))
        .cornerRadius(20)
        .shadow(color: settingsManager.settings.fontColor.opacity(0.3), radius: 10, x: 0, y: 5)
        .onAppear {
            updateTargetTimeString()
        }
        // Listen for the custom reset notification from ContentView.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ResetCountdown"))) { notification in
            if let newTime = notification.object as? Int {
                resetCountdown(with: newTime)
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
            VStack(spacing: 8) {
                Spacer(minLength: 0)

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

                Spacer(minLength: 0)
            }
        }
    }

    private func countdownView(time: Int, running: Bool) -> some View {
        timeBox {
            VStack(spacing: 8) {
                Text("Countdown")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                Spacer(minLength: 0)

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

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    TimerButton(title: "Start", action: startCountdownTimer)
                    TimerButton(title: "Pause", action: pauseCountdownTimer)
                    TimerButton(title: "Reset", action: resetCountdownTimer)
                    TimerButton(title: "-1 min", action: { adjustCountdownTime(by: -60) })
                    TimerButton(title: "+1 min", action: { adjustCountdownTime(by: 60) })
                }
            }
        }
    }

    private func countdownToTimeView() -> some View {
        timeBox {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("Countdown to \(targetTimeString.isEmpty ? "00:00:00" : targetTimeString)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    if let currentIdx = dataSyncManager.countdownPlaylist.currentIndex,
                       currentIdx < dataSyncManager.countdownPlaylist.entries.count,
                       let label = dataSyncManager.countdownPlaylist.entries[currentIdx].label,
                       !label.isEmpty {
                        Text("— \(label)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .lineLimit(1)

                Spacer(minLength: 0)

                if isEditingCountdownToTime {
                    VStack(spacing: 4) {
                        TextField("HH:mm:ss", text: $targetTimeString, onCommit: {
                            if let currentIdx = dataSyncManager.countdownPlaylist.currentIndex,
                               currentIdx < dataSyncManager.countdownPlaylist.entries.count {
                                let currentEntry = dataSyncManager.countdownPlaylist.entries[currentIdx]
                                dataSyncManager.updatePlaylistEntry(
                                    at: currentIdx,
                                    timeString: targetTimeString,
                                    label: currentEntry.label
                                )
                                timerServer.syncPlaylistState(dataSyncManager.countdownPlaylist)
                            }

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
                            if let currentIdx = dataSyncManager.countdownPlaylist.currentIndex,
                               currentIdx < dataSyncManager.countdownPlaylist.entries.count {
                                targetTimeString = dataSyncManager.countdownPlaylist.entries[currentIdx].timeString
                            } else {
                                updateTargetTimeString()
                                if targetTimeString.isEmpty {
                                    targetTimeString = "10:00:00"
                                }
                            }
                            isEditingCountdownToTime = true
                        }
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    TimerButton(title: "Start", action: startCountdownToTime)
                    TimerButton(title: "Pause", action: pauseCountdownToTime, isEnabled: countUpRunning)
                    TimerButton(title: "Next", action: nextPlaylistEntry, isEnabled: hasNextPlaylistEntry)
                    TimerButton(title: "Playlist", action: { showPlaylistEditor = true })
                }

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
                    .frame(height: 22)
                }
            }
        }
    }

    private var settingsButton: some View {
        Button(action: { showSettings.toggle() }) {
            Image(systemName: "gear")
                .resizable()
                .accessibilityLabel(Text("Settings"))
                .help("Settings")
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(settingsManager.settings.fontColor)
        }
    }
    
    private var networkButton: some View {
        Button(action: { showConnectionMonitor.toggle() }) {
            Image(systemName: "network")
                .resizable()
                .accessibilityLabel(Text("Connected Viewers"))
                .help("Connected Viewers")
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(settingsManager.settings.fontColor)
        }
    }
    
    private var userManagementButton: some View {
        Button(action: { showUserManagement.toggle() }) {
            Image(systemName: "person.2")
                .resizable()
                .accessibilityLabel(Text("User Management"))
                .help("User Management")
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(settingsManager.settings.fontColor)
        }
    }
    
    private var syncButton: some View {
        Button(action: {
            // Commit any in-progress cell edit before publishing.
            NSApp.keyWindow?.makeFirstResponder(nil)

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
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: clockPanelHeight, maxHeight: clockPanelHeight)
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
            .contentShape(Rectangle())
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

