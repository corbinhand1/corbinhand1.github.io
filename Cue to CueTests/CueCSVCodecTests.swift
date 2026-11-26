//
//  CueCSVCodecTests.swift
//  Cue to CueTests
//

import XCTest
@testable import Cue_to_Cue

final class CueCSVCodecTests: XCTestCase {

    func testRoundTripSingleStack() throws {
        let stack = CueStack(
            name: "BOS Keynote",
            cues: [
                Cue(values: ["104", "Doors", "29"], timerValue: "10:00", isStruckThrough: false),
                Cue(values: ["105", "Show Start", "2"], timerValue: "14:00", isStruckThrough: true),
            ],
            columns: [
                Column(name: "#", width: 50),
                Column(name: "Description", width: 200),
                Column(name: "Preset", width: 100),
            ]
        )

        let data = CueCSVCodec.encode(stacks: [stack])
        let result = try CueCSVCodec.decode(data: data)

        XCTAssertEqual(result.stacks.count, 1, "Warnings: \(result.warnings)")
        XCTAssertTrue(CueCSVCodec.cueDataMatches([stack], result.stacks))
    }

    func testRoundTripMultipleStacks() throws {
        let stackA = CueStack(
            name: "NYC Keynote",
            cues: [Cue(values: ["A1", "Line one"], timerValue: "", isStruckThrough: false)],
            columns: [Column(name: "#", width: 50), Column(name: "Description", width: 200)]
        )
        let stackB = CueStack(
            name: "LHR Keynote",
            cues: [Cue(values: ["B1", "Line two", "Audio"], timerValue: "5:00", isStruckThrough: false)],
            columns: [
                Column(name: "#", width: 50),
                Column(name: "Description", width: 200),
                Column(name: "Audio", width: 100),
            ]
        )

        let data = CueCSVCodec.encode(stacks: [stackA, stackB])
        let result = try CueCSVCodec.decode(data: data)

        XCTAssertEqual(result.stacks.count, 2)
        XCTAssertTrue(CueCSVCodec.cueDataMatches([stackA, stackB], result.stacks))
        XCTAssertEqual(result.stacks[0].columns.map(\.name), ["#", "Description"])
        XCTAssertEqual(result.stacks[1].columns.map(\.name), ["#", "Description", "Audio"])
    }

    func testImportDoesNotAddUnionColumnsToStacksWithoutData() throws {
        let bos = CueStack(
            name: "BOS Keynote",
            cues: [
                Cue(values: ["104", "Doors", "29"], timerValue: "10:00", isStruckThrough: false),
            ],
            columns: [
                Column(name: "#", width: 50),
                Column(name: "Description", width: 200),
                Column(name: "Preset", width: 100),
            ]
        )
        let lhr = CueStack(
            name: "LHR Keynote",
            cues: [
                Cue(values: ["201", "Walk in", "Rock", "Lopping GFX"], timerValue: "", isStruckThrough: false),
            ],
            columns: [
                Column(name: "#", width: 50),
                Column(name: "Description", width: 200),
                Column(name: "Audio", width: 100),
                Column(name: "Video", width: 100),
            ]
        )

        let result = try CueCSVCodec.decode(data: CueCSVCodec.encode(stacks: [bos, lhr]))

        XCTAssertEqual(result.stacks[0].columns.map(\.name), ["#", "Description", "Preset"])
        XCTAssertEqual(result.stacks[1].columns.map(\.name), ["#", "Description", "Audio", "Video"])
        XCTAssertFalse(result.stacks[0].columns.contains(where: { $0.name == "Audio" }))
        XCTAssertFalse(result.stacks[0].columns.contains(where: { $0.name == "Video" }))
    }

    func testQuotedFieldsWithCommas() throws {
        let stack = CueStack(
            name: "Test",
            cues: [
                Cue(values: ["1", "Doors, Walk in Music, Walk in Lx", "29"], timerValue: "", isStruckThrough: false),
            ],
            columns: [
                Column(name: "#", width: 50),
                Column(name: "Description", width: 200),
                Column(name: "Preset", width: 100),
            ]
        )

        let data = CueCSVCodec.encode(stacks: [stack])
        let csv = String(data: data, encoding: .utf8)!
        XCTAssertTrue(csv.contains("\"Doors, Walk in Music, Walk in Lx\""))

        let result = try CueCSVCodec.decode(data: data)
        XCTAssertTrue(CueCSVCodec.cueDataMatches([stack], result.stacks))
    }

    func testDecodeWithoutVersionComment() throws {
        let csv = """
        Cue Stack,Description,Timer,Strikethrough
        "Legacy Stack","Hello","01:00","FALSE"

        """
        let result = try CueCSVCodec.decode(data: Data(csv.utf8))
        XCTAssertEqual(result.stacks.count, 1)
        XCTAssertEqual(result.stacks[0].name, "Legacy Stack")
        XCTAssertEqual(result.stacks[0].cues[0].values, ["Hello"])
        XCTAssertEqual(result.stacks[0].cues[0].timerValue, "01:00")
    }

    func testUTF8BOM() throws {
        let stack = CueStack(
            name: "BOM Test",
            cues: [Cue(values: ["x"], timerValue: "", isStruckThrough: false)],
            columns: [Column(name: "Description", width: 100)]
        )
        let data = CueCSVCodec.encode(stacks: [stack], options: CueCSVExportOptions(includeVersionComment: false, includeUTF8BOM: true))
        XCTAssertTrue(data.starts(with: [0xEF, 0xBB, 0xBF]))

        let result = try CueCSVCodec.decode(data: data)
        XCTAssertEqual(result.stacks[0].name, "BOM Test")
    }

    func testRowFieldCountMismatchThrows() {
        let csv = """
        Cue Stack,Description,Timer,Strikethrough
        "Only","Three","Columns"

        """
        XCTAssertThrowsError(try CueCSVCodec.decode(data: Data(csv.utf8))) { error in
            guard case CueCSVError.rowFieldCountMismatch(let line, let expected, let found) = error else {
                return XCTFail("Expected rowFieldCountMismatch, got \(error)")
            }
            XCTAssertEqual(line, 2)
            XCTAssertEqual(expected, 4)
            XCTAssertEqual(found, 3)
        }
    }

    func testParseRecordsCRLFLineEndings() {
        let csv = "# Cue to Cue CSV v1\r\nCue Stack,Description\r\nStack A,Hello\r\n"
        let records = CueCSVCodec.parseRecords(from: csv)
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0], ["# Cue to Cue CSV v1"])
        XCTAssertEqual(records[1], ["Cue Stack", "Description"])
        XCTAssertEqual(records[2], ["Stack A", "Hello"])
    }

    func testParseRecordsEmbeddedNewlineInQuotes() {
        let csv = "a,\"line1\nline2\",b\n"
        let records = CueCSVCodec.parseRecords(from: csv)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0], ["a", "line1\nline2", "b"])
    }

    func testStacksForAddRenamesDuplicateNames() {
        let imported = [
            CueStack(name: "BOS Keynote", cues: [Cue(values: ["1"], timerValue: "", isStruckThrough: false)], columns: [Column(name: "#", width: 50)]),
            CueStack(name: "BOS Keynote", cues: [Cue(values: ["2"], timerValue: "", isStruckThrough: false)], columns: [Column(name: "#", width: 50)]),
        ]

        let result = CueCSVCodec.stacksForAdd(imported: imported, existingNames: ["BOS Keynote"])

        XCTAssertEqual(result.map(\.name), ["BOS Keynote (2)", "BOS Keynote (3)"])
    }

    func testMergedStackUnionsColumnsAndAppendsCues() {
        let existing = CueStack(
            name: "BOS Keynote",
            cues: [Cue(values: ["100", "Doors"], timerValue: "10:00", isStruckThrough: false)],
            columns: [Column(name: "#", width: 50), Column(name: "Description", width: 200)]
        )
        let imported = CueStack(
            name: "Imported",
            cues: [Cue(values: ["Walk in", "Rock"], timerValue: "", isStruckThrough: true)],
            columns: [Column(name: "Description", width: 200), Column(name: "Audio", width: 100)]
        )

        let merged = CueCSVCodec.mergedStack(existing: existing, imported: imported)

        XCTAssertEqual(merged.name, "BOS Keynote")
        XCTAssertEqual(merged.columns.map(\.name), ["#", "Description", "Audio"])
        XCTAssertEqual(merged.cues.count, 2)
        XCTAssertEqual(merged.cues[0].values, ["100", "Doors", ""])
        XCTAssertEqual(merged.cues[1].values, ["", "Walk in", "Rock"])
        XCTAssertEqual(merged.cues[1].isStruckThrough, true)
    }
}
