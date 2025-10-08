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
    @EnvironmentObject var settingsManager: SettingsManager
    var updateWebClients: () -> Void

    // For editing the regular countdown time in a TextField
    @State private var isEditingCountdown = false
    @State private var editableCountdownTime = ""

    // Instead of tracking a start date plus elapsed seconds,
    // we track an absolute target date for the regular countdown.
    @State private var countdownTargetDate: Date? = nil

    var body: some View {
        HStack(spacing: 20) {
            currentTimeView
            countdownView(time: countdownTime, running: countdownRunning)
            countdownToTimeView()
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
            // Initialize countdown to time with default 10:00:00
            if let date = parseAsTodayTime(targetTimeString) {
                targetDate = date
            }
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
            } else {
                countdownTargetDate = nil
            }
        }
    }

    // MARK: - Timer Tick

    private func tick() {
        let now = Date()
        // Regular countdown based on absolute target date.
        if countdownRunning, let target = countdownTargetDate {
            let remaining = target.timeIntervalSince(now)
            let newCountdown = max(0, Int(round(remaining)))
            if countdownTime != newCountdown {
                countdownTime = newCountdown
                if newCountdown <= 0 {
                    countdownRunning = false
                    countdownTargetDate = nil
                }
                updateWebClients()
            }
        }
        // Countdown-to-time update.
        var newCountUpTime = countUpTime
        if countUpRunning, let tDate = targetDate {
            let diff = tDate.timeIntervalSince(now)
            if diff <= 0 {
                newCountUpTime = 0
                countUpRunning = false
            } else {
                newCountUpTime = Int(round(diff))
            }
        }
        if countUpTime != newCountUpTime {
            countUpTime = newCountUpTime
            updateWebClients()
        }
        // Update current time display.
        if currentTime != now {
            currentTime = now
            updateWebClients()
        }
    }

    // MARK: - Regular Countdown Controls

    private func startCountdownTimer() {
        // Set countdownRunning to true so that tick() will update the timer.
        countdownRunning = true
        // Set an absolute target date for the regular countdown.
        countdownTargetDate = Date().addingTimeInterval(TimeInterval(countdownTime))
        updateWebClients()
    }

    private func pauseCountdownTimer() {
        countdownRunning = false
        countdownTargetDate = nil
        updateWebClients()
    }

    private func resetCountdownTimer() {
        countdownRunning = false
        countdownTime = 0
        countdownTargetDate = nil
        updateWebClients()
    }

    /// Resets the regular countdown when a new cue timer is selected.
    private func resetCountdown(with newTime: Int) {
        countdownRunning = false
        countdownTime = newTime
        countdownTargetDate = Date().addingTimeInterval(TimeInterval(newTime))
        countdownRunning = true
        updateWebClients()
    }

    private func adjustCountdownTime(by seconds: Int) {
        let newTime = max(0, countdownTime + seconds)
        countdownTime = newTime
        if countdownRunning {
            countdownTargetDate = Date().addingTimeInterval(TimeInterval(newTime))
        }
        updateWebClients()
    }

    // MARK: - “Countdown to Time” Controls

    private func startCountdownToTime() {
        guard let tDate = targetDate else { return }
        countUpRunning = true
        // Initialize countUpTime immediately.
        countUpTime = max(0, Int(round(tDate.timeIntervalSince(Date()))))
        updateWebClients()
    }

    private func pauseCountdownToTime() {
        countUpRunning = false
        updateWebClients()
    }

    private func resetCountdownToTime() {
        countUpRunning = false
        countUpTime = 0
        targetDate = nil
        targetTimeString = "10:00:00"
        // Re-initialize target date
        if let date = parseAsTodayTime(targetTimeString) {
            targetDate = date
        }
        updateWebClients()
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
                            countdownTime = newTime
                            if countdownRunning {
                                startCountdownTimer()
                            }
                            updateWebClients()
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
                        if let date = parseAsTodayTime(targetTimeString) {
                            targetDate = date
                        } else {
                            targetDate = nil
                            countUpTime = 0
                        }
                        isEditingCountdownToTime = false
                        updateWebClients()
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
