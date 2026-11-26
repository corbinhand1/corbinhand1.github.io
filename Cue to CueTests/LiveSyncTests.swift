//
//  LiveSyncTests.swift
//  Cue to CueTests
//
//  WebSocket framing unit tests, plus live stress tests against a real
//  ConnectionManager + LANBroadcastHub listening on a random local port
//  (separate from the app's own server on 8080 and from the user's data).
//

import XCTest
import Network
@testable import Cue_to_Cue

// MARK: - Framing

final class LANFramingTests: XCTestCase {

    private func maskedClientFrame(opcode: UInt8, payload: Data, mask: [UInt8] = [1, 2, 3, 4]) -> Data {
        var frame = Data([0x80 | opcode])
        if payload.count < 126 {
            frame.append(0x80 | UInt8(payload.count))
        } else {
            frame.append(0x80 | 126)
            frame.append(UInt8(payload.count >> 8))
            frame.append(UInt8(payload.count & 0xFF))
        }
        frame.append(contentsOf: mask)
        for (i, byte) in payload.enumerated() { frame.append(byte ^ mask[i % 4]) }
        return frame
    }

    func testDecodesMaskedTextAndPing() {
        var buffer = maskedClientFrame(opcode: 0x1, payload: Data(#"{"type":"ping"}"#.utf8))
        buffer.append(maskedClientFrame(opcode: 0x9, payload: Data("hb".utf8)))
        let frames = LANWebSocketFraming.extractFrames(from: &buffer)
        XCTAssertEqual(frames.count, 2)
        if case .text(let text) = frames[0].kind { XCTAssertEqual(text, #"{"type":"ping"}"#) } else { XCTFail() }
        if case .ping(let data) = frames[1].kind { XCTAssertEqual(data, Data("hb".utf8)) } else { XCTFail() }
        XCTAssertTrue(buffer.isEmpty)
    }

    func testKeepsPartialFrameForNextRead() {
        let full = maskedClientFrame(opcode: 0x1, payload: Data(repeating: 0x41, count: 300))
        var buffer = full.prefix(100)
        XCTAssertTrue(LANWebSocketFraming.extractFrames(from: &buffer).isEmpty)
        buffer.append(full.dropFirst(100))
        XCTAssertEqual(LANWebSocketFraming.extractFrames(from: &buffer).count, 1)
    }

    /// Used to overflow Int and crash the app.
    func testHugeDeclaredLengthClosesInsteadOfCrashing() {
        var buffer = Data([0x81, 0xFF, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 1, 2, 3, 4])
        let frames = LANWebSocketFraming.extractFrames(from: &buffer)
        XCTAssertEqual(frames.count, 1)
        if case .close = frames[0].kind {} else { XCTFail("expected close") }
        XCTAssertTrue(buffer.isEmpty)
    }

    func testOversizedFrameCloses() {
        var buffer = Data([0x81, 0xFF])
        let length = UInt64(LANWebSocketFraming.maxClientFrameBytes + 1)
        for shift in stride(from: 56, through: 0, by: -8) { buffer.append(UInt8((length >> UInt64(shift)) & 0xFF)) }
        buffer.append(contentsOf: [1, 2, 3, 4])
        let frames = LANWebSocketFraming.extractFrames(from: &buffer)
        if case .close = frames.first?.kind {} else { XCTFail("expected close") }
    }

    func testServerTextFrameLengths() {
        for size in [5, 200, 70_000] {
            let frame = LANWebSocketFraming.encodeText(String(repeating: "x", count: size))!
            let header = size < 126 ? 2 : (size <= 0xFFFF ? 4 : 10)
            XCTAssertEqual(frame.count, header + size)
        }
    }
}

// MARK: - Live server

private struct ReceiveTimeout: Error, CustomStringConvertible {
    var description: String { "timed out waiting for a WebSocket message" }
}

final class LiveSyncStressTests: XCTestCase {

    private var data: DataSyncManager!
    private var timer: AuthoritativeTimerServer!
    private var hub: LANBroadcastHub!
    private var connections: ConnectionManager!
    private var listener: NWListener!
    private var port: UInt16 = 0
    private var session: URLSession!
    private var authDir: URL!

    override func setUp() async throws {
        try await MainActor.run {
            data = DataSyncManager()
            data.cueStacks = [CueStack(name: "Main", cues: [Cue(values: ["1", "Doors"])],
                                       columns: [Column(name: "#", width: 60), Column(name: "Description", width: 200)])]
            data.selectedCueStackIndex = 0
            timer = AuthoritativeTimerServer(startTicking: false)
            hub = LANBroadcastHub()
            hub.dataSyncManager = data
            hub.timerServer = timer
            data.broadcastHub = hub
            authDir = FileManager.default.temporaryDirectory.appendingPathComponent("CueToCueLiveSyncAuth-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: authDir, withIntermediateDirectories: true)
            let auth = AuthenticationManager(dataSyncManager: data, storageDirectory: authDir)
            let handler = HTTPHandler(dataSyncManager: data, offlineFileServer: OfflineFileServer(), networkUtilities: NetworkUtilities(),
                                      connectionManager: nil, authManager: auth, timerServer: timer)
            connections = ConnectionManager(httpHandler: handler, broadcastHub: hub)

            listener = try NWListener(using: .tcp, on: .any)
        }
        let ready = expectation(description: "listening")
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.newConnectionHandler = { [connections] in connections?.handleNewConnection($0) }
        listener.start(queue: .global())
        await fulfillment(of: [ready], timeout: 5)
        port = listener.port!.rawValue
        session = URLSession(configuration: .ephemeral)
    }

    override func tearDown() async throws {
        listener.cancel()
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: authDir)
    }

    // MARK: Helpers

    private func connect() -> URLSessionWebSocketTask {
        let task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
        task.resume()
        return task
    }

    /// Receive messages until one matches, or fail after `timeout`.
    @discardableResult
    private func receive(_ task: URLSessionWebSocketTask, timeout: TimeInterval = 5,
                         until match: @escaping ([String: Any]) -> Bool) async throws -> [String: Any] {
        try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask {
                while true {
                    let message = try await task.receive()
                    guard case .string(let text) = message,
                          let json = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { continue }
                    if match(json) { return json }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ReceiveTimeout()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func isSnapshot(_ json: [String: Any], containing text: String) -> Bool {
        guard json["type"] as? String == "snapshot",
              let payload = try? JSONSerialization.data(withJSONObject: json["data"] ?? [:]),
              let string = String(data: payload, encoding: .utf8) else { return false }
        return string.contains(text)
    }

    private func waitForClientCount(_ expected: Int, timeout: TimeInterval = 8) async -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var count = hub.webSocketClientCount
        while count != expected && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            count = hub.webSocketClientCount
        }
        return count
    }

    private func edit(_ change: @escaping @MainActor (DataSyncManager) -> Void) async {
        await MainActor.run {
            change(data)
            data.recordLANChange(kind: .snapshot)
        }
    }

    // MARK: Tests

    func testManyViewersGetInitialSnapshotAndEdits() async throws {
        let clients = (0..<10).map { _ in connect() }
        for client in clients {
            try await receive(client) { self.isSnapshot($0, containing: "Doors") }
        }
        let connectedCount = await waitForClientCount(10)
        XCTAssertEqual(connectedCount, 10)

        await edit { $0.cueStacks[0].cues[0].values[1] = "House to half" }
        for client in clients {
            try await receive(client) { self.isSnapshot($0, containing: "House to half") }
        }
    }

    /// Browsers that vanish without a close frame (tab killed, proxy reset)
    /// used to leave the server spinning on EOF and the client registered
    /// forever, eventually locking that device out (12 sockets per IP).
    func testAbruptDisconnectsAreCleanedUp() async throws {
        let clients = (0..<8).map { _ in connect() }
        for client in clients {
            try await receive(client) { $0["type"] as? String == "snapshot" }
        }
        let initialCount = await waitForClientCount(8)
        XCTAssertEqual(initialCount, 8)

        for client in clients.prefix(5) { client.cancel() } // no close handshake
        let remainingCount = await waitForClientCount(3)
        XCTAssertEqual(remainingCount, 3)

        // Remaining viewers still get updates, and the device can reconnect
        // more times than the per-IP cap without being refused.
        await edit { $0.cueStacks[0].name = "After drop" }
        for client in clients.suffix(3) {
            try await receive(client) { self.isSnapshot($0, containing: "After drop") }
        }
        for round in 0..<15 {
            let c = connect()
            try await receive(c) { $0["type"] as? String == "snapshot" }
            c.cancel()
            _ = await waitForClientCount(3)
            _ = round
        }
    }

    func testMaliciousFrameDisconnectsOnlyThatClient() async throws {
        let good = connect()
        try await receive(good) { $0["type"] as? String == "snapshot" }

        // Raw TCP client: complete the handshake, then send a frame that
        // claims a length of 2^63.
        let raw = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let closed = expectation(description: "server closed bad client")
        raw.stateUpdateHandler = { _ in }
        raw.start(queue: .global())
        let handshake = "GET /ws HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
        raw.send(content: Data(handshake.utf8), completion: .contentProcessed { _ in })
        try await Task.sleep(nanoseconds: 300_000_000)
        raw.send(content: Data([0x81, 0xFF, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 1, 2, 3, 4]),
                 completion: .contentProcessed { _ in })
        func drain() {
            raw.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { _, _, isComplete, error in
                if isComplete || error != nil { closed.fulfill() } else { drain() }
            }
        }
        drain()
        await fulfillment(of: [closed], timeout: 5)
        raw.cancel()

        await edit { $0.cueStacks[0].name = "Still alive" }
        try await receive(good) { self.isSnapshot($0, containing: "Still alive") }
    }

    func testRapidEditsArriveInOrderAndEndOnLatest() async throws {
        let client = connect()
        try await receive(client) { $0["type"] as? String == "snapshot" }
        for i in 1...40 {
            await edit { $0.cueStacks[0].name = "Rev \(i)" }
        }
        var lastVersion: Int = -1
        let final = try await receive(client, timeout: 8) { json in
            guard json["type"] as? String == "snapshot" else { return false }
            let version = json["version"] as? Int ?? -1
            XCTAssertGreaterThanOrEqual(version, lastVersion, "snapshots must not go backwards")
            lastVersion = version
            return self.isSnapshot(json, containing: "Rev 40")
        }
        XCTAssertNotNil(final)
    }

    /// A second timer change inside the 250 ms throttle window used to be
    /// dropped, leaving viewers on the old value until the next change.
    func testTimerChangeInsideThrottleWindowStillArrives() async throws {
        let client = connect()
        try await receive(client) { $0["type"] as? String == "timer_state" }

        await MainActor.run {
            timer.executeCommand(TimerCommand(action: "setCountdownTime", countdownTime: 10, countUpTime: nil, adjustment: nil, targetTimeString: nil))
            hub.broadcastTimerStateIfNeeded(force: true)
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        await MainActor.run {
            timer.executeCommand(TimerCommand(action: "adjust", countdownTime: nil, countUpTime: nil, adjustment: 60, targetTimeString: nil))
            hub.broadcastTimerStateIfNeeded()
        }
        try await receive(client, timeout: 2) { json in
            guard json["type"] as? String == "timer_state",
                  let payload = json["data"] as? [String: Any] else { return false }
            return payload["countdownTime"] as? Int == 70
        }
    }
}
