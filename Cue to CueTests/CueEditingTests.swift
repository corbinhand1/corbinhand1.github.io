//
//  CueEditingTests.swift
//  Cue to CueTests
//
//  Regression tests for undo, paste, delete, duplicate, stack reordering,
//  ID repair and the cue clipboard.
//

import XCTest
import AppKit
@testable import Cue_to_Cue

final class CueEditingTests: XCTestCase {

    private func stack(_ name: String, _ cueNames: [String], columns: Int = 2) -> CueStack {
        CueStack(
            name: name,
            cues: cueNames.map { Cue(values: [$0] + Array(repeating: "", count: max(0, columns - 1))) },
            columns: (0..<columns).map { Column(name: "C\($0)", width: 100) }
        )
    }

    private func names(_ stack: CueStack) -> [String] {
        stack.cues.map { $0.values.first ?? "" }
    }

    // MARK: Undo

    /// The original bug: edit A, switch to B, undo -> B was overwritten with A's cues.
    func testUndoAfterSwitchingStacksDoesNotOverwriteOtherStack() {
        var doc = [stack("A", ["a1"]), stack("B", ["b1", "b2"])]
        var history = CueUndoHistory()
        history.reset(to: doc)

        doc[0].cues.append(Cue(values: ["a2", ""]))
        history.record(doc)

        // User switches to stack B (selection only) and presses Undo.
        let restored = history.undo(current: doc)
        XCTAssertEqual(restored.map { names($0[0]) }, ["a1"])
        XCTAssertEqual(restored.map { names($0[1]) }, ["b1", "b2"])
    }

    func testUndoRedoRoundTrip() {
        var doc = [stack("A", ["1"])]
        var history = CueUndoHistory()
        history.reset(to: doc)
        doc[0].cues.append(Cue(values: ["2", ""]))
        history.record(doc)
        doc[0].cues.append(Cue(values: ["3", ""]))
        history.record(doc)

        doc = history.undo(current: doc)!
        XCTAssertEqual(names(doc[0]), ["1", "2"])
        doc = history.undo(current: doc)!
        XCTAssertEqual(names(doc[0]), ["1"])
        XCTAssertNil(history.undo(current: doc))
        doc = history.redo(current: doc)!
        XCTAssertEqual(names(doc[0]), ["1", "2"])
    }

    /// Changes made without a snapshot (e.g. adding a stack) are undone as one step.
    func testUndoCapturesUntrackedChangesFirst() {
        var doc = [stack("A", ["1"])]
        var history = CueUndoHistory()
        history.reset(to: doc)
        doc.append(stack("New", []))

        let restored = history.undo(current: doc)
        XCTAssertEqual(restored?.count, 1)
        let redone = history.redo(current: restored!)
        XCTAssertEqual(redone?.count, 2)
    }

    func testNewEditClearsRedo() {
        var doc = [stack("A", ["1"])]
        var history = CueUndoHistory()
        history.reset(to: doc)
        doc[0].cues.append(Cue(values: ["2", ""]))
        history.record(doc)
        doc = history.undo(current: doc)!
        doc[0].cues.append(Cue(values: ["x", ""]))
        history.record(doc)
        XCTAssertFalse(history.canRedo)
    }

    func testHistoryLimit() {
        var doc = [stack("A", [])]
        var history = CueUndoHistory(limit: 5)
        history.reset(to: doc)
        for i in 0..<20 {
            doc[0].cues.append(Cue(values: ["\(i)", ""]))
            history.record(doc)
        }
        XCTAssertEqual(history.snapshots.count, 5)
        XCTAssertEqual(history.index, 4)
    }

    // MARK: Paste

    func testPasteGivesNewIDsAndFitsColumns() {
        var target = stack("T", ["t1", "t2"], columns: 3)
        let source = Cue(values: ["p", "x", "y", "z"])
        let last = CueEditing.paste([source, source], into: &target, after: 0)

        XCTAssertEqual(last, 2)
        XCTAssertEqual(names(target), ["t1", "p", "p", "t2"])
        XCTAssertTrue(target.cues.allSatisfy { $0.values.count == 3 })
        XCTAssertEqual(Set(target.cues.map(\.id)).count, 4, "every cue must have a unique ID")
        XCTAssertFalse(target.cues.contains { $0.id == source.id })
    }

    func testPasteIntoEmptyStackAppends() {
        var target = stack("T", [])
        let last = CueEditing.paste([Cue(values: ["p"])], into: &target, after: nil)
        XCTAssertEqual(last, 0)
        XCTAssertEqual(names(target), ["p"])
        XCTAssertEqual(target.cues[0].values.count, 2)
    }

    // MARK: Delete

    func testDeleteSingleSelectedCueSelectsNext() {
        var s = stack("S", ["1", "2", "3"])
        let sel = CueEditing.remove(indices: [1], from: &s, selected: 1)
        XCTAssertEqual(names(s), ["1", "3"])
        XCTAssertEqual(sel, 1)
    }

    func testDeleteLastCueSelectsNewLast() {
        var s = stack("S", ["1", "2", "3"])
        let sel = CueEditing.remove(indices: [2], from: &s, selected: 2)
        XCTAssertEqual(sel, 1)
    }

    func testDeleteBeforeSelectionShiftsSelection() {
        var s = stack("S", ["1", "2", "3", "4"])
        let sel = CueEditing.remove(indices: [0, 1], from: &s, selected: 3)
        XCTAssertEqual(names(s), ["3", "4"])
        XCTAssertEqual(sel, 1)
    }

    func testDeleteEverythingClearsSelection() {
        var s = stack("S", ["1", "2"])
        XCTAssertEqual(CueEditing.remove(indices: [0, 1], from: &s, selected: 0), -1)
    }

    // MARK: Duplicate / reorder / repair

    func testDuplicateStackHasFreshIDs() {
        let original = stack("Show", ["1", "2"])
        let copy = CueEditing.duplicate(original)
        XCTAssertEqual(copy.name, "Show Copy")
        XCTAssertEqual(names(copy), names(original))
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertTrue(Set(copy.cues.map(\.id)).isDisjoint(with: original.cues.map(\.id)))
        XCTAssertTrue(Set(copy.columns.map(\.id)).isDisjoint(with: original.columns.map(\.id)))
    }

    func testMovingSelectedStackUpKeepsSelection() {
        var stacks = [stack("A", []), stack("B", []), stack("C", [])]
        let sel = CueEditing.moveStacks(&stacks, from: IndexSet(integer: 2), to: 0, selected: 2)
        XCTAssertEqual(stacks.map(\.name), ["C", "A", "B"])
        XCTAssertEqual(stacks[sel].name, "C")
    }

    func testMovingOtherStackKeepsSelectionOnSameStack() {
        var stacks = [stack("A", []), stack("B", []), stack("C", [])]
        let sel = CueEditing.moveStacks(&stacks, from: IndexSet(integer: 0), to: 3, selected: 1)
        XCTAssertEqual(stacks[sel].name, "B")
    }

    func testClampedStackIndex() {
        XCTAssertEqual(CueEditing.clampedStackIndex(-1, count: 3), 0)
        XCTAssertEqual(CueEditing.clampedStackIndex(5, count: 3), 2)
        XCTAssertEqual(CueEditing.clampedStackIndex(0, count: 0), -1)
    }

    func testRepairDuplicateIDs() {
        let a = stack("A", ["1", "2"])
        var b = a                       // what old "Duplicate" produced
        b.name = "A Copy"
        let repaired = CueEditing.repairingDuplicateIDs([a, b])
        XCTAssertEqual(repaired[0], a, "first occurrence keeps its IDs")
        XCTAssertNotEqual(repaired[1].id, a.id)
        let allCueIDs = repaired.flatMap { $0.cues.map(\.id) }
        XCTAssertEqual(Set(allCueIDs).count, allCueIDs.count)
        XCTAssertEqual(names(repaired[1]), ["1", "2"])
    }

    // MARK: Clipboard

    func testClipboardRoundTripAndPlainText() {
        let pb = NSPasteboard(name: NSPasteboard.Name("CueEditingTests-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let cues = [Cue(values: ["1", "Doors"]), Cue(values: ["2", "Walk\tin"])]
        CueClipboard.write(cues, columnCount: 2, to: pb)

        XCTAssertEqual(CueClipboard.read(from: pb), cues)
        XCTAssertEqual(pb.string(forType: .string), "1\tDoors\n2\tWalk in")
    }

    func testClipboardReadsLegacyJSONString() throws {
        let pb = NSPasteboard(name: NSPasteboard.Name("CueEditingTests-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let cues = [Cue(values: ["legacy"])]
        let data = try JSONEncoder().encode(MultiCueTransfer(cues: cues, columnCount: 1))
        pb.clearContents()
        pb.setData(data, forType: .string)
        XCTAssertEqual(CueClipboard.read(from: pb), cues)
    }

    func testClipboardIgnoresOrdinaryText() {
        let pb = NSPasteboard(name: NSPasteboard.Name("CueEditingTests-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        pb.setString("just some text", forType: .string)
        XCTAssertNil(CueClipboard.read(from: pb))
    }
}
