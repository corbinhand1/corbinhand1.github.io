//
//  LANWebSocketProtocol.swift
//  Cue to Cue
//
//  WebSocket framing and LAN message encoding for the HTTP server on port 8080.
//

import Foundation
import CryptoKit
import Network

// MARK: - Change kinds

enum LANChangeKind: String {
    case snapshot
    case showState = "show_state"
    case timerState = "timer_state"
    case cuePatch = "cue_patch"
    case stackChanged = "stack_changed"
}

struct LANCuePatch {
    let cueId: UUID
    let columnIndex: Int
    let newValue: String
}

// MARK: - WebSocket handshake

enum LANWebSocketHandshake {
    static func isUpgradeRequest(_ request: HTTPRequest) -> Bool {
        guard request.method == .get else { return false }
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        guard path == "/ws" else { return false }
        return request.headers["upgrade"]?.lowercased() == "websocket"
            && request.headers["sec-websocket-version"] == "13"
            && request.headers["sec-websocket-key"] != nil
    }

    static func acceptKey(for secWebSocketKey: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data((secWebSocketKey + magic).utf8))
        return Data(digest).base64EncodedString()
    }

    static func switchingProtocolsResponse(acceptKey: String) -> Data {
        var response = "HTTP/1.1 101 Switching Protocols\r\n"
        response += "Upgrade: websocket\r\n"
        response += "Connection: Upgrade\r\n"
        response += "Sec-WebSocket-Accept: \(acceptKey)\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"
        response += "\r\n"
        return Data(response.utf8)
    }
}

// MARK: - WebSocket framing

enum LANWebSocketFraming {
  /// Server → client text frame (unmasked).
    static func encodeText(_ text: String) -> Data? {
        guard let payload = text.data(using: .utf8) else { return nil }
        var frame = Data()
        frame.append(0x81) // FIN + text opcode

        let length = payload.count
        if length < 126 {
            frame.append(UInt8(length))
        } else if length <= 0xFFFF {
            frame.append(126)
            frame.append(UInt8((length >> 8) & 0xFF))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> shift) & 0xFF))
            }
        }
        frame.append(payload)
        return frame
    }

    /// Server → client pong frame (unmasked) in reply to a client ping.
    static func encodePong(_ payload: Data = Data()) -> Data {
        var frame = Data()
        frame.append(0x8A) // FIN + pong opcode
        let length = payload.count
        if length < 126 {
            frame.append(UInt8(length))
        } else if length <= 0xFFFF {
            frame.append(126)
            frame.append(UInt8((length >> 8) & 0xFF))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> shift) & 0xFF))
            }
        }
        frame.append(payload)
        return frame
    }

    struct DecodedFrame {
        enum Kind {
            case text(String)
            case ping(Data)
            case close
        }
        let kind: Kind
    }

    /// Largest client frame we accept. Viewers only send tiny pings; anything
    /// bigger is a broken or hostile client, and is disconnected.
    static let maxClientFrameBytes = 1 << 20

    /// Decode complete client frames from a receive buffer. Returns `.close`
    /// (and clears the buffer) for oversized or malformed frames, so a bad
    /// client can't crash the app or make it buffer without limit.
    static func extractFrames(from buffer: inout Data) -> [DecodedFrame] {
        var frames: [DecodedFrame] = []
        // Work on a zero-based copy so indices are always valid even if the
        // caller's Data is a slice.
        if buffer.startIndex != 0 { buffer = Data(buffer) }
        while true {
            guard buffer.count >= 2 else { break }

            let byte0 = buffer[0]
            let byte1 = buffer[1]
            let opcode = byte0 & 0x0F
            let isMasked = (byte1 & 0x80) != 0
            var payloadLength = Int(byte1 & 0x7F)
            var index = 2

            if payloadLength == 126 {
                guard buffer.count >= index + 2 else { break }
                payloadLength = Int(buffer[index]) << 8 | Int(buffer[index + 1])
                index += 2
            } else if payloadLength == 127 {
                guard buffer.count >= index + 8 else { break }
                var length: UInt64 = 0
                for offset in 0..<8 {
                    length = (length << 8) | UInt64(buffer[index + offset])
                }
                guard length <= UInt64(maxClientFrameBytes) else {
                    buffer.removeAll()
                    frames.append(DecodedFrame(kind: .close))
                    return frames
                }
                payloadLength = Int(length)
                index += 8
            }

            guard payloadLength <= maxClientFrameBytes else {
                buffer.removeAll()
                frames.append(DecodedFrame(kind: .close))
                return frames
            }

            let maskKeyOffset = index
            let payloadOffset = isMasked ? index + 4 : index
            let frameLength = payloadOffset + payloadLength
            guard buffer.count >= frameLength else { break }

            var payload = Data(buffer[payloadOffset..<frameLength])
            if isMasked {
                let mask = Array(buffer[maskKeyOffset..<(maskKeyOffset + 4)])
                for i in 0..<payload.count {
                    payload[i] ^= mask[i % 4]
                }
            }

            buffer.removeSubrange(0..<frameLength)

            switch opcode {
            case 0x1:
                if let text = String(data: payload, encoding: .utf8) {
                    frames.append(DecodedFrame(kind: .text(text)))
                }
            case 0x8:
                frames.append(DecodedFrame(kind: .close))
                return frames
            case 0x9:
                frames.append(DecodedFrame(kind: .ping(payload)))
            default:
                break
            }
        }
        return frames
    }

    /// Decode complete client text frames from a receive buffer.
    static func extractTextMessages(from buffer: inout Data) -> [String] {
        extractFrames(from: &buffer).compactMap { frame in
            if case .text(let text) = frame.kind { return text }
            return nil
        }
    }
}

// MARK: - LAN JSON messages

enum LANMessageEncoder {
    static func encode(type: LANChangeKind, version: UInt64, data: [String: Any]) -> String? {
        let envelope: [String: Any] = [
            "type": type.rawValue,
            "version": version,
            "data": data
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: envelope),
              let text = String(data: json, encoding: .utf8) else {
            return nil
        }
        return text
    }

    static func snapshotEnvelope(version: UInt64, snapshotObject: [String: Any]) -> String? {
        let envelope: [String: Any] = [
            "type": LANChangeKind.snapshot.rawValue,
            "version": version,
            "data": snapshotObject
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: envelope),
              let text = String(data: json, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
