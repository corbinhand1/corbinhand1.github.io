import SwiftUI

/// Cue timer as m:ss (or h:mm:ss). Presets and ±15s steps so it's quick on a phone.
struct TimerEditor: View {
    @EnvironmentObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    let cueID: String
    @State private var text = ""
    @FocusState private var focused: Bool

    private let presets = [30, 60, 120, 180, 300, 420, 600]
    private var cue: SheetCue? { store.sheet?.cues.first { $0.id == cueID } }
    private var seconds: Int? { Self.parse(text) }
    private var invalid: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty && seconds == nil }

    static func parse(_ s: String) -> Int? {
        let parts = s.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let v = parts.compactMap { $0 }
        switch v.count {
        case 1: return v[0]
        case 2: return v[0] * 60 + v[1]
        case 3: return v[0] * 3600 + v[1] * 60 + v[2]
        default: return nil
        }
    }

    static func format(_ total: Int) -> String {
        let t = max(0, total)
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(seconds.map(Self.format) ?? (text.isEmpty ? "No timer" : "—"))
                    .font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(seconds == nil ? Theme.textMuted : Theme.text)
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .accessibilityLabel(seconds.map { "Timer \(Self.format($0))" } ?? "No timer")

                HStack(spacing: 16) {
                    step("minus", "Subtract 15 seconds", -15)
                    step("plus", "Add 15 seconds", 15)
                }

                FlowLayout(spacing: 8) {
                    ForEach(presets, id: \.self) { p in
                        Button { text = Self.format(p); Haptics.select() } label: {
                            Text(Self.format(p)).monospacedDigit().font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16).frame(minHeight: 44)
                                .background(seconds == p ? Theme.accentFill : Theme.cardRaised, in: Capsule())
                                .foregroundStyle(seconds == p ? Theme.onAccent : Theme.text)
                        }.buttonStyle(PressStyle())
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    TextField("m:ss", text: $text)
                        .focused($focused).keyboardType(.numbersAndPunctuation)
                        .font(.title3.monospacedDigit()).padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(invalid ? Theme.danger : Theme.accent.opacity(0.7), lineWidth: 1.5))
                    if invalid { Label("Use minutes and seconds, like 2:30.", systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(Theme.danger) }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Cue Timer").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 44) }
                ToolbarItem(placement: .bottomBar) {
                    Button("Clear Timer", role: .destructive) { text = "" }.disabled(text.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") { Task { await save() } }.disabled(invalid).fontWeight(.semibold).frame(minHeight: 44)
                }
            }
            .onAppear { text = cue?.timerValue ?? "" }
        }
    }

    private func step(_ icon: String, _ label: String, _ delta: Int) -> some View {
        Button { text = Self.format((seconds ?? 0) + delta); Haptics.select() } label: {
            Image(systemName: icon).font(.title2.weight(.semibold))
                .frame(width: 72, height: Theme.minTarget)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Theme.text)
        }.buttonStyle(PressStyle()).accessibilityLabel(label)
    }

    private func save() async {
        guard let cue else { dismiss(); return }
        let value = text.trimmingCharacters(in: .whitespaces).isEmpty ? "" : Self.format(seconds ?? 0)
        await store.setTimer(cue, value)
        dismiss()
    }
}
