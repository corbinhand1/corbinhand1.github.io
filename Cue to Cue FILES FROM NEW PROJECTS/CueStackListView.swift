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
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        VStack(spacing: 0) {
            header
            cueStackList
        }
        .frame(width: cueStackListWidth)
        .background(Color.black.opacity(0.0))
    }

    private var header: some View {
        HStack {
            Text("Cue Stacks")
                .font(.headline)
                .foregroundColor(settingsManager.settings.fontColor)
            Spacer()
            Button(action: addCueStack) {
                Image(systemName: "plus")
                    .foregroundColor(settingsManager.settings.fontColor)
            }
            .buttonStyle(PlainButtonStyle())
            Button(action: { isReordering.toggle() }) {
                Image(systemName: isReordering ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
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

                    Button(action: { deleteCueStack(at: index) }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Cue Stack")
                        }
                    }
                    .foregroundColor(.primary)

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

    private func deleteCueStack(at index: Int) {
        cueStacks.remove(at: index)
        selectedCueStackIndex = min(selectedCueStackIndex, cueStacks.count - 1)
    }

    private func renameCueStack(at index: Int) {
        editCueStackIndex = index
    }

    private func duplicateCueStack(at index: Int) {
        let original = cueStacks[index]
        let duplicated = CueStack(name: "\(original.name) Copy", cues: original.cues, columns: original.columns)
        cueStacks.append(duplicated)
    }

    private func moveCueStacks(from source: IndexSet, to destination: Int) {
        cueStacks.move(fromOffsets: source, toOffset: destination)
        if let originalIndex = source.first {
            if originalIndex == selectedCueStackIndex {
                selectedCueStackIndex = destination - 1
            } else if originalIndex < selectedCueStackIndex && destination > selectedCueStackIndex {
                selectedCueStackIndex -= 1
            } else if originalIndex > selectedCueStackIndex && destination <= selectedCueStackIndex {
                selectedCueStackIndex += 1
            }
        }
    }
}
