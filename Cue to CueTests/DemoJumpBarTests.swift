//
//  DemoJumpBarTests.swift
//  Cue to CueTests
//

import XCTest
@testable import Cue_to_Cue

final class DemoJumpBarTests: XCTestCase {
    private let rules = [
        HighlightColorSetting(keyword: "video", color: .blue),
        HighlightColorSetting(keyword: "demo", color: .red),
    ]

    private func stack(_ rows: [(String, String, Bool)]) -> CueStack {
        CueStack(name: "Main",
                 cues: rows.map { var c = Cue(values: [$0.0, $0.1], timerValue: ""); c.isStruckThrough = $0.2; return c },
                 columns: [Column(name: "#", width: 50), Column(name: "Description", width: 300)])
    }

    func testGroupsConsecutiveDemoCuesAndNamesThem() {
        let s = stack([
            ("1", "Walk in", false),
            ("2", "DEMO: Cars 1 [on applause]", false),
            ("", "demo cars b-roll", false),
            ("3", "Speaker", false),
            ("4", "Demo - Robots", false),
        ])
        let groups = CueJumpGroups.groups(stack: s, rules: rules, ruleIndex: 1)
        XCTAssertEqual(groups.map(\.number), [1, 2])
        XCTAssertEqual(groups[0].cueIndices, [1, 2])
        XCTAssertEqual(groups[0].name, "Cars 1")
        XCTAssertEqual(groups[0].cueNumber, "2")
        XCTAssertEqual(groups[1].name, "Robots")
        XCTAssertEqual(groups[1].firstIndex, 4)
        XCTAssertEqual(groups.map(\.shortName), ["Cars", "Robots"])
    }

    func testShortNameIsFirstWordAfterDemo() {
        let s = stack([("1", "DEMO: Adecco 1 & Mac 1 Audio Hot [Now]", false), ("2", "Talk", false),
                       ("3", "Demo: Cars, part 2", false)])
        XCTAssertEqual(CueJumpGroups.groups(stack: s, rules: rules, ruleIndex: 1).map(\.shortName), ["Adecco", "Cars"])
    }

    func testVideoCueTakesPrecedenceLikeTheRowColors() {
        // "video" is the first rule, so a cue mentioning both is a video cue.
        let s = stack([("1", "Demo video roll", false), ("2", "Demo: Live", false)])
        XCTAssertEqual(CueJumpGroups.groups(stack: s, rules: rules, ruleIndex: 1).map(\.firstIndex), [1])
    }

    func testAllStruckGroupIsLeftOut() {
        let s = stack([("1", "Demo: Cut", true), ("2", "Talk", false), ("3", "Demo: Kept", false)])
        let groups = CueJumpGroups.groups(stack: s, rules: rules, ruleIndex: 1)
        XCTAssertEqual(groups.map(\.name), ["Kept"])
        XCTAssertEqual(groups.map(\.number), [1])
    }

    func testDefaultRulePrefersSavedThenDemo() {
        let s = stack([("1", "Video: Open", false), ("2", "Talk", false), ("3", "Demo: A", false)])
        XCTAssertEqual(CueJumpGroups.defaultRule(stack: s, rules: rules, saved: "nothing"), 1)
        XCTAssertEqual(CueJumpGroups.defaultRule(stack: s, rules: rules, saved: "video"), 0)
        let noDemos = stack([("1", "Video: Open", false)])
        XCTAssertEqual(CueJumpGroups.defaultRule(stack: noDemos, rules: rules, saved: "demo"), 0)
        XCTAssertNil(CueJumpGroups.defaultRule(stack: stack([("1", "Talk", false)]), rules: rules, saved: "demo"))
    }
}
