import SwiftUI
import UIKit

/// Edit just the text between the [ ] of a cue description, then jump to the
/// next cue that has one. Built for walking the stage asking "what will you say?".
struct WhenEditor: View {
    @EnvironmentObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss

    @State private var ids: [String] = []
    @State private var cueID: String
    @State private var draft = ""
    @State private var baselineDesc = ""
    @State private var savedFlash = false
    @FocusState private var focused: Bool

    init(start: String) { _cueID = State(initialValue: start) }

    private var sheet: Sheet? { store.sheet }
    private var descCol: Int { sheet?.descriptionColumn ?? 1 }
    private var cue: SheetCue? { sheet?.cues.first { $0.id == cueID } }
    private var description: String { cue.flatMap { descCol < $0.values.count ? $0.values[descCol] : nil } ?? "" }
    private var pos: Int? { ids.firstIndex(of: cueID) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                // What this cue is, so you know which one you're editing.
                VStack(alignment: .leading, spacing: 4) {
                    Text(cue?.values.first.flatMap { $0.isEmpty ? nil : "CUE \($0)" } ?? "CUE")
                        .font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                    Text(When.stripped(description).isEmpty ? "(no description)" : When.stripped(description))
                        .font(.headline).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 12).padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("WHEN — text between the [ ]")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.textMuted)
                    HStack(alignment: .top, spacing: 6) {
                        Text("[").font(.system(.title, design: .monospaced).weight(.bold)).foregroundStyle(Theme.accent)
                        TextField("what they'll say", text: $draft, axis: .vertical)
                            .focused($focused)
                            .font(.title3)
                            .lineLimit(2...8)
                            .submitLabel(.next)
                            .onSubmit { Task { await step(1) } }
                        Text("]").font(.system(.title, design: .monospaced).weight(.bold)).foregroundStyle(Theme.accent)
                    }
                    .padding(14)
                    .frame(minHeight: 96, alignment: .topLeading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.7), lineWidth: 1.5))
                }
                .padding(.horizontal, 12)

                Spacer(minLength: 0)
                navBar
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if savedFlash { Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(.green) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Task { if await commit() { dismiss() } } }
                        .font(.body.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                }
            }
            .onAppear {
                // Fixed list: every cue that has a [when], plus the one we opened on.
                let all = sheet?.cues ?? []
                let col = descCol
                ids = all.filter { c in
                    c.id == cueID || (col < c.values.count && When.text(in: c.values[col]) != nil)
                }.map(\.id)
                load(); focused = true
            }
        }
                .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear { Task { await commit(silent: true) } }
    }

    private var title: String {
        guard let p = pos else { return "Edit [when]" }
        return "[when] \(p + 1) of \(ids.count)"
    }

    private var navBar: some View {
        HStack(spacing: 12) {
            navButton("chevron.up", "Previous cue with a when", enabled: (pos ?? 0) > 0) { await step(-1) }
            navButton("chevron.down", "Next cue with a when", enabled: (pos ?? 0) < ids.count - 1) { await step(1) }
            Spacer(minLength: 0)
            Text("Return = next").font(.footnote).foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.card)
    }

    private func navButton(_ icon: String, _ label: String, enabled: Bool,
                           action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .frame(width: Theme.minTarget + 8, height: Theme.minTarget)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled).opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private func load() { baselineDesc = description; draft = When.text(in: baselineDesc) ?? "" }

    @discardableResult
    private func commit(silent: Bool = false) async -> Bool {
        guard let cue else { return true }
        let current = When.text(in: baselineDesc) ?? ""
        guard draft.trimmingCharacters(in: .whitespacesAndNewlines) != current else { return true }
        let newDesc = When.replacing(in: description, with: draft)
        let ok = await store.edit(cue: cue, column: descCol, value: newDesc, base: baselineDesc)
        if ok { baselineDesc = newDesc }
        if ok && !silent {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            savedFlash = true
            Task { try? await Task.sleep(nanoseconds: 1_200_000_000); savedFlash = false }
        }
        return ok
    }

    private func step(_ delta: Int) async {
        guard let p = pos, ids.indices.contains(p + delta), await commit() else { return }
        cueID = ids[p + delta]; load(); focused = true
    }
}
