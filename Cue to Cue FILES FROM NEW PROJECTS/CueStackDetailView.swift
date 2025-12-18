//
//  CueStackDetailView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/12/24.
//

import SwiftUI
import AppKit

struct CueStackDetailView: View {
    @Binding var cueStack: CueStack
    @Binding var isReorderingCues: Bool
    @Binding var editingCueIndex: Int?
    @Binding var scrollViewProxy: ScrollViewProxy?

    let geometry: GeometryProxy

    @Binding var selectedCueIndex: Int?
    @Binding var selectedCueIndices: Set<Int>
    @Binding var selectedCueTime: Int?

    @Binding var countdownTime: Int
    @Binding var countdownRunning: Bool
    @Binding var countUpRunning: Bool

    var settingsManager: SettingsManager
    var appDelegate: AppDelegate
    var updateWebClients: () -> Void
    var saveState: () -> Void
    var addCue: () -> Void
    var advanceCue: () -> Void
    var previousCue: () -> Void
    var highlightCue: (Int) -> Void
    var parseCountdownTime: (String) -> Int?
    var getHighlightColor: (Cue) -> Color
    var handleCueSelection: (Int, Bool, Bool) -> Void
    var deleteSelectedCues: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top row with column headers
            columnHeaders

            // Main List of cues
            cueList

            // Bottom row with Add Cue, Next/Prev, etc. (no extra reorder button)
            bottomButtons
        }
    }

    // MARK: - Column Headers
    private var columnHeaders: some View {
        HStack(spacing: 0) {
            ForEach(cueStack.columns.indices, id: \.self) { index in
                ResizableColumnHeader(
                    column: $cueStack.columns[index],
                    allColumns: $cueStack.columns,
                    font: .constant(Font.system(size: settingsManager.settings.fontSize)),
                    fontSize: .constant(settingsManager.settings.fontSize),
                    fontColor: .constant(settingsManager.settings.fontColor),
                    cues: $cueStack.cues,
                    isReorderingCues: $isReorderingCues,
                    addColumn: addColumn,
                    deleteColumn: deleteColumn
                )
            }
            Spacer(minLength: 35)

            // This uses the arrow button to toggle isReorderingCues
            HeaderButtons(addColumn: addColumn, isReorderingCues: $isReorderingCues)
        }
        .padding(.top, 4)
        .background(Color.gray.opacity(0.0))
    }

    // MARK: - Cue List
    private var cueList: some View {
        // Use a ScrollViewReader so we can scroll to selected cues
        ScrollViewReader { proxy in
            List {
                ForEach(cueStack.cues.indices, id: \.self) { rowIndex in
                    // Each row is drawn by rowContent
                    rowContent(rowIndex: rowIndex)
                        .id(rowIndex)
                }
                .onMove(perform: isReorderingCues ? moveCue : nil)
                .moveDisabled(!isReorderingCues)
            }
            .listStyle(PlainListStyle())
            .background(Color.black.opacity(0.0))
            .cornerRadius(8)
            // Whenever the selectedCueIndex changes, scroll to it
            .onChange(of: selectedCueIndex) { _, newValue in
                if let newValue = newValue {
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: UnitPoint(x: 0.5, y: 0.2))
                    }
                }
            }
            .onAppear {
                // Keep a reference to the ScrollViewReader
                scrollViewProxy = proxy
            }
        }
        .cornerRadius(8)
        .background(Color.black.opacity(0.0))
    }

    // The actual row content, with a small "handle" if reordering is on
    private func rowContent(rowIndex: Int) -> some View {
        HStack(spacing: 0) {
            // Show a small handle for reordering if isReorderingCues == true
            if isReorderingCues {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.trailing, 4)
            }

            // The standard CueRowView inside
            cueRow(for: rowIndex)
        }
    }

    // The actual CueRowView
    private func cueRow(for rowIndex: Int) -> some View {
        CueRowView(
            cue: $cueStack.cues[rowIndex],
            columns: $cueStack.columns,
            index: rowIndex,
            selectedIndex: selectedCueIndex,
            selectedIndices: selectedCueIndices,
            fontSize: settingsManager.settings.fontSize,
            tableBackgroundColor: settingsManager.settings.tableBackgroundColor,
            onDelete: deleteCue,
            onCopy: copyCue,
            onPaste: pasteCue,
            getHighlightColor: getHighlightColor,
            saveState: saveState,
            onSelect: { idx, isShiftDown, isCommandDown in
                // Only allow selection if not reordering
                if !isReorderingCues {
                    handleCueSelection(idx, isShiftDown, isCommandDown)
                }
            },
            onAddCueAbove: addCueAbove,
            onAddCueBelow: addCueBelow,
            editingCueIndex: $editingCueIndex,
            scrollViewProxy: $scrollViewProxy
        )
    }

    // MARK: - Bottom Buttons
    private var bottomButtons: some View {
        HStack {
            Button(action: addCue) {
                Label("Add Cue", systemImage: "plus")
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .background(Color.blue)
            .cornerRadius(8)

            // "Delete Selected" if multiple are selected
            if selectedCueIndices.count > 1 {
                Button(action: {
                    deleteSelectedCues()
                }) {
                    Label("Delete Selected", systemImage: "trash")
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(Color.red)
                .cornerRadius(8)
            }

            Spacer()

            // Prev/Next
            HStack(spacing: 16) {
                Button(action: previousCue) {
                    Label("Previous", systemImage: "chevron.left")
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(Color.gray)
                .cornerRadius(8)

                Button(action: advanceCue) {
                    Label("Next", systemImage: "chevron.right")
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .background(Color.gray)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.0))
        .cornerRadius(8)
    }

    // MARK: - Reordering Logic
    private func moveCue(from source: IndexSet, to destination: Int) {
        saveState()
        cueStack.cues.move(fromOffsets: source, toOffset: destination)

        // If the selected cue was moved, fix selectedCueIndex
        if let oldSelected = selectedCueIndex,
           let movedIndex = source.first {
            if movedIndex == oldSelected {
                // The selected row was moved
                selectedCueIndex = (destination > movedIndex) ? (destination - 1) : destination
            }
            else if movedIndex < oldSelected && destination <= oldSelected {
                // A row above the selection was pulled below => shift selection up by 1
                selectedCueIndex = oldSelected - 1
            }
            else if movedIndex > oldSelected && destination <= oldSelected {
                // A row below the selection was pulled above => shift selection down by 1
                selectedCueIndex = oldSelected + 1
            }
        }

        updateWebClients()
    }

    // MARK: - Column Methods
    private func addColumn() {
        saveState()
        cueStack.columns.append(Column(name: "Column \(cueStack.columns.count + 1)", width: 100))
        for i in cueStack.cues.indices {
            cueStack.cues[i].values.append("")
        }
        updateWebClients()
    }

    private func deleteColumn(at index: Int) {
        saveState()
        cueStack.columns.remove(at: index)
        for i in cueStack.cues.indices {
            if index < cueStack.cues[i].values.count {
                cueStack.cues[i].values.remove(at: index)
            }
        }
        updateWebClients()
    }

    // MARK: - Cue Manipulations
    private func deleteCue(at index: Int) {
        saveState()
        cueStack.cues.remove(at: index)
        if let s = selectedCueIndex {
            if index < s {
                selectedCueIndex = s - 1
            } else if index == s {
                selectedCueIndex = nil
                selectedCueTime = nil
            }
        }
        updateWebClients()
    }

    private func copyCue(at index: Int) {
        appDelegate.contentView?.copyCue(at: index)
    }

    private func pasteCue(at index: Int) {
        appDelegate.contentView?.pasteCue(at: index)
    }

    private func addCueAbove(_ index: Int) {
        saveState()
        let newCue = Cue(values: Array(repeating: "", count: cueStack.columns.count))
        cueStack.cues.insert(newCue, at: index)
        selectedCueIndex = index
        updateWebClients()
    }

    private func addCueBelow(_ index: Int) {
        saveState()
        let newCue = Cue(values: Array(repeating: "", count: cueStack.columns.count))
        cueStack.cues.insert(newCue, at: index + 1)
        selectedCueIndex = index + 1
        updateWebClients()
    }
}
