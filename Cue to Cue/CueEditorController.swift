//
//  CueEditorController.swift
//  Cue to Cue
//
//  Owns everything about editing the cue sheet that is not file I/O or UI
//  layout: undo/redo, cue selection (single, Cmd-click, Shift-click), cue
//  navigation during a show, add/delete/cut/copy/paste and strike-through.
//
//  ContentView used to hold all of this as @State plus ~400 lines of
//  methods; it now forwards to this object, which can be tested directly
//  against a real DataSyncManager.
//

import Foundation
import AppKit
import Combine

@MainActor
final class CueEditorController: ObservableObject {

    // MARK: - State

    /// The shared document model (also used by the LAN server).
    let data: DataSyncManager

    /// Rows highlighted in the table. Contains the single selected cue when
    /// there is no multi-selection.
    @Published var selectedCueIndices: Set<Int> = []
    /// Anchor for Shift-click range selection.
    @Published private(set) var lastSelectedIndex: Int?
    /// True after Cmd-click / Shift-click / Select All.
    @Published private(set) var isMultiSelectMode = false
    /// Timer value (seconds) of the most recently highlighted cue.
    @Published var selectedCueTime: Int?

    private(set) var history = CueUndoHistory()
    private var isPerformingUndoRedo = false

    // MARK: - Hooks

    /// Called after any change the LAN viewers should see.
    var notifyWebClients: () -> Void = {}
    /// Called when a highlighted cue has a timer value (seconds).
    var onCueTimerSelected: (Int) -> Void = { seconds in
        NotificationCenter.default.post(name: Notification.Name("ResetCountdown"), object: seconds)
    }
    /// Alert sound for impossible actions; replaceable in tests.
    var beep: () -> Void = { NSSound.beep() }
    /// Pasteboard used for cue copy/paste; replaceable in tests.
    var pasteboard: NSPasteboard = .general

    init(data: DataSyncManager) {
        self.data = data
    }

    // MARK: - Convenience

    var selectedStackIndex: Int { data.selectedCueStackIndex }

    var hasValidSelectedStack: Bool {
        data.cueStacks.indices.contains(data.selectedCueStackIndex)
    }

    var selectedStack: CueStack? {
        hasValidSelectedStack ? data.cueStacks[data.selectedCueStackIndex] : nil
    }

    var canUndo: Bool { history.canUndo || (history.index >= 0 && history.snapshots[history.index] != data.cueStacks) }
    var canRedo: Bool { history.canRedo }

    // MARK: - Undo / Redo

    /// Record the document as it is now, after an edit. Call AFTER mutating.
    func recordEdit() {
        history.record(data.cueStacks)
    }

    /// Start a clean undo baseline (after load / new document).
    func resetHistory() {
        history.reset(to: data.cueStacks)
    }

    func undo() {
        guard !isPerformingUndoRedo else { return }
        isPerformingUndoRedo = true
        defer { isPerformingUndoRedo = false }
        guard let state = history.undo(current: data.cueStacks) else {
            beep()
            return
        }
        applyHistoryState(state)
    }

    func redo() {
        guard !isPerformingUndoRedo else { return }
        isPerformingUndoRedo = true
        defer { isPerformingUndoRedo = false }
        guard let state = history.redo(current: data.cueStacks) else {
            beep()
            return
        }
        applyHistoryState(state)
    }

    /// Restore a whole-document snapshot and keep selection indices valid.
    private func applyHistoryState(_ state: [CueStack]) {
        data.cueStacks = state
        let stackIndex = CueEditing.clampedStackIndex(data.selectedCueStackIndex, count: state.count)
        if stackIndex != data.selectedCueStackIndex {
            data.selectedCueStackIndex = stackIndex
        }
        let cueCount = state.indices.contains(stackIndex) ? state[stackIndex].cues.count : 0
        if data.selectedCueIndex >= cueCount {
            data.selectedCueIndex = cueCount - 1
        }
        clearSelection()
        notifyWebClients()
    }

    // MARK: - Selection

    func handleCueSelection(at index: Int, withShiftKey: Bool, withCommandKey: Bool) {
        guard let stack = selectedStack, stack.cues.indices.contains(index) else { return }

        if withCommandKey {
            isMultiSelectMode = true
            if selectedCueIndices.contains(index) {
                selectedCueIndices.remove(index)
                if selectedCueIndices.isEmpty {
                    isMultiSelectMode = false
                    data.selectedCueIndex = -1
                }
            } else {
                selectedCueIndices.insert(index)
                data.selectedCueIndex = index
            }
        } else if withShiftKey, let anchor = lastSelectedIndex {
            isMultiSelectMode = true
            let range = min(anchor, index)...max(anchor, index)
            selectedCueIndices.formUnion(range.filter { stack.cues.indices.contains($0) })
            data.selectedCueIndex = index
        } else {
            isMultiSelectMode = false
            selectedCueIndices = [index]
            data.selectedCueIndex = index
            highlightCue(at: index)
        }
        lastSelectedIndex = index
        notifyWebClients()
    }

    /// The cues an edit command should act on: the multi-selection, or the
    /// single selected cue.
    func selectedIndicesForCommand() -> [Int]? {
        if isMultiSelectMode && !selectedCueIndices.isEmpty {
            return selectedCueIndices.sorted()
        }
        if data.selectedCueIndex >= 0 {
            return [data.selectedCueIndex]
        }
        return nil
    }

    func clearSelection() {
        selectedCueIndices.removeAll()
        isMultiSelectMode = false
        lastSelectedIndex = nil
    }

    func selectAll() {
        guard let stack = selectedStack, !stack.cues.isEmpty else { return }
        isMultiSelectMode = true
        selectedCueIndices = Set(stack.cues.indices)
        if data.selectedCueIndex >= 0 {
            lastSelectedIndex = data.selectedCueIndex
        } else {
            data.selectedCueIndex = 0
            lastSelectedIndex = 0
        }
        notifyWebClients()
    }

    // MARK: - Show navigation

    /// Next cue that is not struck through.
    func advanceCue() {
        guard let stack = selectedStack, data.selectedCueIndex >= 0,
              let next = stack.cues.nextPlayableIndex(after: data.selectedCueIndex) else { return }
        goToCue(at: next)
    }

    /// Previous cue that is not struck through.
    func previousCue() {
        guard let stack = selectedStack, data.selectedCueIndex >= 0,
              let previous = stack.cues.previousPlayableIndex(before: data.selectedCueIndex) else { return }
        goToCue(at: previous)
    }

    private func goToCue(at index: Int) {
        data.selectedCueIndex = index
        selectedCueIndices = [index]
        isMultiSelectMode = false
        lastSelectedIndex = index
        highlightCue(at: index)
        notifyWebClients()
    }

    /// Reset the countdown to the cue's timer value, if it has one.
    func highlightCue(at index: Int) {
        guard let stack = selectedStack, stack.cues.indices.contains(index),
              let seconds = Self.parseCountdownTime(stack.cues[index].timerValue) else { return }
        selectedCueTime = seconds
        onCueTimerSelected(seconds)
    }

    /// "SS", "MM:SS" or "HH:MM:SS" to seconds.
    nonisolated static func parseCountdownTime(_ timeString: String) -> Int? {
        let parts = timeString.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let values = parts.compactMap { $0 }
        switch values.count {
        case 1: return values[0]
        case 2: return values[0] * 60 + values[1]
        case 3: return values[0] * 3600 + values[1] * 60 + values[2]
        default: return nil
        }
    }

    // MARK: - Editing

    func addCue() {
        guard hasValidSelectedStack else {
            beep()
            return
        }
        let stackIndex = data.selectedCueStackIndex
        let newCue = Cue(values: Array(repeating: "", count: data.cueStacks[stackIndex].columns.count))
        data.cueStacks[stackIndex].cues.append(newCue)
        recordEdit()
        notifyWebClients()
    }

    func deleteSelectedCues() {
        guard hasValidSelectedStack, let indices = selectedIndicesForCommand(), !indices.isEmpty else { return }
        let stackIndex = data.selectedCueStackIndex
        var stack = data.cueStacks[stackIndex]
        let newSelection = CueEditing.remove(indices: indices, from: &stack, selected: data.selectedCueIndex)
        data.cueStacks[stackIndex] = stack
        data.selectedCueIndex = newSelection
        clearSelection()
        if newSelection >= 0 {
            selectedCueIndices = [newSelection]
            lastSelectedIndex = newSelection
        }
        recordEdit()
        notifyWebClients()
    }

    func copySelection() {
        guard let indices = selectedIndicesForCommand() else { return }
        copyCues(at: indices)
    }

    func copyCues(at indices: [Int]) {
        guard let stack = selectedStack else { return }
        let cues = indices.filter { stack.cues.indices.contains($0) }.map { stack.cues[$0] }
        CueClipboard.write(cues, columnCount: stack.columns.count, to: pasteboard)
    }

    func cutSelection() {
        guard let indices = selectedIndicesForCommand() else { return }
        copyCues(at: indices)
        deleteSelectedCues()
    }

    /// Paste after the selected cue, or at the end when nothing is selected.
    func paste() {
        pasteCues(after: data.selectedCueIndex >= 0 ? data.selectedCueIndex : nil)
    }

    func pasteCues(after index: Int?) {
        guard hasValidSelectedStack else { return }
        guard let cues = CueClipboard.read(from: pasteboard), !cues.isEmpty else {
            beep()
            return
        }
        let stackIndex = data.selectedCueStackIndex
        var stack = data.cueStacks[stackIndex]
        guard let lastInserted = CueEditing.paste(cues, into: &stack, after: index) else { return }
        data.cueStacks[stackIndex] = stack
        data.selectedCueIndex = lastInserted
        clearSelection()
        selectedCueIndices = [lastInserted]
        lastSelectedIndex = lastInserted
        recordEdit()
        notifyWebClients()
    }

    /// Toggle strike-through on the selected cue(s). Struck cues are skipped
    /// by next/previous cue.
    func toggleStrikeThrough() {
        guard hasValidSelectedStack, let indices = selectedIndicesForCommand() else { return }
        let stackIndex = data.selectedCueStackIndex
        var stack = data.cueStacks[stackIndex]
        let valid = indices.filter { stack.cues.indices.contains($0) }
        guard !valid.isEmpty else { return }
        // Mixed selection: strike everything; all struck: unstrike everything.
        let strike = !valid.allSatisfy { stack.cues[$0].isStruckThrough }
        for i in valid {
            stack.cues[i].isStruckThrough = strike
        }
        data.cueStacks[stackIndex] = stack
        data.recordLANChange(kind: .snapshot)
        recordEdit()
        notifyWebClients()
    }
}
