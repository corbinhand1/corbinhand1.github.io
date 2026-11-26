//
//  RemoteOpsTests.swift
//  Cue to CueTests
//
//  Structural edits sent by the iPhone remote: insert, move, strike, timer,
//  delete, and column changes. The live cue must stay on the same cue.
//

import XCTest
@testable import Cue_to_Cue

@MainActor
final class RemoteOpsTests: XCTestCase {

    private func makeSync() -> (DataSyncManager, UUID) {
        let sync = DataSyncManager()
        let cues = (1...4).map { Cue(values: ["\($0)", "Cue \($0)", "x\($0)"]) }
        let stack = CueStack(name: "S", cues: cues,
                             columns: [Column(name: "#", width: 50), Column(name: "Description", width: 200), Column(name: "Audio", width: 100)])
        sync.cueStacks = [stack]
        sync.selectedCueStackIndex = 0
        return (sync, stack.id)
    }

    private func apply(_ sync: DataSyncManager, _ op: [String: Any]) -> Result<UUID?, RemoteOpError> {
        sync.applyRemoteOpSync(op)
    }

    func testInsertAtIndexPadsValuesAndReturnsId() throws {
        let (sync, sid) = makeSync()
        let result = apply(sync, ["op": "insert", "cueStackId": sid.uuidString, "index": 1, "values": ["9"]])
        let id = try XCTUnwrap(try result.get())
        XCTAssertEqual(sync.cueStacks[0].cues[1].id, id)
        XCTAssertEqual(sync.cueStacks[0].cues[1].values, ["9", "", ""])
        XCTAssertEqual(sync.cueStacks[0].cues.count, 5)
    }

    func testInsertWithExplicitIdRestoresDeletedCueAndRejectsDuplicates() throws {
        let (sync, sid) = makeSync()
        let victim = sync.cueStacks[0].cues[2]
        XCTAssertNoThrow(try apply(sync, ["op": "delete", "cueIds": [victim.id.uuidString]]).get())
        XCTAssertEqual(sync.cueStacks[0].cues.count, 3)
        let op: [String: Any] = ["op": "insert", "cueStackId": sid.uuidString, "index": 2, "cueId": victim.id.uuidString,
                                 "values": victim.values, "isStruckThrough": true]
        XCTAssertNoThrow(try apply(sync, op).get())
        XCTAssertEqual(sync.cueStacks[0].cues[2].id, victim.id)
        XCTAssertTrue(sync.cueStacks[0].cues[2].isStruckThrough)
        XCTAssertThrowsError(try apply(sync, op).get())   // same id again
    }

    func testMoveKeepsLiveCueOnTheSameCue() throws {
        let (sync, _) = makeSync()
        sync.activeCueIndex = 1                      // "Cue 2" is live
        let live = sync.cueStacks[0].cues[1].id
        // Move the last cue to the top; Cue 2 slides to index 2.
        XCTAssertNoThrow(try apply(sync, ["op": "move", "cueId": sync.cueStacks[0].cues[3].id.uuidString, "toIndex": 0]).get())
        XCTAssertEqual(sync.cueStacks[0].cues[sync.activeCueIndex].id, live)
        XCTAssertEqual(sync.cueStacks[0].cues.map(\.values.first), ["4", "1", "2", "3"])
    }

    func testInsertBeforeLiveCueShiftsLiveIndex() throws {
        let (sync, sid) = makeSync()
        sync.activeCueIndex = 0
        let live = sync.cueStacks[0].cues[0].id
        XCTAssertNoThrow(try apply(sync, ["op": "insert", "cueStackId": sid.uuidString, "index": 0, "values": []]).get())
        XCTAssertEqual(sync.cueStacks[0].cues[sync.activeCueIndex].id, live)
        XCTAssertEqual(sync.activeCueIndex, 1)
    }

    func testStrikeAndTimer() throws {
        let (sync, _) = makeSync()
        let ids = sync.cueStacks[0].cues.prefix(2).map { $0.id.uuidString }
        XCTAssertNoThrow(try apply(sync, ["op": "strike", "cueIds": ids, "struck": true]).get())
        XCTAssertEqual(sync.cueStacks[0].cues.map(\.isStruckThrough), [true, true, false, false])
        XCTAssertNoThrow(try apply(sync, ["op": "timer", "cueId": ids[0], "timerValue": "00:30"]).get())
        XCTAssertEqual(sync.cueStacks[0].cues[0].timerValue, "00:30")
    }

    func testBulkDeleteAndUnknownCue() {
        let (sync, _) = makeSync()
        let ids = sync.cueStacks[0].cues.prefix(2).map { $0.id.uuidString }
        XCTAssertNoThrow(try apply(sync, ["op": "delete", "cueIds": ids]).get())
        XCTAssertEqual(sync.cueStacks[0].cues.count, 2)
        XCTAssertThrowsError(try apply(sync, ["op": "delete", "cueIds": [UUID().uuidString]]).get())
        XCTAssertThrowsError(try apply(sync, ["op": "bogus"]).get())
    }

    func testColumnOpsKeepEveryCueInStep() throws {
        let (sync, sid) = makeSync()
        let s = sid.uuidString
        XCTAssertNoThrow(try apply(sync, ["op": "addColumn", "cueStackId": s, "name": "LX", "index": 1]).get())
        XCTAssertEqual(sync.cueStacks[0].columns.map(\.name), ["#", "LX", "Description", "Audio"])
        XCTAssertEqual(sync.cueStacks[0].cues[0].values, ["1", "", "Cue 1", "x1"])

        XCTAssertNoThrow(try apply(sync, ["op": "renameColumn", "cueStackId": s, "columnIndex": 1, "name": "Lights"]).get())
        XCTAssertEqual(sync.cueStacks[0].columns[1].name, "Lights")

        XCTAssertNoThrow(try apply(sync, ["op": "moveColumn", "cueStackId": s, "from": 3, "to": 1]).get())
        XCTAssertEqual(sync.cueStacks[0].columns.map(\.name), ["#", "Audio", "Lights", "Description"])
        XCTAssertEqual(sync.cueStacks[0].cues[0].values, ["1", "x1", "", "Cue 1"])

        XCTAssertNoThrow(try apply(sync, ["op": "deleteColumn", "cueStackId": s, "columnIndex": 2]).get())
        XCTAssertEqual(sync.cueStacks[0].cues[0].values, ["1", "x1", "Cue 1"])
        XCTAssertTrue(sync.cueStacks[0].cues.allSatisfy { $0.values.count == sync.cueStacks[0].columns.count })
    }

    func testCannotDeleteLastColumn() {
        let (sync, sid) = makeSync()
        for _ in 0..<2 { _ = apply(sync, ["op": "deleteColumn", "cueStackId": sid.uuidString, "columnIndex": 0]) }
        XCTAssertEqual(sync.cueStacks[0].columns.count, 1)
        XCTAssertThrowsError(try apply(sync, ["op": "deleteColumn", "cueStackId": sid.uuidString, "columnIndex": 0]).get())
    }
}


// MARK: - Security of the remote interface

final class RemoteSecurityTests: XCTestCase {
    func testIdentityProofIsDeterministicKeyedAndTokenSpecific() {
        let a = AuthenticationManager.identityProof(token: "tokenA", nonce: "0123456789abcdef")
        XCTAssertEqual(a, AuthenticationManager.identityProof(token: "tokenA", nonce: "0123456789abcdef"))
        XCTAssertNotEqual(a, AuthenticationManager.identityProof(token: "tokenB", nonce: "0123456789abcdef"))
        XCTAssertNotEqual(a, AuthenticationManager.identityProof(token: "tokenA", nonce: "fedcba9876543210"))
        XCTAssertEqual(a.count, 64)
        // The key id must not reveal the token.
        XCTAssertFalse(AuthenticationManager.tokenID("tokenA").contains("tokenA"))
    }

    func testTailscaleAddressRange() {
        XCTAssertTrue(NetworkUtilities.isTailscaleAddress("100.64.0.1"))
        XCTAssertTrue(NetworkUtilities.isTailscaleAddress("100.101.2.3"))
        XCTAssertTrue(NetworkUtilities.isTailscaleAddress("100.127.255.254"))
        XCTAssertFalse(NetworkUtilities.isTailscaleAddress("100.63.0.1"))
        XCTAssertFalse(NetworkUtilities.isTailscaleAddress("100.128.0.1"))
        XCTAssertFalse(NetworkUtilities.isTailscaleAddress("192.168.1.211"))
        XCTAssertFalse(NetworkUtilities.isTailscaleAddress("not an ip"))
    }
}
