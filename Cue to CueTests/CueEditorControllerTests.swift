//
//  CueEditorControllerTests.swift
//  Cue to CueTests
//
//  End-to-end editing tests: CueEditorController driving a real
//  DataSyncManager, the same pairing the app uses.
//

import XCTest
import AppKit
@testable import Cue_to_Cue

@MainActor
final class CueEditorControllerTests: XCTestCase {

    private var data: DataSyncManager!
    private var editor: CueEditorController!
    private var pasteboard: NSPasteboard!
    private var beeps = 0
    private var webNotifications = 0
    private var timerResets: [Int] = []

    override func setUp() async throws {
        data = DataSyncManager()
        data.cueStacks = [
            Self.stack("Main", ["1", "2", "3", "4"]),
            Self.stack("Alt", ["a", "b"]),
        ]
        data.selectedCueStackIndex = 0
        data.selectedCueIndex = -1

        editor = CueEditorController(data: data)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("CueEditorControllerTests-\(UUID().uuidString)"))
        editor.pasteboard = pasteboard
        beeps = 0
        webNotifications = 0
        timerResets = []
        editor.beep = { [unowned self] in beeps += 1 }
        editor.notifyWebClients = { [unowned self] in webNotifications += 1 }
        editor.onCueTimerSelected = { [unowned self] in timerResets.append($0) }
        editor.resetHistory()
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private static func stack(_ name: String, _ cueNames: [String]) -> CueStack {
        CueStack(
            name: name,
            cues: cueNames.map { Cue(values: [$0, ""]) },
            columns: [Column(name: "#", width: 60), Column(name: "Description", width: 200)]
        )
    }

    private func names(_ stackIndex: Int = 0) -> [String] {
        data.cueStacks[stackIndex].cues.map { $0.values[0] }
    }

    private func click(_ index: Int, shift: Bool = false, command: Bool = false) {
        editor.handleCueSelection(at: index, withShiftKey: shift, withCommandKey: command)
    }

    // MARK: Selection

    func testClickSelectsSingleCue() {
        click(2)
        XCTAssertEqual(data.selectedCueIndex, 2)
        XCTAssertEqual(editor.selectedCueIndices, [2])
        XCTAssertFalse(editor.isMultiSelectMode)
    }

    func testShiftClickSelectsRange() {
        click(1)
        click(3, shift: true)
        XCTAssertEqual(editor.selectedCueIndices, [1, 2, 3])
        XCTAssertEqual(editor.selectedIndicesForCommand(), [1, 2, 3])
    }

    func testCommandClickToggles() {
        click(0)
        click(2, command: true)
        XCTAssertEqual(editor.selectedCueIndices, [0, 2])
        click(2, command: true)
        XCTAssertEqual(editor.selectedCueIndices, [0])
    }

    func testClickOutOfRangeIsIgnored() {
        click(99)
        XCTAssertEqual(data.selectedCueIndex, -1)
    }

    // MARK: Editing

    func testAddCueIsUndoable() {
        editor.addCue()
        XCTAssertEqual(data.cueStacks[0].cues.count, 5)
        XCTAssertEqual(data.cueStacks[0].cues[4].values.count, 2)
        editor.undo()
        XCTAssertEqual(data.cueStacks[0].cues.count, 4)
        editor.redo()
        XCTAssertEqual(data.cueStacks[0].cues.count, 5)
    }

    func testDeleteSingleSelectedCue() {
        click(1)
        editor.deleteSelectedCues()
        XCTAssertEqual(names(), ["1", "3", "4"])
        XCTAssertEqual(data.selectedCueIndex, 1, "selection moves to the cue that took its place")
        editor.undo()
        XCTAssertEqual(names(), ["1", "2", "3", "4"])
    }

    func testDeleteMultiSelection() {
        click(0)
        click(2, command: true)
        editor.deleteSelectedCues()
        XCTAssertEqual(names(), ["2", "4"])
    }

    func testCutThenPaste() {
        click(0)
        editor.cutSelection()
        XCTAssertEqual(names(), ["2", "3", "4"])
        click(2)
        editor.paste()
        XCTAssertEqual(names(), ["2", "3", "4", "1"])
        XCTAssertEqual(data.selectedCueIndex, 3)
    }

    func testCopyPasteCreatesNewIDs() {
        click(0)
        editor.copySelection()
        editor.paste()
        XCTAssertEqual(names(), ["1", "1", "2", "3", "4"])
        let ids = data.cueStacks[0].cues.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testPasteIntoEmptyStack() {
        click(0)
        editor.copySelection()
        data.cueStacks.append(Self.stack("Empty", []))
        data.selectedCueStackIndex = 2
        data.selectedCueIndex = -1
        editor.paste()
        XCTAssertEqual(names(2), ["1"])
    }

    func testPasteWithEmptyClipboardBeeps() {
        pasteboard.clearContents()
        pasteboard.setString("not cues", forType: .string)
        click(0)
        editor.paste()
        XCTAssertEqual(beeps, 1)
        XCTAssertEqual(names(), ["1", "2", "3", "4"])
    }

    func testToggleStrikeThroughOnSelection() {
        click(1)
        click(2, shift: true)
        editor.toggleStrikeThrough()
        XCTAssertEqual(data.cueStacks[0].cues.map(\.isStruckThrough), [false, true, true, false])
        editor.toggleStrikeThrough()
        XCTAssertEqual(data.cueStacks[0].cues.map(\.isStruckThrough), [false, false, false, false])
    }

    // MARK: Undo across stacks (the Phase 1 data-loss bug, end to end)

    func testUndoAfterSwitchingStacksLeavesOtherStackAlone() {
        click(0)
        editor.deleteSelectedCues()           // edit Main
        data.selectedCueStackIndex = 1        // switch to Alt
        editor.undo()
        XCTAssertEqual(names(0), ["1", "2", "3", "4"])
        XCTAssertEqual(names(1), ["a", "b"])
    }

    func testUndoRemovesUntrackedNewStack() {
        data.cueStacks.append(Self.stack("New", []))
        data.selectedCueStackIndex = 2
        editor.undo()
        XCTAssertEqual(data.cueStacks.map(\.name), ["Main", "Alt"])
        XCTAssertEqual(data.selectedCueStackIndex, 1, "selection is clamped back into range")
    }

    func testUndoWithNothingToUndoBeeps() {
        editor.undo()
        XCTAssertEqual(beeps, 1)
    }

    // MARK: Navigation

    func testAdvanceSkipsStruckThroughCues() {
        data.cueStacks[0].cues[1].isStruckThrough = true
        click(0)
        editor.advanceCue()
        XCTAssertEqual(data.selectedCueIndex, 2)
        XCTAssertEqual(editor.selectedCueIndices, [2], "table highlight follows the playhead")
        editor.previousCue()
        XCTAssertEqual(data.selectedCueIndex, 0)
    }

    func testAdvanceAtEndStays() {
        click(3)
        editor.advanceCue()
        XCTAssertEqual(data.selectedCueIndex, 3)
    }

    func testSelectingCueWithTimerResetsCountdown() {
        data.cueStacks[0].cues[2].timerValue = "1:30"
        click(2)
        XCTAssertEqual(timerResets, [90])
        XCTAssertEqual(editor.selectedCueTime, 90)
    }

    // MARK: Robustness with no valid stack

    func testActionsWithInvalidStackDoNotCrash() {
        data.selectedCueStackIndex = -1
        editor.addCue()
        editor.advanceCue()
        editor.previousCue()
        editor.deleteSelectedCues()
        editor.paste()
        editor.selectAll()
        editor.toggleStrikeThrough()
        click(0)
        XCTAssertEqual(beeps, 1, "only addCue reports failure audibly")
        XCTAssertEqual(data.cueStacks[0].cues.count, 4)
    }

    // MARK: Time parsing

    func testParseCountdownTime() {
        XCTAssertEqual(CueEditorController.parseCountdownTime("45"), 45)
        XCTAssertEqual(CueEditorController.parseCountdownTime("2:05"), 125)
        XCTAssertEqual(CueEditorController.parseCountdownTime("1:00:00"), 3600)
        XCTAssertNil(CueEditorController.parseCountdownTime(""))
        XCTAssertNil(CueEditorController.parseCountdownTime("1:xx"), "garbage must not be read as a partial time")
        XCTAssertNil(CueEditorController.parseCountdownTime("1:2:3:4"))
    }
}
