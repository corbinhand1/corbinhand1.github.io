//
//  TopSectionView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/12/24.
//

import SwiftUI

struct TopSectionView: View {
    @Binding var currentTime: Date
    @Binding var countdownTime: Int
    @Binding var countdownRunning: Bool
    @Binding var countUpTime: Int
    @Binding var countUpRunning: Bool

    // "Countdown to a specific time" states:
    @State private var targetTimeString: String = "10:00:00"
    @State private var targetDate: Date? = nil
    @State private var isEditingCountdownToTime = false

    @Binding var showSettings: Bool
    @Binding var showConnectionMonitor: Bool
    @Binding var showUserManagement: Bool
    @EnvironmentObject var settingsManager: SettingsManager
    var updateWebClients: () -> Void
    
    // Reference to DataSyncManager for timer commands
    @EnvironmentObject var dataSyncManager: DataSyncManager

    // For editing the regular countdown time in a TextField
    @State private var isEditingCountdown = false
    @State private var editableCountdownTime = ""

    var body: some View {
        HStack(spacing: 20) {
            currentTimeView
            countdownView(time: countdownTime, running: countdownRunning)
            countdownToTimeView()
            networkButton
            userManagementButton
            settingsButton
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(20)
        .shadow(color: settingsManager.settings.fontColor.opacity(0.3), radius: 10, x: 0, y: 5)
        // Update frequently for accuracy.
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            tick()
        }
        .onAppear {
            if countdownRunning {
                startCountdownTimer()
            }
            // Get target time string from server
            targetTimeString = dataSyncManager.timerServer.getTargetTimeString()
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
    }

    // MARK: - Timer Tick (Now just updates UI bindings)

    private func tick() {
        // Timer calculations are now handled by AuthoritativeTimerServer
        // This function just updates the UI bindings from the timer server
        let timerState = dataSyncManager.timerServer
        
        // Update bindings to reflect timer server state
        if currentTime != timerState.currentTime {
            currentTime = timerState.currentTime
        }
        
        if countdownTime != timerState.countdownTime {
            countdownTime = timerState.countdownTime
        }
        
        if countUpTime != timerState.countUpTime {
            countUpTime = timerState.countUpTime
        }
        
        if countdownRunning != timerState.countdownRunning {
            countdownRunning = timerState.countdownRunning
        }
        
        if countUpRunning != timerState.countUpRunning {
            countUpRunning = timerState.countUpRunning
        }
        
        // Update target time string from server
        let serverTargetTime = timerState.getTargetTimeString()
        if targetTimeString != serverTargetTime {
            targetTimeString = serverTargetTime
        }
        
        // Update web clients with current state
        updateWebClients()
    }

    // MARK: - Regular Countdown Controls (Now delegate to AuthoritativeTimerServer)

    private func startCountdownTimer() {
        let command = TimerCommand(action: "start", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        dataSyncManager.executeTimerCommand(command)
    }

    private func pauseCountdownTimer() {
        let command = TimerCommand(action: "pause", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        dataSyncManager.executeTimerCommand(command)
    }

    private func resetCountdownTimer() {
        let command = TimerCommand(action: "reset", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        dataSyncManager.executeTimerCommand(command)
    }

    /// Resets the regular countdown when a new cue timer is selected.
    private func resetCountdown(with newTime: Int) {
        dataSyncManager.resetCountdown(with: newTime)
    }

    private func adjustCountdownTime(by seconds: Int) {
        let command = TimerCommand(action: "adjust", countdownTime: nil, countUpTime: nil, adjustment: seconds, targetTimeString: nil)
        dataSyncManager.executeTimerCommand(command)
    }

    // MARK: - "Countdown to Time" Controls (Now delegate to AuthoritativeTimerServer)

    private func startCountdownToTime() {
        let command = TimerCommand(action: "startCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        dataSyncManager.executeTimerCommand(command)
    }

    private func pauseCountdownToTime() {
        let command = TimerCommand(action: "pauseCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        dataSyncManager.executeTimerCommand(command)
    }

    private func resetCountdownToTime() {
        let command = TimerCommand(action: "resetCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        dataSyncManager.executeTimerCommand(command)
    }

    // MARK: - Subviews

    private var currentTimeView: some View {
        timeBox {
            VStack(alignment: .center, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(dateFormatter.string(from: currentTime).uppercased())
                        .font(.custom("Digital-7Mono", size: settingsManager.settings.clockFontSize * 0.4))
                        .foregroundColor(settingsManager.settings.dateTimeColor)
                }
                Spacer()
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
                            dataSyncManager.executeTimerCommand(command)
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
            VStack(alignment: .center, spacing: 5) {
                Text("Countdown to \(targetTimeString.isEmpty ? "00:00:00" : targetTimeString)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                if isEditingCountdownToTime {
                    TextField("HH:mm:ss", text: $targetTimeString, onCommit: {
                        let command = TimerCommand(action: "setCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: targetTimeString)
                        dataSyncManager.executeTimerCommand(command)
                        isEditingCountdownToTime = false
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 150)
                    .multilineTextAlignment(.center)
                } else {
                    Text(timeString(time: countUpTime, isRunning: countUpRunning))
                        .font(.custom("Digital-7Mono", size: settingsManager.settings.clockFontSize))
                        .foregroundColor(settingsManager.settings.countdownColor)
                        .onTapGesture {
                            targetTimeString = targetTimeString.isEmpty ? "10:00:00" : targetTimeString
                            isEditingCountdownToTime = true
                        }
                }
                HStack(spacing: 10) {
                    TimerButton(title: "Start", action: startCountdownToTime)
                    TimerButton(title: "Pause", action: pauseCountdownToTime)
                    TimerButton(title: "Reset", action: resetCountdownToTime)
                }
            }
        }
    }

    private var settingsButton: some View {
        Button(action: { showSettings.toggle() }) {
            Image(systemName: "gear")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundColor(settingsManager.settings.fontColor)
        }
    }
    
    private var networkButton: some View {
        Button(action: { showConnectionMonitor.toggle() }) {
            Image(systemName: "network")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundColor(settingsManager.settings.fontColor)
        }
    }
    
    private var userManagementButton: some View {
        Button(action: { showUserManagement.toggle() }) {
            Image(systemName: "person.2")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundColor(settingsManager.settings.fontColor)
        }
    }

    // MARK: - Utility Methods

    private func timeBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: 125)
            .padding()
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
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(settingsManager.settings.fontColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .background(settingsManager.settings.backgroundColor.opacity(0.3))
        .cornerRadius(8)
    }
}
