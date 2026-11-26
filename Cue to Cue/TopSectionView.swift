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
        // Label row + digits + button row; about 15% shorter than before so
        // the cue list gets the space.
        return fontSize + 70 + playlistExtra
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Timer displays in horizontal row
            currentTimeView
            countdownView(time: countdownTime, running: countdownRunning)
            countdownToTimeView()
            
            // Labeled tool buttons; each also has a menu item.
            VStack(spacing: 6) {
                ToolButton(title: "Viewers", systemImage: "network",
                           help: "Connected Viewers (Window menu)") {
                    showConnectionMonitor.toggle()
                }
                ToolButton(title: "Users", systemImage: "person.2",
                           help: "Users & Permissions (Window menu)") {
                    showUserManagement.toggle()
                }
                ToolButton(title: websiteSyncManager.isSyncing ? "Publishing" : "Publish",
                           systemImage: websiteSyncManager.isSyncing ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up",
                           help: "Publish to Website (\u{21E7}\u{2318}U)",
                           tint: websiteSyncManager.isSyncing ? .orange : nil) {
                    // Same path as File ▸ Publish to Website (handled in ContentView).
                    NotificationCenter.default.post(name: .appDelegatePublishWebsite, object: nil)
                }
                    .disabled(websiteSyncManager.isSyncing)
                    .overlay(syncNotificationOverlay, alignment: .topTrailing)
                ToolButton(title: "Settings", systemImage: "gearshape",
                           help: "Settings (\u{2318},)") {
                    showSettings.toggle()
                }
            }
            .frame(width: 104)
            .onChange(of: websiteSyncManager.syncStatus) { _, status in
                // Confirm a successful publish next to the button (failures
                // get an alert with a way into Website settings).
                if status == .success { showSyncSuccess() }
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
            VStack(spacing: 6) {
                panelLabel("Time of Day", detail: dateFormatter.string(from: currentTime))
                Spacer(minLength: 0)
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
            VStack(spacing: 6) {
                panelLabel("Countdown", detail: nil)
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

                HStack(spacing: 6) {
                    TimerButton(title: "Start", shortcutID: "countdownStart", isPrimary: !running, action: startCountdownTimer)
                    TimerButton(title: "Pause", shortcutID: "countdownPause", action: pauseCountdownTimer)
                    TimerButton(title: "Reset", shortcutID: "countdownReset", action: resetCountdownTimer)
                    TimerButton(title: "−1m", shortcutID: "countdownMinus1Min", action: { adjustCountdownTime(by: -60) })
                    TimerButton(title: "+1m", shortcutID: "countdownPlus1Min", action: { adjustCountdownTime(by: 60) })
                }
            }
        }
    }

    private func countdownToTimeView() -> some View {
        timeBox {
            VStack(spacing: 6) {
                panelLabel("To \(targetTimeString.isEmpty ? "00:00:00" : targetTimeString)", detail: currentPlaylistLabel)

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

                HStack(spacing: 6) {
                    TimerButton(title: "Start", shortcutID: "countdownToTimeStart", action: startCountdownToTime)
                    TimerButton(title: "Pause", shortcutID: "countdownToTimePause", action: pauseCountdownToTime, isEnabled: countUpRunning)
                    TimerButton(title: "Next", shortcutID: "countdownToTimeNext", action: nextPlaylistEntry, isEnabled: hasNextPlaylistEntry)
                    TimerButton(title: "Playlist", shortcutID: "countdownPlaylist", action: { showPlaylistEditor = true })
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

    private var currentPlaylistLabel: String? {
        let playlist = dataSyncManager.countdownPlaylist
        guard let idx = playlist.currentIndex, idx < playlist.entries.count,
              let label = playlist.entries[idx].label, !label.isEmpty else { return nil }
        return label
    }

    /// Small uppercase panel label with optional right-aligned detail.
    private func panelLabel(_ title: String, detail: String?) -> some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.0)
                .foregroundColor(.white.opacity(0.72))
            Spacer(minLength: 4)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .lineLimit(1)
    }

    private func timeBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
    /// Keyboard shortcut id to print on the button (from Shortcuts settings).
    var shortcutID: String? = nil
    /// Primary action gets the countdown color as its fill.
    var isPrimary: Bool = false
    let action: () -> Void
    var isEnabled: Bool = true
    @EnvironmentObject var settingsManager: SettingsManager

    private var shortcut: String? {
        shortcutID.flatMap { settingsManager.shortcutsManager.displayString(for: $0) }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .opacity(0.6)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .foregroundColor(foreground)
            .padding(.horizontal, 9)
            .frame(minHeight: 26)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
    }

    private var foreground: Color {
        if isPrimary && isEnabled { return Color.black.opacity(0.85) }
        return isEnabled ? settingsManager.settings.fontColor : settingsManager.settings.fontColor.opacity(0.4)
    }

    private var background: Color {
        if isPrimary && isEnabled { return settingsManager.settings.countdownColor }
        return settingsManager.settings.backgroundColor.opacity(isEnabled ? 0.45 : 0.18)
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



// MARK: - Tool button

/// Icon + label button for the column beside the clocks.
struct ToolButton: View {
    let title: String
    let systemImage: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(tint ?? settingsManager.settings.fontColor)
            .opacity(isEnabled ? 1 : 0.7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(settingsManager.settings.backgroundColor.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(title))
    }
}
