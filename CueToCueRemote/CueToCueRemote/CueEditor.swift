import SwiftUI
import UIKit

/// Edit one cell at a time: pick a column chip, type, then jump to the same
/// column on the previous/next cue. Changes save automatically when you move
/// or close, so there is no Save button to forget.
struct CueEditor: View {
    @EnvironmentObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss

    @State private var cueID: String
    @State private var column: Int
    @State private var draft = ""
    @State private var saving = false
    @State private var savedFlash = false
    @FocusState private var focused: Bool

    init(start: EditTarget) {
        _cueID = State(initialValue: start.cueID)
        _column = State(initialValue: start.column)
    }

    private var cues: [SheetCue] { store.sheet?.cues ?? [] }
    private var columns: [SheetColumn] { store.sheet?.columns ?? [] }
    private var index: Int? { cues.firstIndex { $0.id == cueID } }
    private var cue: SheetCue? { index.map { cues[$0] } }

    private func value(_ cue: SheetCue, _ col: Int) -> String {
        col < cue.values.count ? cue.values[col] : ""
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                columnChips
                editorField
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
                    Button("Done") { Task { await finish() } }
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .onAppear { load(); focused = true }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
        // Swiping the sheet away still saves what was typed.
        .onDisappear { Task { await commit(silent: true) } }
    }

    private var title: String {
        guard let i = index else { return "Edit Cue" }
        let num = cue?.values.first ?? ""
        return num.isEmpty ? "Cue \(i + 1) of \(cues.count)" : "Cue \(num) · \(i + 1) of \(cues.count)"
    }

    // MARK: Column chips

    private var columnChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { i, col in
                        let filled = cue.map { !value($0, i).isEmpty } ?? false
                        Button { Task { await switchColumn(i) } } label: {
                            HStack(spacing: 6) {
                                Text(col.name)
                                    .font(.subheadline.weight(i == column ? .bold : .medium))
                                if filled && i != column {
                                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: Theme.minTarget)
                            .foregroundStyle(i == column ? Theme.onAccent : Theme.text)
                            .background(i == column ? Theme.accent : Theme.cardRaised, in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .id(i)
                        .accessibilityLabel("\(col.name)\(filled ? ", has content" : ", empty")")
                        .accessibilityAddTraits(i == column ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .onChange(of: column) { _, c in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(c, anchor: .center) } }
        }
    }

    // MARK: Field

    private var editorField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(columns[safe: column]?.name ?? "Column")
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.textMuted)
            TextField("Type here", text: $draft, axis: .vertical)
                .focused($focused)
                .font(.title3)
                .lineLimit(2...10)
                .padding(14)
                .frame(minHeight: 96, alignment: .topLeading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.7), lineWidth: 1.5))
                .submitLabel(.next)
                .onSubmit { Task { await step(1) } }   // Return = next cue, same column
        }
        .padding(.horizontal, 12).padding(.top, 4)
    }

    // MARK: Prev / Next bar

    private var navBar: some View {
        HStack(spacing: 12) {
            navButton("chevron.up", "Previous cue", enabled: (index ?? 0) > 0) { await step(-1) }
            navButton("chevron.down", "Next cue", enabled: (index ?? 0) < cues.count - 1) { await step(1) }
            Spacer(minLength: 0)
            Button {
                Task { await nextColumn() }
            } label: {
                Label("Next field", systemImage: "arrow.right")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 18).frame(minHeight: Theme.minTarget)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(PressStyle())
            .disabled(column >= columns.count - 1)
            .opacity(column >= columns.count - 1 ? 0.4 : 1)
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

    // MARK: Behavior

    private func load() {
        draft = cue.map { value($0, column) } ?? ""
    }

    /// Saves the draft if it changed. Returns false if the save failed.
    @discardableResult
    private func commit(silent: Bool = false) async -> Bool {
        guard let cue, draft != value(cue, column) else { return true }
        saving = true; defer { saving = false }
        let ok = await store.edit(cue: cue, column: column, value: draft)
        if ok && !silent {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            savedFlash = true
            Task { try? await Task.sleep(nanoseconds: 1_200_000_000); savedFlash = false }
        }
        return ok
    }

    private func switchColumn(_ i: Int) async {
        guard i != column, await commit() else { return }
        column = i; load(); focused = true
    }

    private func nextColumn() async { await switchColumn(column + 1) }

    private func step(_ delta: Int) async {
        guard let i = index, cues.indices.contains(i + delta), await commit() else { return }
        cueID = cues[i + delta].id; load(); focused = true
    }

    private func finish() async {
        if await commit() { dismiss() }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
