//
//  FindReplaceTests.swift
//  Cue to CueTests
//

import XCTest
@testable import Cue_to_Cue

final class FindReplaceTests: XCTestCase {
    private func stacks() -> [CueStack] {
        [
            CueStack(name: "Main", cues: [
                Cue(values: ["201", "Preset 29 & FLS", "29"], timerValue: ""),
                Cue(values: ["29", "Golden Hoodie Moment", "290"], timerValue: "2:29"),
            ], columns: [Column(name: "#", width: 50), Column(name: "Description", width: 300), Column(name: "Preset", width: 60)]),
            CueStack(name: "Other", cues: [Cue(values: ["1", "preset 29", "29"])],
                     columns: [Column(name: "#", width: 50), Column(name: "Description", width: 300), Column(name: "Preset", width: 60)]),
        ]
    }

    func testExactWholeWordSkipsLongerNumbers() {
        let all = stacks()
        let edits = CueFindReplace.literal(find: "29", replace: "25", matchCase: false, wholeWord: true,
                                           in: all, scope: [all[0].id])
        XCTAssertEqual(edits.map(\.newText), ["Preset 25 & FLS", "25", "25", "2:25"],
                       "whole words: 290 is left alone; the other stack is out of scope")
        XCTAssertEqual(edits.last?.columnName, "Timer")
    }

    func testExactCaseAndApplyIsGuarded() {
        var all = stacks()
        let edits = CueFindReplace.literal(find: "golden hoodie", replace: "Hoodie", matchCase: false, wholeWord: false,
                                           in: all, scope: Set(all.map(\.id)))
        XCTAssertEqual(edits.map(\.newText), ["Hoodie Moment"])
        XCTAssertTrue(CueFindReplace.literal(find: "golden hoodie", replace: "x", matchCase: true, wholeWord: false,
                                             in: all, scope: Set(all.map(\.id))).isEmpty)

        // A cell edited after the preview isn't overwritten.
        var stale = all
        stale[0].cues[1].values[1] = "Changed meanwhile"
        XCTAssertEqual(CueFindReplace.apply(edits, to: &stale), 0)
        XCTAssertEqual(CueFindReplace.apply(edits, to: &all), 1)
        XCTAssertEqual(all[0].cues[1].values[1], "Hoodie Moment")
    }

    func testSmartRequestAndAnswerMapping() throws {
        let all = stacks()
        let request = CueFindReplace.smartRequest(instruction: "preset 29 to 25", stacks: all, scope: Set(all.map(\.id)))
        let system = try XCTUnwrap(request.body["system"] as? [[String: Any]])
        let sheet = try XCTUnwrap(system.last?["text"] as? String)
        XCTAssertTrue(sheet.contains("Ref | # | Description | Preset | Timer"))
        XCTAssertTrue(sheet.contains("R1 | 201 | Preset 29 & FLS | 29 | "))
        XCTAssertNotNil(system.last?["cache_control"])
        XCTAssertEqual((request.body["output_config"] as? [String: Any])?["effort"] as? String, "medium")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(request.body))

        let answer = CueFindReplace.SmartAnswer(summary: "Changed 3.", edits: [
            .init(ref: "R1", column: "Description", newText: "Preset 25 & FLS"),
            .init(ref: "R1", column: "preset", newText: "25"),
            .init(ref: "R1", column: "Preset", newText: "26"),          // duplicate cell: first wins
            .init(ref: "R3", column: "Description", newText: "preset 25"),
            .init(ref: "R2", column: "Timer", newText: "2:29"),        // no change: dropped
            .init(ref: "R99", column: "Description", newText: "x"),    // unknown row: dropped
            .init(ref: "R1", column: "Nope", newText: "x"),            // unknown column: dropped
        ])
        let edits = CueFindReplace.edits(from: answer, refs: request.refs, stacks: all)
        XCTAssertEqual(edits.map(\.newText), ["Preset 25 & FLS", "25", "preset 25"])
        XCTAssertEqual(edits.map(\.cueLabel), ["Cue 201", "Cue 201", "Cue 1"])
        XCTAssertEqual(edits[2].stackName, "Other")
    }
}
