import SwiftUI

struct SheetView: View {
    @EnvironmentObject var store: RemoteStore
    @State private var editing: SheetCue?

    var body: some View {
        NavigationStack {
            List {
                if let sheet = store.sheet {
                    ForEach(sheet.cues) { cue in
                        Button { editing = cue } label: { CueRow(cue: cue, columns: sheet.columns) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) { Task { await store.delete(cue) } } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    if sheet.cues.isEmpty {
                        ContentUnavailableView("No cues", systemImage: "list.bullet.rectangle",
                                               description: Text("Tap + to add the first cue."))
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await store.refresh() }
            .navigationTitle(store.sheet?.cueStackName ?? "Cues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { stackMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Circle().fill(store.live ? Color.green : Color.orange)
                            .frame(width: 9, height: 9)
                            .accessibilityLabel(store.live ? "Live" : "Reconnecting")
                        Button { Task { await store.addCue() } } label: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(item: $editing) { cue in
                CueEditor(cue: cue).environmentObject(store)
            }
            .alert("Problem", isPresented: Binding(get: { store.error != nil },
                                                   set: { if !$0 { store.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(store.error ?? "") }
        }
    }

    private var stackMenu: some View {
        Menu {
            if let stacks = store.sheet?.availableCueStacks {
                ForEach(stacks) { s in
                    Button {
                        Task { await store.selectStack(s.id) }
                    } label: {
                        Label(s.name, systemImage: s.id == store.selectedStackID ? "checkmark" : "")
                    }
                }
            }
            Divider()
            Button("Sign out", role: .destructive) { store.signOut() }
        } label: { Image(systemName: "line.3.horizontal.circle") }
    }
}

private struct CueRow: View {
    let cue: SheetCue
    let columns: [SheetColumn]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if cue.values.allSatisfy({ $0.isEmpty }) {
                Text("Empty cue — tap to edit")
                    .font(.subheadline).italic().foregroundStyle(.secondary)
            }
            ForEach(Array(cue.values.enumerated()), id: \.offset) { i, v in
                if !v.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(i < columns.count ? columns[i].name : "")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                            .lineLimit(1)
                        Text(v).font(i == 0 ? .headline : .subheadline)
                    }
                }
            }
        }
        .strikethrough(cue.isStruckThrough)
        .opacity(cue.isStruckThrough ? 0.5 : 1)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct CueEditor: View {
    @EnvironmentObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    let cue: SheetCue
    @State private var draft: [String] = []
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                ForEach(Array(draft.indices), id: \.self) { i in
                    Section(store.sheet?.columns[safe: i]?.name ?? "Column \(i + 1)") {
                        TextField("", text: $draft[i], axis: .vertical)
                            .lineLimit(1...8)
                    }
                }
            }
            .navigationTitle("Edit Cue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(saving)
                }
            }
            .onAppear { draft = cue.values }
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        for i in draft.indices where i < cue.values.count && draft[i] != cue.values[i] {
            guard await store.edit(cue: cue, column: i, value: draft[i]) else { return }
        }
        dismiss()
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
