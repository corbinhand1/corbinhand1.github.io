//
//  CueStackListView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/12/24.
//

import SwiftUI

struct CueStackListView: View {
    @Binding var cueStacks: [CueStack]
    @Binding var selectedCueStackIndex: Int
    @Binding var cueStackListWidth: CGFloat
    @State private var isReordering = false
    @State private var editCueStackIndex: Int?
    @State private var pendingDeleteIndex: Int?
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        VStack(spacing: 0) {
            header
            cueStackList
        }
        .frame(width: cueStackListWidth)
        .background(Color.black.opacity(0.0))
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: Binding(
                get: { pendingDeleteIndex != nil },
                set: { if !$0 { pendingDeleteIndex = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let index = pendingDeleteIndex { deleteCueStack(at: index) }
                pendingDeleteIndex = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteIndex = nil }
        } message: {
            Text("You can undo this with Edit → Undo.")
        }
    }

    private var deleteDialogTitle: String {
        guard let index = pendingDeleteIndex, cueStacks.indices.contains(index) else { return "Delete Cue Stack?" }
        let stack = cueStacks[index]
        return "Delete \"\(stack.name)\" and its \(stack.cues.count) cue\(stack.cues.count == 1 ? "" : "s")?"
    }

    private var header: some View {
        HStack {
            Text("Cue Stacks")
                .font(.headline)
                .foregroundColor(settingsManager.settings.fontColor)
            Spacer()
            Button(action: addCueStack) {
                Image(systemName: "plus")
                    .accessibilityLabel(Text("Add Cue Stack"))
                    .help("Add Cue Stack")
                    .foregroundColor(settingsManager.settings.fontColor)
            }
            .buttonStyle(PlainButtonStyle())
            Button(action: { isReordering.toggle() }) {
                Image(systemName: isReordering ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                    .accessibilityLabel(Text(isReordering ? "Finish Reordering Cue Stacks" : "Reorder Cue Stacks"))
                    .help(isReordering ? "Finish Reordering Cue Stacks" : "Reorder Cue Stacks")
                    .foregroundColor(isReordering ? .blue : settingsManager.settings.fontColor)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 24)
 //       .background(settingsManager.settings.backgroundColor)
    }

    private var cueStackList: some View {
        List {
            ForEach(cueStacks.indices, id: \.self) { index in
                cueStackRow(for: index)
                    .listRowBackground(selectedCueStackIndex == index ? Color.blue.opacity(0.0) : Color.clear)
            }
            .onMove(perform: isReordering ? moveCueStacks : nil)
            .listRowInsets(EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1))
        }
        .listStyle(PlainListStyle())
      //  .background(settingsManager.settings.backgroundColor)
        .cornerRadius(8)
    }

    private func cueStackRow(for index: Int) -> some View {
        HStack {
            if isReordering {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.gray)
            }
            if editCueStackIndex == index {
                TextField("Cue Stack Name", text: $cueStacks[index].name, onCommit: {
                    editCueStackIndex = nil
                })
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(settingsManager.settings.fontColor)
            } else {
                Text(cueStacks[index].name)
                    .foregroundColor(settingsManager.settings.fontColor)
                    .onTapGesture {
                        if !isReordering {
                            selectedCueStackIndex = index
                        }
                    }
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(selectedCueStackIndex == index ? Color.blue.opacity(0.6) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .contextMenu {
            if !isReordering {
                Group {
                    Button(action: { addCueStack() }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Cue Stack")
                        }
                    }
                    .foregroundColor(.primary)

                    Button(action: { requestDeleteCueStack(at: index) }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Cue Stack")
                        }
                    }
                    .foregroundColor(.primary)
                    .disabled(cueStacks.count <= 1)

                    Button(action: { renameCueStack(at: index) }) {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Rename Cue Stack")
                        }
                    }
                    .foregroundColor(.primary)

                    Button(action: { duplicateCueStack(at: index) }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Duplicate Cue Stack")
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
        }
    }

    private func addCueStack() {
        let newCueStack = CueStack(name: "Cue Stack \(cueStacks.count + 1)", cues: [], columns: [Column(name: "Column 1", width: 100)])
        cueStacks.append(newCueStack)
    }

    /// Empty stacks are deleted straight away; stacks with cues ask first.
    private func requestDeleteCueStack(at index: Int) {
        guard cueStacks.indices.contains(index), cueStacks.count > 1 else { return }
        if cueStacks[index].cues.isEmpty {
            deleteCueStack(at: index)
        } else {
            pendingDeleteIndex = index
        }
    }

    /// Never deletes the last stack: the rest of the app assumes one exists.
    private func deleteCueStack(at index: Int) {
        guard cueStacks.indices.contains(index), cueStacks.count > 1 else { return }
        editCueStackIndex = nil
        let oldSelected = selectedCueStackIndex
        cueStacks.remove(at: index)
        let newSelected: Int
        if index < oldSelected {
            newSelected = oldSelected - 1
        } else {
            newSelected = oldSelected
        }
        selectedCueStackIndex = CueEditing.clampedStackIndex(newSelected, count: cueStacks.count)
    }

    private func renameCueStack(at index: Int) {
        editCueStackIndex = index
    }

    private func duplicateCueStack(at index: Int) {
        guard cueStacks.indices.contains(index) else { return }
        cueStacks.insert(CueEditing.duplicate(cueStacks[index]), at: index + 1)
        if selectedCueStackIndex > index {
            selectedCueStackIndex += 1
        }
    }

    private func moveCueStacks(from source: IndexSet, to destination: Int) {
        selectedCueStackIndex = CueEditing.moveStacks(&cueStacks, from: source, to: destination, selected: selectedCueStackIndex)
    }
}
