import SwiftUI

/// Rename, add, reorder and delete columns for the current stack (administrators).
struct ColumnsEditor: View {
    @EnvironmentObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Int?
    @State private var nameDraft = ""
    @State private var adding = false
    @State private var deleting: Int?

    private var columns: [SheetColumn] { store.sheet?.columns ?? [] }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(columns.enumerated()), id: \.offset) { i, col in
                        Button { nameDraft = col.name; renaming = i } label: {
                            HStack {
                                Text(col.name).foregroundStyle(Theme.text)
                                Spacer()
                                Image(systemName: "pencil").foregroundStyle(Theme.textMuted).accessibilityHidden(true)
                            }.frame(minHeight: 44)
                        }
                        .listRowBackground(Theme.card)
                        .accessibilityLabel("Column \(col.name). Rename")
                        .accessibilityAction(named: "Delete") { deleting = i }
                        .swipeActions { Button(role: .destructive) { deleting = i } label: { Label("Delete", systemImage: "trash") }.tint(.red) }
                    }
                    .onMove { from, to in
                        guard let f = from.first else { return }
                        Task { await store.moveColumn(from: f, to: to > f ? to - 1 : to) }
                    }
                    .deleteDisabled(columns.count <= 1)
                } footer: {
                    Text(store.isAdmin ? "Drag to reorder. Swipe to delete. Changes apply to every cue in this stack."
                                       : "Only administrators can change columns.")
                }
                Section {
                    Button { nameDraft = ""; adding = true } label: { Label("Add Column", systemImage: "plus.circle.fill").frame(minHeight: 44) }
                        .listRowBackground(Theme.card)
                }
            }
            .disabled(!store.isAdmin)
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Columns").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.frame(minHeight: 44) } }
            .alert("Rename Column", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $nameDraft)
                Button("Save") { if let i = renaming { Task { await store.renameColumn(i, to: nameDraft) } } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("New Column", isPresented: $adding) {
                TextField("Name", text: $nameDraft)
                Button("Add") { Task { await store.addColumn(nameDraft) } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this column?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete Column", role: .destructive) { if let i = deleting { Task { await store.deleteColumn(i) } } }
            } message: { Text("Its text is removed from every cue in this stack. You can undo right after.") }
        }
    }
}
