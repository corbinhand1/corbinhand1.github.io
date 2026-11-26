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

    var settingsManager: SettingsManager
    var appDelegate: AppDelegate
    var updateWebClients: () -> Void
    var onCueValueCommitted: (UUID, Int, String) -> Void
    var saveState: () -> Void
    var addCue: () -> Void
    var advanceCue: () -> Void
    var previousCue: () -> Void
    var highlightCue: (Int) -> Void
    var parseCountdownTime: (String) -> Int?
    var getHighlightColor: (Cue) -> Color
    var handleCueSelection: (Int, Bool, Bool) -> Void
    var deleteSelectedCues: () -> Void
    var copyCue: (Int) -> Void
    var pasteCue: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Headers and rows scroll sideways together inside this panel when
            // the sheet is wider than the window. Before, a wide sheet forced
            // the whole window's content wider than the window, pushing the
            // timer buttons, toolbar and Next button off screen.
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        columnHeaders
                        cueList
                    }
                    .frame(width: max(proxy.size.width, tableContentWidth))
                    .frame(maxHeight: .infinity)
                }
            }

            // Bottom row with Add Cue, Next/Prev, etc. (no extra reorder button)
            bottomButtons
        }
    }

    /// Width the cue rows need: state column, every column, the timer, and
    /// room for the header buttons.
    private var tableContentWidth: CGFloat {
        let columnsWidth = cueStack.columns.reduce(0) { $0 + $1.width + 8 }
        return CueRowStyle.stateColumnWidth + 20 + columnsWidth + 80 + CueRowStyle.timerColumnWidth + 60
    }

    // MARK: - Column Headers
    private var columnHeaders: some View {
        HStack(spacing: 0) {
            // Lines the headers up with the cells, past the state column.
            Color.clear.frame(width: CueRowStyle.stateColumnWidth + 20, height: 1)
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
            // This uses the arrow button to toggle isReorderingCues
            HeaderButtons(addColumn: addColumn, isReorderingCues: $isReorderingCues)
                .padding(.leading, 6)
                .padding(.top, 10)

            Spacer(minLength: 12)

            Text("TIMER")
                .font(.system(size: max(10, settingsManager.settings.fontSize - 3), weight: .semibold))
                .tracking(0.8)
                .foregroundColor(settingsManager.settings.fontColor.opacity(0.65))
                .frame(width: CueRowStyle.timerColumnWidth, alignment: .leading)
                .padding(.top, 10)
                .padding(.trailing, 22)
        }
        .padding(.top, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
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
        let upNextIndex = selectedCueIndex.flatMap { cueStack.cues.nextPlayableIndex(after: $0) }

        return CueRowView(
            cue: $cueStack.cues[rowIndex],
            columns: $cueStack.columns,
            index: rowIndex,
            selectedIndex: selectedCueIndex,
            upNextIndex: upNextIndex,
            selectedIndices: selectedCueIndices,
            fontSize: settingsManager.settings.fontSize,
            tableBackgroundColor: settingsManager.settings.tableBackgroundColor,
            onDelete: deleteCue,
            onCopy: copyCue,
            onPaste: pasteCue,
            getHighlightColor: getHighlightColor,
            saveState: saveState,
            updateWebClients: updateWebClients,
            onCueValueCommitted: onCueValueCommitted,
            onSelect: { idx, isShiftDown, isCommandDown in
                // Only allow selection if not reordering
                if !isReorderingCues {
                    handleCueSelection(idx, isShiftDown, isCommandDown)
                }
            },
            onAddCueAbove: addCueAbove,
            onAddCueBelow: addCueBelow,
            editingCueIndex: $editingCueIndex,
            scrollViewProxy: $scrollViewProxy,
            isReorderingCues: isReorderingCues
        )
    }

    // MARK: - Bottom Buttons
    private var bottomButtons: some View {
        let shortcuts = settingsManager.shortcutsManager
        return HStack(spacing: 10) {
            ShowControlButton(title: "Add Cue", systemImage: "plus", shortcut: shortcuts.displayString(for: "addCue"), action: addCue)

            // "Delete Selected" if multiple are selected
            if selectedCueIndices.count > 1 {
                ShowControlButton(title: "Delete Selected", systemImage: "trash", style: .destructive, action: deleteSelectedCues)
            }

            Spacer()

            ShowControlButton(title: "Previous", systemImage: "chevron.left", shortcut: shortcuts.displayString(for: "previousCue"), action: previousCue)
            ShowControlButton(title: "Next Cue", systemImage: "chevron.right", shortcut: shortcuts.displayString(for: "nextCue"), style: .go, action: advanceCue)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Reordering Logic
    private func moveCue(from source: IndexSet, to destination: Int) {
        print("🔄 moveCue called: from \(source) to \(destination)")
        
        // Perform the move directly on the cueStack WITHOUT saving state first
        cueStack.cues.move(fromOffsets: source, toOffset: destination)
        
        print("✅ Move completed - cue moved from \(source.first ?? -1) to \(destination)")

        // Update selected cue index if needed
        if let oldSelected = selectedCueIndex,
           let movedIndex = source.first {
            if movedIndex == oldSelected {
                selectedCueIndex = (destination > movedIndex) ? (destination - 1) : destination
            }
            else if movedIndex < oldSelected && destination <= oldSelected {
                selectedCueIndex = oldSelected - 1
            }
            else if movedIndex > oldSelected && destination <= oldSelected {
                selectedCueIndex = oldSelected + 1
            }
        }
        
        // Save state AFTER the move is complete
        saveState()
        
        // Debounce web client updates to prevent interference with drag operations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            updateWebClients()
        }
    }

    // MARK: - Column Methods
    private func addColumn() {
        cueStack.columns.append(Column(name: "Column \(cueStack.columns.count + 1)", width: 100))
        for i in cueStack.cues.indices {
            cueStack.cues[i].values.append("")
        }
        saveState()
        updateWebClients()
    }

    private func deleteColumn(at index: Int) {
        cueStack.columns.remove(at: index)
        for i in cueStack.cues.indices {
            if index < cueStack.cues[i].values.count {
                cueStack.cues[i].values.remove(at: index)
            }
        }
        saveState()
        updateWebClients()
    }

    // MARK: - Cue Manipulations
    private func deleteCue(at index: Int) {
        cueStack.cues.remove(at: index)
        if let s = selectedCueIndex {
            if index < s {
                selectedCueIndex = s - 1
            } else if index == s {
                selectedCueIndex = nil
                selectedCueTime = nil
            }
        }
        saveState()
        updateWebClients()
    }

    private func copyCueAt(index: Int) {
        copyCue(index)
    }

    private func pasteCueAt(index: Int) {
        pasteCue(index)
    }

    private func addCueAbove(_ index: Int) {
        let newCue = Cue(values: Array(repeating: "", count: cueStack.columns.count))
        cueStack.cues.insert(newCue, at: index)
        selectedCueIndex = index
        saveState()
        updateWebClients()
    }

    private func addCueBelow(_ index: Int) {
        let newCue = Cue(values: Array(repeating: "", count: cueStack.columns.count))
        cueStack.cues.insert(newCue, at: index + 1)
        selectedCueIndex = index + 1
        saveState()
        updateWebClients()
    }
}


// MARK: - Show control button (option A)

/// Footer button with its keyboard shortcut printed on it.
struct ShowControlButton: View {
    enum Style { case normal, go, destructive }

    let title: String
    let systemImage: String
    var shortcut: String? = nil
    var style: Style = .normal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .opacity(0.65)
                }
            }
            .foregroundColor(foreground)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
    }

    private var foreground: Color {
        switch style {
        case .go: return Color(red: 0.02, green: 0.13, blue: 0.06)
        case .destructive, .normal: return .white
        }
    }

    private var background: Color {
        switch style {
        case .go: return CueRowStyle.live
        case .destructive: return Color.red.opacity(0.8)
        case .normal: return Color.white.opacity(0.1)
        }
    }
}
