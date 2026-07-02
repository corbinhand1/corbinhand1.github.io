//
//  LANBroadcastHub.swift
//  Cue to Cue
//
//  Central WebSocket broadcast hub for LAN viewers (anonymous read, push updates).
//

import Foundation
import Network

final class LANWebSocketClient {
    let id: UUID
    private let connection: NWConnection
    private let sendQueue = DispatchQueue(label: "LANWebSocketClient.send")

    init(id: UUID = UUID(), connection: NWConnection) {
        self.id = id
        self.connection = connection
    }

    func send(text: String) {
        guard let frame = LANWebSocketFraming.encodeText(text) else { return }
        sendQueue.async { [connection] in
            connection.send(content: frame, completion: .contentProcessed { _ in })
        }
    }
}

final class LANBroadcastHub {
    private let queue = DispatchQueue(label: "LANBroadcastHub.queue")
    private var clients: [UUID: LANWebSocketClient] = [:]
    private var lastTimerBroadcast: Date = .distantPast
    private let timerBroadcastMinInterval: TimeInterval = 0.25

    weak var dataSyncManager: DataSyncManager?
    weak var timerServer: AuthoritativeTimerServer?

    var webSocketClientCount: Int {
        queue.sync { clients.count }
    }

    // MARK: - Client registry

    func register(_ client: LANWebSocketClient) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.clients[client.id] = client
            let count = self.clients.count
            DispatchQueue.main.async {
                print("📡 LAN WebSocket client connected (\(count) total)")
            }
            self.deliverSnapshot(to: client)
            self.deliverShowState(to: client)
            self.deliverTimerState(to: client)
        }
    }

    func unregister(clientId: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.clients.removeValue(forKey: clientId)
            let count = self.clients.count
            DispatchQueue.main.async {
                print("📡 LAN WebSocket client disconnected (\(count) remaining)")
            }
        }
    }

    // MARK: - Notifications (call from main thread)

    func notifyChange(version: UInt64, kind: LANChangeKind, patch: LANCuePatch? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.broadcast(version: version, kind: kind, patch: patch)
        }
    }

    func broadcastSnapshot() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let dataSyncManager = self.dataSyncManager,
                  let timerServer = self.timerServer else { return }
            let version = dataSyncManager.dataVersion
            let jsonData = dataSyncManager.generateJSONResponseForWebClient(timerServer: timerServer)
            guard let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let text = LANMessageEncoder.snapshotEnvelope(version: version, snapshotObject: object) else { return }
            self.queue.async {
                self.sendToAll(text)
            }
        }
    }

    func broadcastShowStateIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let dataSyncManager = self.dataSyncManager,
                  let payload = dataSyncManager.buildShowStatePayload() else { return }

            let version = dataSyncManager.showVersion
            guard let text = LANMessageEncoder.encode(type: .showState, version: version, data: payload) else { return }
            self.queue.async {
                self.sendToAll(text)
            }
        }
    }

    func broadcastTimerStateIfNeeded(force: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let dataSyncManager = self.dataSyncManager,
                  let timerServer = self.timerServer else { return }

            let now = Date()
            if !force, now.timeIntervalSince(self.lastTimerBroadcast) < self.timerBroadcastMinInterval {
                return
            }
            self.lastTimerBroadcast = now

            let payload = self.timerStatePayload(dataSyncManager: dataSyncManager, timerServer: timerServer)
            guard let payload,
                  let text = LANMessageEncoder.encode(type: .timerState, version: dataSyncManager.dataVersion, data: payload) else { return }
            self.queue.async {
                self.sendToAll(text)
            }
        }
    }

    // MARK: - Private

    private func broadcast(version: UInt64, kind: LANChangeKind, patch: LANCuePatch?) {
        guard let dataSyncManager = dataSyncManager, let timerServer = timerServer else { return }

        switch kind {
        case .snapshot, .stackChanged:
            let jsonData = dataSyncManager.generateJSONResponseForWebClient(timerServer: timerServer)
            guard let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let text = LANMessageEncoder.snapshotEnvelope(version: version, snapshotObject: object) else { return }
            queue.async { [weak self] in
                self?.sendToAll(text)
            }
        case .showState, .timerState:
            break
        case .cuePatch:
            guard let patch = patch else { return }
            let payload: [String: Any] = [
                "cueId": patch.cueId.uuidString,
                "columnIndex": patch.columnIndex,
                "newValue": patch.newValue
            ]
            guard let text = LANMessageEncoder.encode(type: .cuePatch, version: version, data: payload) else { return }
            queue.async { [weak self] in
                self?.sendToAll(text)
            }
        }
    }

    private func deliverSnapshot(to client: LANWebSocketClient) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let dataSyncManager = self.dataSyncManager,
                  let timerServer = self.timerServer else { return }
            let version = dataSyncManager.dataVersion
            let jsonData = dataSyncManager.generateJSONResponseForWebClient(timerServer: timerServer)
            guard let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let text = LANMessageEncoder.snapshotEnvelope(version: version, snapshotObject: object) else { return }
            self.queue.async {
                client.send(text: text)
            }
        }
    }

    private func deliverShowState(to client: LANWebSocketClient) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let dataSyncManager = self.dataSyncManager,
                  let payload = dataSyncManager.buildShowStatePayload() else { return }
            let version = dataSyncManager.showVersion
            guard let text = LANMessageEncoder.encode(type: .showState, version: version, data: payload) else { return }
            self.queue.async {
                client.send(text: text)
            }
        }
    }

    private func deliverTimerState(to client: LANWebSocketClient) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let dataSyncManager = self.dataSyncManager,
                  let timerServer = self.timerServer,
                  let payload = self.timerStatePayload(dataSyncManager: dataSyncManager, timerServer: timerServer),
                  let text = LANMessageEncoder.encode(type: .timerState, version: dataSyncManager.dataVersion, data: payload) else { return }
            self.queue.async {
                client.send(text: text)
            }
        }
    }

    private func timerStatePayload(dataSyncManager: DataSyncManager, timerServer: AuthoritativeTimerServer) -> [String: Any]? {
        let state = timerServer.getTimerState()
        var payload: [String: Any] = [
            "countdownTime": state.countdownTime,
            "countdownRunning": state.countdownRunning,
            "countUpTime": state.countUpTime,
            "countUpRunning": state.countUpRunning
        ]
        if let target = state.countdownTarget {
            payload["countdownTarget"] = target
        }
        if let target = state.countUpTarget {
            payload["countUpTarget"] = target
        }
        return payload
    }

    private func sendToAll(_ text: String) {
        for client in clients.values {
            client.send(text: text)
        }
    }
}
