import Foundation
import NIO
import NIOHTTP1
import NIOWebSocket
import Combine
import CryptoKit
import CommonCrypto

// Suppress Swift 6 Sendable warnings for SwiftNIO handlers
#if compiler(>=6.0)
@preconcurrency import NIO
@preconcurrency import NIOHTTP1
@preconcurrency import NIOWebSocket
#endif

// MARK: - WebSocket Server Protocol

protocol WebSocketServerProtocol: AnyObject {
    func notifyCueNavigation(cueIndex: Int, cueId: String?)
    func notifyFileChanged(filename: String, lastUpdated: Date)
    func notifyTimerSync(timerData: [String: Any])
    func notifyTimerCommand(command: String, data: [String: Any])
    func notifyTimerUpdate(timerData: [String: Any])
    func notifyCueUpdate(cueId: String, columnIndex: Int, newValue: String)
}

class SwiftNIOWebSocketServer: ObservableObject, WebSocketServerProtocol {
    // MARK: - Published Properties
    @Published var connectionCount: Int = 0
    @Published var isRunning: Bool = false
    
    // MARK: - Private Properties
    private var group: EventLoopGroup
    private var channel: Channel?
    private var connections: [UUID: Channel] = [:]
    private var connectionMetrics: [UUID: (lastMessageTime: Date, messageCount: Int)] = [:]
    private let connectionsQueue = DispatchQueue(label: "com.cuetocue.connections")
    private let authManager: AuthenticationManager
    internal let dataSyncManager: DataSyncManager
    private let timerServer: AuthoritativeTimerServer
    
    // MARK: - Initialization
    init(authManager: AuthenticationManager, dataSyncManager: DataSyncManager, timerServer: AuthoritativeTimerServer) {
        self.authManager = authManager
        self.dataSyncManager = dataSyncManager
        self.timerServer = timerServer
        
        // Use single-threaded event loop for simplicity
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        print("🔌 SwiftNIOWebSocketServer initialized")
    }
    
    deinit {
        stop()
        try? group.syncShutdownGracefully()
    }
    
    private func initializeChildChannel(_ channel: Channel) -> EventLoopFuture<Void> {
        let connectionId = UUID()
        
        return channel.pipeline.addHandler(
            ByteToMessageHandler(HTTPRequestDecoder()),
            name: "HTTPDecoder"
        ).flatMap {
            channel.pipeline.addHandler(
                HTTPResponseEncoder(),
                name: "HTTPEncoder"
            )
        }.flatMap {
            channel.pipeline.addHandler(
                WebSocketUpgradeHandler(server: self, connectionId: connectionId)
            )
        }
    }
    
    // MARK: - Server Control
    func start(port: Int) throws {
        print("🔌 SwiftNIO WebSocket server attempting to start on port \(port)")
        
        guard !isRunning else {
            print("⚠️ SwiftNIO WebSocket server already running")
            return
        }
        
        do {
            let bootstrap = ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .childChannelInitializer { channel in
                    self.initializeChildChannel(channel)
                }
                .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
                .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
            
            print("🔌 SwiftNIO bootstrap configured, attempting to bind to port \(port)")
            self.channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
            self.isRunning = true
            
            print("🔌 SwiftNIO WebSocket server started successfully on port \(port)")
            
            // Start listening for connections
            DispatchQueue.global(qos: .background).async {
                try? self.channel?.closeFuture.wait()
            }
        } catch {
            print("❌ SwiftNIO WebSocket server failed to start on port \(port): \(error)")
            print("❌ Error type: \(type(of: error))")
            print("❌ Error details: \(error.localizedDescription)")
            
            // Check if it's a port binding error
            if let posixError = error as? POSIXError {
                print("❌ POSIX Error Code: \(posixError.code)")
                switch posixError.code {
                case .EADDRINUSE:
                    print("❌ Port \(port) is already in use")
                case .EACCES:
                    print("❌ Permission denied to bind to port \(port)")
                case .EADDRNOTAVAIL:
                    print("❌ Address not available for port \(port)")
                default:
                    print("❌ Other POSIX error: \(posixError.code)")
                }
            }
            
            // Clean up on failure
            try? group.syncShutdownGracefully()
            group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            
            throw error
        }
    }
    
    func stop() {
        guard isRunning else { return }
        
        // Close all connections first
        for (_, channel) in connections {
            try? channel.close().wait()
        }
        connections.removeAll()
        
        // Close the main channel
        try? channel?.close().wait()
        channel = nil
        
        // Shutdown the event loop group
        try? group.syncShutdownGracefully()
        
        connectionCount = 0
        isRunning = false
        
        print("🔌 SwiftNIO WebSocket server stopped")
    }
    
    // MARK: - Connection Management
    func addConnection(_ connectionId: UUID, channel: Channel) {
        connectionsQueue.async { [weak self] in
            guard let self = self else { return }
            self.connections[connectionId] = channel
            self.connectionMetrics[connectionId] = (lastMessageTime: Date(), messageCount: 0)
            
            DispatchQueue.main.async {
                self.connectionCount = self.connections.count
            }
            
            print("🔌 New SwiftNIO WebSocket connection: \(connectionId) (total: \(self.connections.count))")
        }
    }
    
    func removeConnection(_ connectionId: UUID) {
        connectionsQueue.async { [weak self] in
            guard let self = self else { return }
            self.connections.removeValue(forKey: connectionId)
            self.connectionMetrics.removeValue(forKey: connectionId)
            
            DispatchQueue.main.async {
                self.connectionCount = self.connections.count
            }
            
            print("🔌 SwiftNIO WebSocket connection removed: \(connectionId) (total: \(self.connections.count))")
        }
    }
    
    // MARK: - Message Broadcasting
    func sendMessage(_ message: String) {
        connectionsQueue.async { [weak self] in
            guard let self = self else { return }
            let data = message.data(using: .utf8) ?? Data()
            var buffer = ByteBuffer()
            buffer.writeBytes(data)
            
            let connectionsCopy = self.connections
            var successCount = 0
            var failedConnections: [UUID] = []
            let currentTime = Date()
            
            for (connectionId, channel) in connectionsCopy {
                if channel.isActive {
                    let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
                    channel.writeAndFlush(frame, promise: nil)
                    successCount += 1
                    
                    // Update connection metrics
                    if var metrics = self.connectionMetrics[connectionId] {
                        metrics.lastMessageTime = currentTime
                        metrics.messageCount += 1
                        self.connectionMetrics[connectionId] = metrics
                    }
                } else {
                    failedConnections.append(connectionId)
                }
            }
            
            // Clean up failed connections
            for connectionId in failedConnections {
                self.removeConnection(connectionId)
            }
            
                // Only log errors or when no clients are connected
                if successCount == 0 {
                    print("⚠️ SwiftNIO: No clients connected to receive message")
                }
        }
    }
    
    func sendMessageToConnection(connectionId: UUID, message: String) {
        connectionsQueue.async { [weak self] in
            guard let self = self else { return }
            guard let channel = self.connections[connectionId], channel.isActive else {
                print("⚠️ Connection \(connectionId) not found or inactive")
                return
            }
            
            let data = message.data(using: .utf8) ?? Data()
            var buffer = ByteBuffer()
            buffer.writeBytes(data)
            let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
            channel.writeAndFlush(frame, promise: nil)
            print("📡 SwiftNIO sent message to connection \(connectionId)")
        }
    }
    
    // MARK: - Cue Navigation Methods (Compatible with existing interface)
    func notifyCueNavigation(cueIndex: Int, cueId: String?) {
        let message = WebSocketMessage(
            type: "cue_navigation",
            data: [
                "cueIndex": AnyCodable(cueIndex),
                "cueStackIndex": AnyCodable(dataSyncManager.selectedCueStackIndex)
            ]
        )
        
        if let jsonData = try? JSONEncoder().encode(message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendMessage(jsonString)
        }
    }
    
    func notifyFileChanged(filename: String, lastUpdated: Date = Date()) {
        let message = WebSocketMessage(
            type: "file_changed",
            data: [
                "filename": AnyCodable(filename),
                "lastUpdated": AnyCodable(ISO8601DateFormatter().string(from: lastUpdated))
            ]
        )
        
        if let jsonData = try? JSONEncoder().encode(message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendMessage(jsonString)
        }
    }
    
    func notifyCueUpdate(cueId: String, columnIndex: Int, newValue: String) {
        let message = WebSocketMessage(
            type: "cue_update",
            data: [
                "cueId": AnyCodable(cueId),
                "columnIndex": AnyCodable(columnIndex),
                "newValue": AnyCodable(newValue)
            ]
        )
        
        if let jsonData = try? JSONEncoder().encode(message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendMessage(jsonString)
        }
    }
    
    func notifyTimerSync(timerData: [String: Any]) {
        let convertedData = timerData.mapValues { AnyCodable($0) }
        let message = WebSocketMessage(
            type: "timer_sync",
            data: convertedData
        )
        
        if let jsonData = try? JSONEncoder().encode(message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendMessage(jsonString)
        }
    }
    
    func notifyTimerCommand(command: String, data: [String: Any] = [:]) {
        var messageData = data.mapValues { AnyCodable($0) }
        messageData["command"] = AnyCodable(command)
        
        let message = WebSocketMessage(
            type: "timer_command",
            data: messageData
        )
        
        if let jsonData = try? JSONEncoder().encode(message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendMessage(jsonString)
        }
    }
    
    func notifyTimerUpdate(timerData: [String: Any]) {
        let convertedData = timerData.mapValues { AnyCodable($0) }
        let message = WebSocketMessage(
            type: "timer_update",
            data: convertedData
        )
        
        if let jsonData = try? JSONEncoder().encode(message),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendMessage(jsonString)
        }
    }
}

// MARK: - WebSocket Message Structure
struct WebSocketMessage: Codable {
    let type: String
    let data: [String: AnyCodable]
    let timestamp: Date
    
    init(type: String, data: [String: AnyCodable] = [:]) {
        self.type = type
        self.data = data
        self.timestamp = Date()
    }
}

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let dictValue = value as? [String: Any] {
            let anyCodableDict = dictValue.mapValues { AnyCodable($0) }
            try container.encode(anyCodableDict)
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}


// MARK: - WebSocketUpgradeHandler
private final class WebSocketUpgradeHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private weak var server: SwiftNIOWebSocketServer?
    private let connectionId: UUID
    private var requestHead: HTTPRequestHead?
    
    init(server: SwiftNIOWebSocketServer?, connectionId: UUID) {
        self.server = server
        self.connectionId = connectionId
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = unwrapInboundIn(data)
        
        switch request {
        case .head(let head):
            self.requestHead = head
            
        case .end:
            // Wait for the complete request before deciding what to do
            guard let head = self.requestHead else {
                print("❌ Received .end without .head")
                context.close(promise: nil)
                return
            }
            
            if isWebSocketUpgradeRequest(head) {
                print("🔌 WebSocket upgrade request detected")
                handleWebSocketUpgrade(context: context, head: head)
            } else {
                print("❌ Not a WebSocket upgrade request, sending 404")
                sendNotFound(context: context, head: head)
            }
            
        case .body:
            // Ignore body for WebSocket upgrade requests
            break
        }
    }
    
    private func sendNotFound(context: ChannelHandlerContext, head: HTTPRequestHead) {
        var responseHead = HTTPResponseHead(version: head.version, status: .notFound)
        responseHead.headers.add(name: "Content-Length", value: "0")
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
    
    private func isWebSocketUpgradeRequest(_ head: HTTPRequestHead) -> Bool {
        return head.headers["upgrade"].first?.lowercased() == "websocket" &&
               head.headers["connection"].first?.lowercased().contains("upgrade") == true &&
               head.headers["sec-websocket-version"].first == "13" &&
               head.headers["sec-websocket-key"].first != nil
    }
    
    private func handleWebSocketUpgrade(context: ChannelHandlerContext, head: HTTPRequestHead) {
        guard let key = head.headers["sec-websocket-key"].first else {
            print("❌ Missing Sec-WebSocket-Key header")
            context.close(promise: nil)
            return
        }
        
        let acceptKey = generateWebSocketAcceptKey(key)
        
        // Send 101 Switching Protocols response
        var responseHead = HTTPResponseHead(version: head.version, status: .switchingProtocols)
        responseHead.headers.add(name: "Upgrade", value: "websocket")
        responseHead.headers.add(name: "Connection", value: "Upgrade")
        responseHead.headers.add(name: "Sec-WebSocket-Accept", value: acceptKey)
        
        print("📤 Sending 101 Switching Protocols")
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        
        // CRITICAL: Wait for the flush to complete before upgrading the pipeline
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success:
                print("✅ 101 response sent successfully, now upgrading pipeline")
                self.upgradeToWebSocket(context: context)
                
            case .failure(let error):
                print("❌ Failed to send 101 response: \(error)")
                context.close(promise: nil)
            }
        }
    }
    
    private func upgradeToWebSocket(context: ChannelHandlerContext) {
        print("🔌 SwiftNIO upgrading pipeline to WebSocket")
        
        // Use a more robust approach to ensure proper pipeline upgrade
        let upgradeFuture = context.pipeline.removeHandler(name: "HTTPDecoder")
            .flatMap { _ in
                print("✅ Removed HTTPDecoder")
                return context.pipeline.removeHandler(name: "HTTPEncoder")
            }
            .flatMap { _ in
                print("✅ Removed HTTPEncoder")
                return context.pipeline.removeHandler(self)
            }
            .flatMap { _ in
                print("✅ All HTTP handlers removed, adding WebSocket handlers")
                return context.pipeline.addHandler(
                    ByteToMessageHandler(WebSocketFrameDecoder()),
                    name: "WebSocketFrameDecoder"
                )
            }
            .flatMap { _ in
                print("✅ Added WebSocketFrameDecoder")
                return context.pipeline.addHandler(
                    WebSocketFrameEncoder(),
                    name: "WebSocketFrameEncoder"
                )
            }
            .flatMap { _ in
                print("✅ Added WebSocketFrameEncoder")
                return context.pipeline.addHandler(
                    WebSocketFrameHandler(server: self.server, connectionId: self.connectionId),
                    name: "WebSocketFrameHandler"
                )
            }
        
        upgradeFuture.whenComplete { [weak self] (result: Result<Void, Error>) in
            guard let self = self else { return }
            
            switch result {
            case .success:
                print("✅ WebSocket pipeline configured successfully")
                print("🎉 WebSocket upgrade complete for connection \(self.connectionId)")
                
                // Ensure the connection is properly tracked
                if let server = self.server {
                    print("🔗 Explicitly adding connection to server: \(self.connectionId)")
                    server.addConnection(self.connectionId, channel: context.channel)
                } else {
                    print("⚠️ Server reference is nil, cannot add connection")
                }
                
            case .failure(let error):
                print("❌ Failed to configure WebSocket pipeline: \(error)")
                context.close(promise: nil)
            }
        }
    }
    
    private func generateWebSocketAcceptKey(_ key: String) -> String {
        let magicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + magicString
        
        guard let data = combined.data(using: .utf8) else { return "" }
        
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &hash)
        }
        
        return Data(hash).base64EncodedString()
    }
}


// MARK: - WebSocket Frame Handler
final class WebSocketFrameHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    
    private weak var server: SwiftNIOWebSocketServer?
    private let connectionId: UUID
    
    init(server: SwiftNIOWebSocketServer?, connectionId: UUID) {
        self.server = server
        self.connectionId = connectionId
    }
    
    func channelActive(context: ChannelHandlerContext) {
        print("🔌 SwiftNIO WebSocketFrameHandler active for connection: \(connectionId)")
        server?.addConnection(connectionId, channel: context.channel)
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        print("🔌 SwiftNIO WebSocket connection inactive: \(connectionId)")
        server?.removeConnection(connectionId)
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        
        
        switch frame.opcode {
        case .text:
            var data = frame.unmaskedData
            if let text = data.readString(length: data.readableBytes) {
                handleTextMessage(context: context, text: text)
            } else {
                print("⚠️ SwiftNIO failed to decode text frame")
            }
            
        case .binary:
            print("📦 SwiftNIO received binary frame")
            // Handle binary data if needed
            
        case .ping:
            let data = frame.unmaskedData
            let pongFrame = WebSocketFrame(fin: true, opcode: .pong, data: data)
            context.writeAndFlush(wrapOutboundOut(pongFrame), promise: nil)
            
        case .pong:
            print("🏓 SwiftNIO received pong frame")
            // Handle pong if needed
            
        case .connectionClose:
            print("🔌 SwiftNIO received close frame")
            // Echo the close frame back
            let data = frame.unmaskedData
            let closeFrame = WebSocketFrame(fin: true, opcode: .connectionClose, data: data)
            context.writeAndFlush(wrapOutboundOut(closeFrame)).whenComplete { _ in
                context.close(promise: nil)
            }
            
        default:
            print("❓ SwiftNIO received unknown frame opcode: \(frame.opcode)")
        }
    }
    
    private func handleTextMessage(context: ChannelHandlerContext, text: String) {
        
        // Parse JSON message and handle different types
        guard let data = text.data(using: .utf8) else {
            print("⚠️ Failed to convert text to data")
            return
        }
        
        do {
            let message = try JSONDecoder().decode(WebSocketMessage.self, from: data)
            
            switch message.type {
            case "test":
                print("🧪 SwiftNIO received test message")
                sendResponse(context: context, message: WebSocketMessage(
                    type: "test_response",
                    data: ["message": AnyCodable("Hello from SwiftNIO!")]
                ))
                
            case "cue_navigation":
                if let cueIndex = message.data["cueIndex"]?.value as? Int,
                   let cueStackIndex = message.data["cueStackIndex"]?.value as? Int {
                    print("🧭 SwiftNIO received cue navigation: cueIndex=\(cueIndex), cueStackIndex=\(cueStackIndex)")
                    
                    // Update the DataSyncManager with the new cue selection
                    DispatchQueue.main.async {
                        self.server?.dataSyncManager.selectedCueStackIndex = cueStackIndex
                        self.server?.dataSyncManager.selectedCueIndex = cueIndex
                        print("✅ SwiftNIO updated cue selection: cueIndex=\(cueIndex), cueStackIndex=\(cueStackIndex)")
                    }
                }
                
            case "timer_command":
                if let command = message.data["command"]?.value as? String {
                    print("⏰ SwiftNIO received timer command: \(command)")
                    // TODO: Integrate with timer server
                }
                
            case "ping":
                // Send pong response
                sendResponse(context: context, message: WebSocketMessage(
                    type: "pong",
                    data: ["timestamp": AnyCodable(Date().timeIntervalSince1970)]
                ))
                
            default:
                print("📨 SwiftNIO received unknown message type: \(message.type)")
            }
        } catch {
            print("⚠️ Failed to parse WebSocket message: \(error)")
            print("⚠️ Raw data: \(String(data: data, encoding: .utf8) ?? "nil")")
        }
    }
    
    private func sendResponse(context: ChannelHandlerContext, message: WebSocketMessage) {
        do {
            let jsonData = try JSONEncoder().encode(message)
            guard String(data: jsonData, encoding: .utf8) != nil else {
                print("⚠️ Failed to convert response to string")
                return
            }
            
            var buffer = context.channel.allocator.buffer(capacity: jsonData.count)
            buffer.writeBytes(jsonData)
            
            let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
            context.writeAndFlush(wrapOutboundOut(frame), promise: nil)
            
        } catch {
            print("⚠️ Failed to encode response message: \(error)")
        }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("❌ WebSocketFrameHandler error: \(error)")
        context.close(promise: nil)
    }
}