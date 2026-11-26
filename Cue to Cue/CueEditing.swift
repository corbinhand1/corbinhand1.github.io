//
//  CueEditing.swift
//  Cue to Cue
//
//  Pure, testable editing logic shared by ContentView and CueStackListView:
//  document-level undo history, paste/duplicate with fresh IDs, stack
//  reordering that keeps the selection on the same stack, and the cue
//  clipboard format.
//

import Foundation
import AppKit

// MARK: - Undo history

/// Whole-document undo history.
///
/// Each snapshot is the full `[CueStack]` array, so undo can never write one
/// stack's cues into another stack (the old per-stack history did exactly that
/// after switching stacks). Changes that happened without a snapshot (stack
/// add/rename/delete, LAN edits, strike-through) are captured on the next
/// undo so they are reverted as one step instead of being silently lost.
struct CueUndoHistory {
    private(set) var snapshots: [[CueStack]] = []
    private(set) var index: Int = -1
    let limit: Int

    init(limit: Int = 200) {
        self.limit = max(2, limit)
    }

    var canUndo: Bool { index > 0 }
    var canRedo: Bool { index >= 0 && index < snapshots.count - 1 }

    /// Start a fresh history whose only entry is `state`.
    mutating func reset(to state: [CueStack]) {
        snapshots = [state]
        index = 0
    }

    /// Record `state` as the result of an edit. Duplicate states are ignored.
    mutating func record(_ state: [CueStack]) {
        if index >= 0, index < snapshots.count, snapshots[index] == state {
            return
        }
        if index < snapshots.count - 1 {
            snapshots.removeSubrange((index + 1)...)
        }
        snapshots.append(state)
        index = snapshots.count - 1
        if snapshots.count > limit {
            let overflow = snapshots.count - limit
            snapshots.removeFirst(overflow)
            index -= overflow
        }
    }

    /// Returns the state to restore, or nil when there is nothing to undo.
    /// `current` is the live document; if it differs from the last snapshot
    /// it is recorded first so untracked edits are what gets undone.
    mutating func undo(current: [CueStack]) -> [CueStack]? {
        if index >= 0, index < snapshots.count, snapshots[index] != current {
            record(current)
        }
        guard canUndo else { return nil }
        index -= 1
        return snapshots[index]
    }

    /// Returns the state to restore, or nil when there is nothing to redo.
    /// If the live document drifted since the last snapshot the redo branch
    /// is no longer valid, so nothing is redone.
    mutating func redo(current: [CueStack]) -> [CueStack]? {
        guard index >= 0, index < snapshots.count, snapshots[index] == current else { return nil }
        guard canRedo else { return nil }
        index += 1
        return snapshots[index]
    }
}

// MARK: - Editing helpers

enum CueEditing {

    /// A copy of `cue` with a new ID and its values padded/truncated to
    /// `columnCount`. Every pasted or duplicated cue must get a new ID:
    /// LAN sync, selection and SwiftUI row identity all key off `Cue.id`.
    static func fittedCopy(of cue: Cue, columnCount: Int) -> Cue {
        var values = cue.values
        if values.count < columnCount {
            values.append(contentsOf: Array(repeating: "", count: columnCount - values.count))
        } else if values.count > columnCount {
            values = Array(values.prefix(columnCount))
        }
        return Cue(id: UUID(), values: values, timerValue: cue.timerValue, isStruckThrough: cue.isStruckThrough)
    }

    /// Duplicate a stack with fresh stack, column and cue IDs.
    static func duplicate(_ stack: CueStack, name: String? = nil) -> CueStack {
        CueStack(
            id: UUID(),
            name: name ?? "\(stack.name) Copy",
            cues: stack.cues.map { Cue(id: UUID(), values: $0.values, timerValue: $0.timerValue, isStruckThrough: $0.isStruckThrough) },
            columns: stack.columns.map { Column(id: UUID(), name: $0.name, width: $0.width) }
        )
    }

    /// Insert `cues` into `stack` after `index` (or at the end when `index`
    /// is nil / out of range). Returns the index of the last inserted cue.
    @discardableResult
    static func paste(_ cues: [Cue], into stack: inout CueStack, after index: Int?) -> Int? {
        guard !cues.isEmpty else { return nil }
        let fitted = cues.map { fittedCopy(of: $0, columnCount: stack.columns.count) }
        let insertAt: Int
        if let index, index >= 0, index < stack.cues.count {
            insertAt = index + 1
        } else {
            insertAt = stack.cues.count
        }
        stack.cues.insert(contentsOf: fitted, at: insertAt)
        return insertAt + fitted.count - 1
    }

    /// Remove the cues at `indices` and return the new selected index:
    /// the cue that took the place of the first removed one, or the new last
    /// cue, or -1 when the stack is empty. `selected` is the old selection.
    static func remove(indices: [Int], from stack: inout CueStack, selected: Int) -> Int {
        let valid = Set(indices.filter { stack.cues.indices.contains($0) })
        guard !valid.isEmpty else { return selected }
        let lowest = valid.min()!
        let selectedWasRemoved = valid.contains(selected)
        let removedBeforeSelected = valid.filter { $0 < selected }.count
        for i in valid.sorted(by: >) {
            stack.cues.remove(at: i)
        }
        if stack.cues.isEmpty { return -1 }
        if selected < 0 { return -1 }
        if selectedWasRemoved {
            return min(lowest, stack.cues.count - 1)
        }
        return selected - removedBeforeSelected
    }

    /// Move stacks and return the selected index so it still points at the
    /// same stack it did before the move.
    static func moveStacks(_ stacks: inout [CueStack], from source: IndexSet, to destination: Int, selected: Int) -> Int {
        let selectedID = stacks.indices.contains(selected) ? stacks[selected].id : nil
        stacks.move(fromOffsets: source, toOffset: destination)
        guard let selectedID, let newIndex = stacks.firstIndex(where: { $0.id == selectedID }) else {
            return min(max(selected, 0), stacks.count - 1)
        }
        return newIndex
    }

    /// Give every stack, column and cue a unique ID. The first occurrence
    /// of an ID keeps it; later duplicates get a new one. Content is unchanged.
    static func repairingDuplicateIDs(_ stacks: [CueStack]) -> [CueStack] {
        var seenStacks = Set<UUID>()
        var seenColumns = Set<UUID>()
        var seenCues = Set<UUID>()
        return stacks.map { original in
            var stack = original
            if !seenStacks.insert(stack.id).inserted { stack.id = UUID() }
            for i in stack.columns.indices where !seenColumns.insert(stack.columns[i].id).inserted {
                stack.columns[i].id = UUID()
            }
            for i in stack.cues.indices where !seenCues.insert(stack.cues[i].id).inserted {
                stack.cues[i].id = UUID()
            }
            return stack
        }
    }

    /// Clamp a stack selection into range (0 when there are stacks, else -1).
    static func clampedStackIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return -1 }
        return min(max(index, 0), count - 1)
    }
}

// MARK: - Clipboard

enum CueClipboard {
    /// Private pasteboard type so cue data never lands as JSON in other apps.
    static let cueType = NSPasteboard.PasteboardType("org.nebulacreative.cuetocue.cues")

    /// Write cues as the private type plus tab-separated text for other apps
    /// (Numbers, Excel, Notes, email).
    static func write(_ cues: [Cue], columnCount: Int, to pasteboard: NSPasteboard = .general) {
        guard !cues.isEmpty,
              let data = try? JSONEncoder().encode(MultiCueTransfer(cues: cues, columnCount: columnCount)) else { return }
        pasteboard.clearContents()
        pasteboard.declareTypes([cueType, .string], owner: nil)
        pasteboard.setData(data, forType: cueType)
        pasteboard.setString(plainText(for: cues), forType: .string)
    }

    /// Read cues from the private type, falling back to the legacy format
    /// (JSON stored as plain text by older builds).
    static func read(from pasteboard: NSPasteboard = .general) -> [Cue]? {
        let decoder = JSONDecoder()
        if let data = pasteboard.data(forType: cueType),
           let transfer = try? decoder.decode(MultiCueTransfer.self, from: data) {
            return transfer.cues
        }
        guard let data = pasteboard.data(forType: .string) else { return nil }
        if let transfer = try? decoder.decode(MultiCueTransfer.self, from: data) {
            return transfer.cues
        }
        if let single = try? decoder.decode(TransferCue.self, from: data) {
            return [single.cue]
        }
        if let cue = try? decoder.decode(Cue.self, from: data) {
            return [cue]
        }
        return nil
    }

    static func plainText(for cues: [Cue]) -> String {
        cues.map { cue in
            cue.values
                .map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
                .joined(separator: "\t")
        }
        .joined(separator: "\n")
    }
}
