//
//  PlaylistEditorView.swift
//  Cue to Cue
//
//  Timer ▸ Edit Playlist…: the list of clock times the "countdown to time"
//  clock runs to, one after another.
//

import SwiftUI

struct PlaylistEditorView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataSyncManager: DataSyncManager
    @EnvironmentObject var timerServer: AuthoritativeTimerServer

    /// Edits are made on a copy and applied on Save.
    @State private var playlist = CountdownPlaylist()
    @State private var hasLoaded = false

    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(systemImage: "clock.badge.checkmark",
                        title: "Countdown to Time",
                        subtitle: "The clock counts down to each time in this list in turn, moving to the next one when it reaches zero.",
                        tint: .orange)
            Form {
                scheduleSection
                optionsSection
            }
            .formStyle(.grouped)
            footer
        }
        .frame(width: 620, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            playlist = dataSyncManager.countdownPlaylist
            if playlist.currentIndex == nil, !playlist.entries.isEmpty { playlist.currentIndex = 0 }
        }
    }

    // MARK: Schedule

    private var scheduleSection: some View {
        Section {
            if playlist.entries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No times yet").fontWeight(.medium)
                    Text("Add the times your show runs to, such as Doors, Walk-in and Show Start.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            ForEach(Array(playlist.entries.enumerated()), id: \.element.id) { index, entry in
                PlaylistEntryRow(
                    entry: $playlist.entries[index],
                    position: index + 1,
                    isCurrent: playlist.currentIndex == index,
                    canMoveUp: index > 0,
                    canMoveDown: index < playlist.entries.count - 1,
                    onMakeCurrent: { playlist.currentIndex = index },
                    onMove: { move(from: index, by: $0) },
                    onDelete: { delete(at: index) }
                )
            }
            .onMove(perform: moveEntries)

            Button {
                addEntry()
            } label: {
                Label("Add Time", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
        } header: {
            HStack {
                Text("Schedule")
                Spacer()
                if !isInTimeOrder {
                    Button("Sort by Time", action: sortByTime)
                        .controlSize(.small)
                        .help("Put the times in clock order")
                }
            }
        } footer: {
            if !isInTimeOrder {
                Label("These times aren't in clock order, so the countdown will jump around. Sort them, or drag to reorder.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Text("Times use this Mac's clock. A time that has already passed today counts down to tomorrow.")
            }
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle("Start again from the first time after the last", isOn: $playlist.loopPlaylist)
        } header: {
            Text("After the Last Time")
        } footer: {
            Text(playlist.loopPlaylist
                 ? "After the last time, the countdown goes back to the first one."
                 : "After the last time, the countdown stops.")
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                // ⌘Return, not Return: Return while typing a label or time
                // must only finish that field, not save and close.
                Button("Save", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .help("Save (\u{2318}Return)")
                    .disabled(playlist.entries.isEmpty)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private var summary: String {
        let count = playlist.entries.count
        guard count > 0 else { return "Add at least one time to save." }
        let current = playlist.currentIndex.map { playlist.entries.indices.contains($0) ? " · current: \(entryName(playlist.entries[$0]))" : "" } ?? ""
        return "\(count) time\(count == 1 ? "" : "s")\(current)"
    }

    private func entryName(_ entry: PlaylistEntry) -> String {
        if let label = entry.label, !label.isEmpty { return label }
        return PlaylistTime.display(entry.timeString)
    }

    // MARK: Editing

    private var isInTimeOrder: Bool {
        let seconds = playlist.entries.compactMap { PlaylistTime.secondsOfDay($0.timeString) }
        return zip(seconds, seconds.dropFirst()).allSatisfy { $0 <= $1 }
    }

    private func addEntry() {
        // Suggest 30 minutes after the last time, or the next half hour.
        let base: Int
        if let last = playlist.entries.last.flatMap({ PlaylistTime.secondsOfDay($0.timeString) }) {
            base = (last + 30 * 60) % 86_400
        } else {
            let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let minutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
            base = ((minutes / 30 + 1) * 30 % 1440) * 60
        }
        playlist.entries.append(PlaylistEntry(timeString: PlaylistTime.string(fromSecondsOfDay: base)))
        if playlist.currentIndex == nil { playlist.currentIndex = 0 }
    }

    private func delete(at index: Int) {
        guard playlist.entries.indices.contains(index) else { return }
        playlist.entries.remove(at: index)
        if let current = playlist.currentIndex {
            if playlist.entries.isEmpty {
                playlist.currentIndex = nil
            } else if index < current {
                playlist.currentIndex = current - 1
            } else if index == current {
                playlist.currentIndex = min(current, playlist.entries.count - 1)
            }
        }
    }

    private func move(from index: Int, by step: Int) {
        let target = index + step
        guard playlist.entries.indices.contains(target) else { return }
        moveEntries(from: IndexSet(integer: index), to: step > 0 ? target + 1 : target)
    }

    private func moveEntries(from source: IndexSet, to destination: Int) {
        let currentID = playlist.currentIndex.flatMap { playlist.entries.indices.contains($0) ? playlist.entries[$0].id : nil }
        playlist.entries.move(fromOffsets: source, toOffset: destination)
        if let currentID { playlist.currentIndex = playlist.entries.firstIndex { $0.id == currentID } }
    }

    private func sortByTime() {
        let currentID = playlist.currentIndex.flatMap { playlist.entries.indices.contains($0) ? playlist.entries[$0].id : nil }
        playlist.entries.sort { (PlaylistTime.secondsOfDay($0.timeString) ?? 0) < (PlaylistTime.secondsOfDay($1.timeString) ?? 0) }
        if let currentID { playlist.currentIndex = playlist.entries.firstIndex { $0.id == currentID } }
    }

    private func save() {
        guard !playlist.entries.isEmpty else { return }
        var saved = playlist
        saved.isActive = true   // the playlist is the only countdown-to-time mode
        if let index = saved.currentIndex, !saved.entries.indices.contains(index) { saved.currentIndex = 0 }
        for i in saved.entries.indices {
            let label = saved.entries[i].label?.trimmingCharacters(in: .whitespaces) ?? ""
            saved.entries[i].label = label.isEmpty ? nil : label
        }

        dataSyncManager.countdownPlaylist = saved
        timerServer.syncPlaylistState(saved)
        if let index = saved.currentIndex {
            timerServer.executeCommand(TimerCommand(action: "setCountdownToTime", countdownTime: nil, countUpTime: nil,
                                                    adjustment: nil, targetTimeString: saved.entries[index].timeString))
        }
        isPresented = false
    }
}

// MARK: - Row

private struct PlaylistEntryRow: View {
    @Binding var entry: PlaylistEntry
    let position: Int
    let isCurrent: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMakeCurrent: () -> Void
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Text("CURRENT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .foregroundStyle(.black.opacity(0.85))
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("\(position)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 62, alignment: .leading)

            TimeOfDayField(date: timeBinding)
                .fixedSize()
                .accessibilityLabel(Text("Time for item \(position)"))

            TextField("Label", text: labelBinding, prompt: Text("Label, e.g. Doors"))
                .onSubmit { NSApp.keyWindow?.makeFirstResponder(nil) }
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text("Label for item \(position)"))

            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(PlaylistTime.relativeDescription(entry.timeString, now: context.date))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .trailing)
            }

            Menu {
                Button("Make Current", action: onMakeCurrent).disabled(isCurrent)
                Divider()
                Button("Move Up") { onMove(-1) }.disabled(!canMoveUp)
                Button("Move Down") { onMove(1) }.disabled(!canMoveDown)
                Divider()
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("Actions for item \(position)"))
        }
        .padding(.vertical, 2)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { PlaylistTime.date(from: entry.timeString) },
            set: { entry.timeString = PlaylistTime.string(from: $0) }
        )
    }

    private var labelBinding: Binding<String> {
        Binding(get: { entry.label ?? "" }, set: { entry.label = $0 })
    }
}

// MARK: - Time field

/// Native hours:minutes:seconds field with stepper (SwiftUI's DatePicker
/// can't show seconds on macOS). Follows the Mac's 12/24-hour setting.
private struct TimeOfDayField: NSViewRepresentable {
    @Binding var date: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinuteSecond
        picker.isBezeled = true
        picker.drawsBackground = true
        picker.dateValue = date
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        if picker.dateValue != date { picker.dateValue = date }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: TimeOfDayField
        init(_ parent: TimeOfDayField) { self.parent = parent }
        @objc func changed(_ sender: NSDatePicker) { parent.date = sender.dateValue }
    }
}

// MARK: - Time helpers

/// Playlist times are stored as 24-hour "HH:mm:ss" strings (the timer and
/// web viewer read them that way); the editor shows them with a time picker.
enum PlaylistTime {
    static func secondsOfDay(_ string: String) -> Int? {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]), (0..<60).contains(parts[2]) else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    static func string(fromSecondsOfDay seconds: Int) -> String {
        let s = ((seconds % 86_400) + 86_400) % 86_400
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }

    static func date(from string: String, on day: Date = Date()) -> Date {
        let start = Calendar.current.startOfDay(for: day)
        return start.addingTimeInterval(TimeInterval(secondsOfDay(string) ?? 0))
    }

    static func string(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return string(fromSecondsOfDay: (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0))
    }

    /// Time in the user's preferred 12/24-hour style.
    static func display(_ string: String) -> String {
        date(from: string).formatted(date: .omitted, time: .standard)
    }

    /// "in 1 h 5 min", "in 40 sec", or "tomorrow, in 23 h" — matching how the
    /// timer treats a time that has already passed today.
    static func relativeDescription(_ string: String, now: Date = Date()) -> String {
        var target = date(from: string, on: now)
        var tomorrow = false
        if target < now {
            target = target.addingTimeInterval(86_400)
            tomorrow = true
        }
        let remaining = Int(target.timeIntervalSince(now))
        let hours = remaining / 3600, minutes = (remaining / 60) % 60
        let amount: String
        if hours > 0 { amount = minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h" }
        else if minutes > 0 { amount = "\(minutes) min" }
        else { amount = "\(remaining) sec" }
        return tomorrow ? "tomorrow" : "in \(amount)"
    }
}
