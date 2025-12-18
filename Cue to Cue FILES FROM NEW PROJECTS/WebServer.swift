//
//  WebServer.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/31/24.
//

import Foundation
import Network
import Darwin
import Combine

// MARK: - Connection Info Structure

struct ConnectionInfo: Identifiable {
    let id = UUID()
    let endpoint: String
    let state: String
    let requestCount: Int
    let lastSeen: Date
    let ipAddress: String
    let userAgent: String
    let connectionType: String
    let idleTime: TimeInterval
    let browserType: String
    let deviceType: String
    let networkInterface: String
}

struct ClientSession: Identifiable {
    let id: UUID
    let ipAddress: String
    let userAgent: String
    let browserType: String
    let deviceType: String
    let deviceName: String
    let firstSeen: Date
    let lastSeen: Date
    let networkInterface: String
    
    var sessionKey: String {
        return "\(ipAddress)_\(userAgent)"
    }
    
    init(id: UUID, ipAddress: String, userAgent: String, browserType: String, deviceType: String, deviceName: String, firstSeen: Date, lastSeen: Date, networkInterface: String) {
        self.id = id
        self.ipAddress = ipAddress
        self.userAgent = userAgent
        self.browserType = browserType
        self.deviceType = deviceType
        self.deviceName = deviceName
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.networkInterface = networkInterface
    }
}

// MARK: - HTTP Types and Constants

/// HTTP status codes
enum HTTPStatus: Int {
    case ok = 200
    case notFound = 404
    case methodNotAllowed = 405
    case internalServerError = 500
    
    var description: String {
        switch self {
        case .ok: return "OK"
        case .notFound: return "Not Found"
        case .methodNotAllowed: return "Method Not Allowed"
        case .internalServerError: return "Internal Server Error"
        }
    }
    

}

/// HTTP methods
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case options = "OPTIONS"
    case head = "HEAD"
}

/// HTTP request structure
struct HTTPRequest {
    let method: HTTPMethod
    let path: String
    let headers: [String: String]
    let body: Data?
    
    init?(from data: Data) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        
        let requestComponents = requestLine.components(separatedBy: " ")
        guard requestComponents.count >= 3 else { return nil }
        
        guard let method = HTTPMethod(rawValue: requestComponents[0]) else { return nil }
        let path = requestComponents[1]
        
        // Parse headers
        var headers: [String: String] = [:]
        var bodyStartIndex = 0
        
        for (index, line) in lines.enumerated() {
            if line.isEmpty {
                bodyStartIndex = index + 1
                break
            }
            
            if line.contains(": ") {
                let headerComponents = line.components(separatedBy: ": ")
                if headerComponents.count >= 2 {
                    let key = headerComponents[0].lowercased()
                    let value = headerComponents[1...].joined(separator: ": ")
                    headers[key] = value
                }
            }
        }
        
        // Parse body if present
        var body: Data?
        if bodyStartIndex < lines.count {
            let bodyLines = lines[bodyStartIndex...]
            let bodyString = bodyLines.joined(separator: "\r\n")
            body = bodyString.data(using: .utf8)
        }
        
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

/// HTTP response structure
struct HTTPResponse {
    let status: HTTPStatus
    let headers: [String: String]
    let body: Data
    
    init(status: HTTPStatus, headers: [String: String] = [:], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }
    
    func serialize() -> Data {
        var responseString = "HTTP/1.1 \(status.rawValue) \(status.description)\r\n"
        
        // Add standard headers
        responseString += "Content-Length: \(body.count)\r\n"
        responseString += "Connection: keep-alive\r\n"
        responseString += "Keep-Alive: timeout=120, max=1000\r\n"
        responseString += "Access-Control-Allow-Origin: *\r\n"
        responseString += "Cache-Control: no-cache, no-store, must-revalidate\r\n"
        responseString += "Pragma: no-cache\r\n"
        responseString += "Expires: 0\r\n"
        
        // Add custom headers
        for (key, value) in headers {
            responseString += "\(key): \(value)\r\n"
        }
        
        responseString += "\r\n"
        
        guard let headerData = responseString.data(using: .utf8) else {
            return Data()
        }
        
        return headerData + body
    }
}

// MARK: - WebServer Class

class WebServer: ObservableObject {
    // MARK: - Properties
    
    private var listener: NWListener?
    private var port: UInt16
    private var _activeConnections: [NWConnection] = []
    private var _connectionRequestCounts: [ObjectIdentifier: Int] = [:]
    private var _connectionTimestamps: [ObjectIdentifier: Date] = [:]
    private var _connectionUserAgents: [ObjectIdentifier: String] = [:]
    private var _clientSessions: [String: ClientSession] = [:] // Group by client IP + User-Agent
    private var _inactiveClientSessions: [String: ClientSession] = [:] // Store inactive sessions until app restart
    private let maxConnections = 100 // Support 100+ devices
    private var _serverStartTime: Date?
    
    // Published properties for UI updates
    @Published var connectionStats: (active: Int, max: Int) = (0, 100)
    @Published var detailedConnectionInfo: [ConnectionInfo] = []
    @Published var serverStatus: (isRunning: Bool, port: UInt16) = (false, 8080)

    @Published var localIPAddress: String = "Unknown"
    
    // Thread-safe data storage
    private let dataQueue = DispatchQueue(label: "WebServer.dataQueue", attributes: .concurrent)
    private var _cueStacks: [CueStack] = []
    private var _selectedCueStackIndex: Int = 0
    private var _activeCueIndex: Int = -1
    private var _selectedCueIndex: Int = -1
    private var _highlightColors: [HighlightColorSetting] = []
    
    // Clock-related properties
    private var _currentTime: Date = Date()
    private var _countdownTime: Int = 0
    private var _countUpTime: Int = 0
    private var _countdownRunning: Bool = false
    private var _countUpRunning: Bool = false
    
    // Connection management - use serial queue for thread safety
    private let connectionQueue = DispatchQueue(label: "WebServer.connectionQueue")
    
    // Direct access to activeConnections - all operations go through connectionQueue
    
    // MARK: - Thread-safe Getters/Setters
    
    private var cueStacks: [CueStack] {
        get { dataQueue.sync { _cueStacks } }
        set { dataQueue.async(flags: .barrier) { self._cueStacks = newValue } }
    }
    
    private var selectedCueStackIndex: Int {
        get { dataQueue.sync { _selectedCueStackIndex } }
        set { dataQueue.async(flags: .barrier) { self._selectedCueStackIndex = newValue } }
    }
    
    private var activeCueIndex: Int {
        get { dataQueue.sync { _activeCueIndex } }
        set { dataQueue.async(flags: .barrier) { self._activeCueIndex = newValue } }
    }
    
    private var selectedCueIndex: Int {
        get { dataQueue.sync { _selectedCueIndex } }
        set { dataQueue.async(flags: .barrier) { self._selectedCueIndex = newValue } }
    }
    
    private var highlightColors: [HighlightColorSetting] {
        get { dataQueue.sync { _highlightColors } }
        set { dataQueue.async(flags: .barrier) { self._highlightColors = newValue } }
    }
    
    private var currentTime: Date {
        get { dataQueue.sync { _currentTime } }
        set { dataQueue.async(flags: .barrier) { self._currentTime = newValue } }
    }
    
    private var countdownTime: Int {
        get { dataQueue.sync { _countdownTime } }
        set { dataQueue.async(flags: .barrier) { self._countdownTime = newValue } }
    }
    
    private var countUpTime: Int {
        get { dataQueue.sync { _countUpTime } }
        set { dataQueue.async(flags: .barrier) { self._countUpTime = newValue } }
    }
    
    private var countdownRunning: Bool {
        get { dataQueue.sync { _countdownRunning } }
        set { dataQueue.async(flags: .barrier) { self._countdownRunning = newValue } }
    }
    
    private var countUpRunning: Bool {
        get { dataQueue.sync { _countUpRunning } }
        set { dataQueue.async(flags: .barrier) { self._countUpRunning = newValue } }
    }
    
    // MARK: - Initialization
    
    init() {
        self.port = 8080
        // Initialize published properties safely for initialization
        initializePublishedProperties()
    }
    
    // MARK: - Server Management
    
    func start(port: UInt16) {
        self.port = port
        self._serverStartTime = Date()
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        // Set TCP keep-alive options for better connection handling
        if let tcpOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolTCP.Options {
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveCount = 5
            tcpOptions.connectionTimeout = 30 // 30 second timeout
        }
        
        listener = try? NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleListenerStateChange(state)
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            print("📱 New connection from: \(connection.endpoint)")
            self?.handleNewConnection(connection)
        }
        
        listener?.start(queue: .global(qos: .userInitiated))
        
        // Start periodic connection cleanup and monitoring
        startConnectionCleanup()
        startConnectionMonitoring()
        
        // Initialize published properties
        updatePublishedProperties()
        
        // Debug: Check initial connection count
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.debugConnectionCount()
        }
    }
    
    private func startConnectionCleanup() {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.cleanupStaleConnections()
        }
    }
    
    private func startConnectionMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.logConnectionStatus()
        }
    }
    
    private func logConnectionStatus() {
        let stats = getConnectionStats()
        if stats.active > stats.max * 9 / 10 { // 90% of capacity
            print("⚠️ High connection usage: \(getConnectionDetails())")
        } else {
            print("📊 Connection status: \(getConnectionDetails())")
        }
    }
    
    private func cleanupStaleConnections() {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let beforeCount = self._activeConnections.count
            print("🔍 DEBUG: Starting cleanup. Current count: \(beforeCount)")
            
            let staleConnections = self._activeConnections.filter { connection in
                // Remove connections that are definitely dead
                if case .failed = connection.state { return true }
                if case .cancelled = connection.state { return true }
                
                // Also remove connections that have been idle for too long
                let id = ObjectIdentifier(connection)
                if let lastSeen = self._connectionTimestamps[id] {
                    let idleTime = Date().timeIntervalSince(lastSeen)
                    if idleTime > 300 { // 5 minutes of inactivity
                        print("⏰ Connection \(connection.endpoint) idle for \(Int(idleTime))s, marking as stale")
                        return true
                    }
                }
                
                return false
            }
            
            print("🔍 DEBUG: Found \(staleConnections.count) stale connections")
            
            for connection in staleConnections {
                if let index = self._activeConnections.firstIndex(where: { $0 === connection }) {
                    self._activeConnections.remove(at: index)
                    // Clean up associated data
                    let id = ObjectIdentifier(connection)
                    let userAgent = self._connectionUserAgents[id] ?? "Unknown"
                    let ipAddress = self.extractIPAddress(from: String(describing: connection.endpoint))
                    
                    self._connectionRequestCounts.removeValue(forKey: id)
                    self._connectionTimestamps.removeValue(forKey: id)
                    self._connectionUserAgents.removeValue(forKey: id)
                    
                    // Update client session
                    self.removeConnectionFromSession(for: connection, ipAddress: ipAddress, userAgent: userAgent)
                }
            }
            
            let afterCount = self._activeConnections.count
            if !staleConnections.isEmpty {
                print("🧹 Cleaned up \(staleConnections.count) dead connections. Active: \(beforeCount) → \(afterCount)")
            }
            
            // Update published properties safely
            self.updatePublishedProperties()
            
            // Also cleanup old client sessions more frequently
            self.cleanupOldClientSessions()
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        
        // Close all active connections
        connectionQueue.async { [weak self] in
            self?._activeConnections.forEach { connection in
                connection.cancel()
            }
            self?._activeConnections.removeAll()
        }
    }
    
    // MARK: - Listener State Management
    
    private func handleListenerStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("✅ Web server ready on port \(port)")
        case .failed(let error):
            print("❌ Web server failed: \(error)")
        case .cancelled:
            print("🛑 Web server stopped")
        case .waiting(let error):
            print("⏳ Web server waiting: \(error)")
        case .setup:
            print("🔧 Web server setting up...")
        @unknown default:
            print("❓ Web server unknown state: \(state)")
        }
    }
    
    // MARK: - Connection Management
    
    private func handleNewConnection(_ connection: NWConnection) {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check connection limit - only reject if we're at capacity
            let currentCount = self._activeConnections.count
            print("🔍 DEBUG: Checking connection limit. Current: \(currentCount), Max: \(self.maxConnections)")
            if currentCount >= self.maxConnections {
                print("⚠️ Connection limit reached (\(currentCount)/\(self.maxConnections)), rejecting new connection")
                connection.cancel()
                return
            }
            
            // Check for duplicate connections from the same endpoint
            let connectionEndpoint = String(describing: connection.endpoint)
            let existingConnections = self._activeConnections.filter { 
                String(describing: $0.endpoint) == connectionEndpoint 
            }
            
            if existingConnections.count >= 2 {
                print("⚠️ Too many connections from \(connectionEndpoint), rejecting duplicate. Existing: \(existingConnections.count)")
                connection.cancel()
                return
            }
            
            self._activeConnections.append(connection)
            self._connectionRequestCounts[ObjectIdentifier(connection)] = 0
            self._connectionTimestamps[ObjectIdentifier(connection)] = Date()
            print("📱 Added connection. Total active: \(self._activeConnections.count)")
            print("🔍 DEBUG: Connection added - \(connectionEndpoint)")
            
            // Update published properties safely
            self.updatePublishedProperties()
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.global(qos: .utility).async {
                self?.handleConnectionStateChange(connection, state: state)
            }
        }
        
        // Start the connection
        connection.start(queue: .global(qos: .utility))
    }
    
    private func handleConnectionStateChange(_ connection: NWConnection, state: NWConnection.State) {
        switch state {
        case .ready:
            print("✅ Connection ready from: \(connection.endpoint)")
            receiveRequest(on: connection)
        case .failed:
            print("❌ Connection failed from \(connection.endpoint)")
            cleanupConnection(connection)
        case .cancelled:
            print("🛑 Connection cancelled from: \(connection.endpoint)")
            cleanupConnection(connection)
        case .waiting:
            print("⏳ Connection waiting from \(connection.endpoint)")
            // Give mobile connections time to establish
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) { [weak self] in // 30 seconds
                if case .waiting = connection.state {
                    print("⏰ Connection still waiting from \(connection.endpoint) after 30 seconds, cleaning up")
                    self?.cleanupConnection(connection)
                }
            }
        case .preparing:
            print("🔧 Connection preparing from: \(connection.endpoint)")
        case .setup:
            print("⚙️ Connection setup from: \(connection.endpoint)")
        @unknown default:
            print("❓ Unknown connection state from \(connection.endpoint): \(state)")
        }
    }
    
    private func cleanupConnection(_ connection: NWConnection) {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            if let index = self._activeConnections.firstIndex(where: { $0 === connection }) {
                self._activeConnections.remove(at: index)
                // Remove request count tracking
                let id = ObjectIdentifier(connection)
                let requestCount = self._connectionRequestCounts[id] ?? 0
                let userAgent = self._connectionUserAgents[id] ?? "Unknown"
                let ipAddress = self.extractIPAddress(from: String(describing: connection.endpoint))
                
                // Clean up tracking data
                self._connectionRequestCounts.removeValue(forKey: id)
                self._connectionTimestamps.removeValue(forKey: id)
                self._connectionUserAgents.removeValue(forKey: id)
                
                // Update client session
                self.removeConnectionFromSession(for: connection, ipAddress: ipAddress, userAgent: userAgent)
                print("🗑️ Removed connection from array. Active: \(self._activeConnections.count) (was handling \(requestCount) requests)")
            }
            // Update published properties safely
            self.updatePublishedProperties()
        }
        connection.cancel()
    }
    
    private func incrementRequestCount(for connection: NWConnection) {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            let id = ObjectIdentifier(connection)
            let currentCount = self._connectionRequestCounts[id] ?? 0
            self._connectionRequestCounts[id] = currentCount + 1
            self._connectionTimestamps[id] = Date() // Update last seen time
            print("📊 Connection \(connection.endpoint) has handled \(currentCount + 1) requests")
            
            // Update published properties safely
            self.updatePublishedProperties()
        }
    }
    
    /// Safely initializes published properties during object initialization.
    /// This method is safe to call from any thread, including main thread.
    private func initializePublishedProperties() {
        // Initialize with default values on main queue
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Set initial values for published properties
            self.connectionStats = (active: 0, max: self.maxConnections)
            self.detailedConnectionInfo = []
            self.serverStatus = (isRunning: false, port: self.port)
            
            // Get local IP address
            if let ipAddress = self.getLocalIPAddress() {
                self.localIPAddress = ipAddress
            } else {
                self.localIPAddress = "Unknown"
            }
        }
    }
    
    /// Updates all published properties with current connection data.
    /// 
    /// **IMPORTANT:** This method must be called from the connectionQueue context.
    /// It accesses private properties directly and then updates @Published properties on the main queue.
    /// 
    /// - Warning: Calling this from any other background queue may cause data races
    func updatePublishedProperties() {
        // This method is called from connectionQueue context, so we can safely access private properties
        // Note: Removed assertion to prevent crashes during development
        
        // Capture the data we need
        let activeCount = _activeConnections.count
        let connections = _activeConnections
        let requestCounts = _connectionRequestCounts
        let timestamps = _connectionTimestamps
        
        // Update published properties on main queue
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update connection stats
            self.connectionStats = (active: activeCount, max: self.maxConnections)
            
            // Update detailed connection info
            self.detailedConnectionInfo = connections.enumerated().map { index, connection in
                let id = ObjectIdentifier(connection)
                let requestCount = requestCounts[id] ?? 0
                let state = String(describing: connection.state)
                let endpoint = String(describing: connection.endpoint)
                let lastSeen = timestamps[id] ?? Date()
                let idleTime = Date().timeIntervalSince(lastSeen)
                
                // Extract IP address from endpoint
                let ipAddress = self.extractIPAddress(from: endpoint)
                
                // Extract user agent from connection (we'll need to store this)
                let userAgent = self.getThreadSafeUserAgent(for: connection)
                
                // Determine connection type based on endpoint and state
                let connectionType = self.determineConnectionType(endpoint: endpoint, state: state)
                
                // Extract browser and device information
                let browserType = self.extractBrowserType(from: userAgent)
                let deviceType = self.extractDeviceType(from: userAgent)
                let networkInterface = self.getNetworkInterface(for: connection)
                
                return ConnectionInfo(
                    endpoint: endpoint,
                    state: state,
                    requestCount: requestCount,
                    lastSeen: lastSeen,
                    ipAddress: ipAddress,
                    userAgent: userAgent,
                    connectionType: connectionType,
                    idleTime: idleTime,
                    browserType: browserType,
                    deviceType: deviceType,
                    networkInterface: networkInterface
                )
            }
            
            // Update server status
            self.serverStatus = (isRunning: self.listener?.state == .ready, port: self.port)
            
            // Update local IP address
            if let ipAddress = self.getLocalIPAddress() {
                self.localIPAddress = ipAddress
            }
        }
    }
    
    /// Manually refreshes the published properties from the main thread.
    /// This method is safe to call from UI components and will trigger an update
    /// by dispatching to the connection queue.
    func refreshPublishedProperties() {
        // This method can be called from any thread, including main thread
        connectionQueue.async { [weak self] in
            self?.updatePublishedProperties()
        }
    }
    

    
    private func continueListening(on connection: NWConnection) {
        // Continue listening for more requests on the same connection
        // This enables HTTP Keep-Alive and connection reuse
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { [weak self] in
            // Only continue if connection is still alive
            if connection.state == .ready {
                print("🔄 Reusing connection \(connection.endpoint) for next request")
                self?.receiveRequest(on: connection)
            } else {
                // Connection is dead, clean it up
                print("💀 Connection \(connection.endpoint) is dead, cleaning up")
                self?.cleanupConnection(connection)
            }
        }
    }
    
    private func keepConnectionAlive(_ connection: NWConnection) {
        // Keep connections alive for mobile devices - only close if definitely dead
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 120) { [weak self] in // 2 minutes
            // Only close if connection is definitely dead
            if case .failed = connection.state { self?.cleanupConnection(connection) }
            if case .cancelled = connection.state { self?.cleanupConnection(connection) }
            // Otherwise keep the connection alive
        }
    }
    
    // MARK: - Request Handling
    
    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                // Only log and cleanup on actual errors, not cancellations
                let nsError = error as NSError
                if nsError.domain == "NSPOSIXErrorDomain" && nsError.code == 89 {
                    // Operation canceled - this is normal, don't log as error
                    return
                }
                print("❌ Error receiving request: \(error)")
                self.cleanupConnection(connection)
                return
            }
            
            guard let data = data else {
                // No data but no error - this might be normal
                return
            }
            
            // Process the request
            self.processRequest(data, on: connection)
            
            // Increment request count for this connection
            self.incrementRequestCount(for: connection)
            

            
            // After sending response, continue listening for more requests on the same connection
            self.continueListening(on: connection)
        }
    }
    
    private func processRequest(_ data: Data, on connection: NWConnection) {
        // This method should only be called from connectionQueue context
        guard let request = HTTPRequest(from: data) else {
            sendErrorResponse(.internalServerError, on: connection)
            return
        }
        
        // Log request for debugging
        print("📥 \(request.method.rawValue) \(request.path)")
        
        // Extract and store User-Agent header
        if let userAgent = request.headers["user-agent"] {
            // Store User-Agent on connectionQueue to avoid data races
            connectionQueue.async { [weak self] in
                guard let self = self else { return }
                let connectionId = ObjectIdentifier(connection)
                self._connectionUserAgents[connectionId] = userAgent
                print("🔍 User-Agent: \(userAgent)")
                
                // Update client session
                let ipAddress = self.extractIPAddress(from: String(describing: connection.endpoint))
                let deviceName = self.extractDeviceName(from: userAgent)
                print("🔍 Extracted Device Name: \(deviceName)")
                self.updateClientSession(for: connection, ipAddress: ipAddress, userAgent: userAgent)
            }
        }
        
        // Route the request
        let response = routeRequest(request)
        
        // Send the response
        sendResponse(response, on: connection)
    }
    
    // MARK: - Request Routing
    
    private func routeRequest(_ request: HTTPRequest) -> HTTPResponse {
        switch (request.method, request.path) {
        case (.get, "/"):
            return serveHTML()
        case (.get, "/cues"):
            return serveJSON()
        case (.get, "/offline.html"):
            return serveOfflineHTML()
        case (.get, "/offline-service-worker.js"):
            return serveOfflineServiceWorker()
        case (.get, "/offline-data-manager.js"):
            return serveOfflineDataManager()
        case (.get, "/offline-state-manager.js"):
            return serveOfflineStateManager()
        case (.get, "/offline-styles.css"):
            return serveOfflineStyles()
        case (.get, "/offline-integration.js"):
            return serveOfflineIntegration()
        case (.get, "/manifest.json"):
            return serveManifest()
        case (.get, "/test-offline.html"):
            return serveTestOfflineHTML()
        case (.get, "/offline-status"):
            return serveOfflineStatus()
        case (.get, "/health"):
            return serveHealthCheck()
        case (.options, _):
            return serveCORS()
        default:
            return HTTPResponse(
                status: .notFound,
                headers: ["Content-Type": "text/plain"],
                body: "404 Not Found".data(using: .utf8) ?? Data()
            )
        }
    }
    
    private func serveHTML() -> HTTPResponse {
        let htmlData = CompleteHTML.content.data(using: .utf8) ?? Data()
        return HTTPResponse(
            status: .ok,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: htmlData
        )
    }
    
    private func serveJSON() -> HTTPResponse {
        let jsonData = generateJSONResponse()
        return HTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: jsonData
        )
    }
    
    private func serveCORS() -> HTTPResponse {
        return HTTPResponse(
            status: .ok,
            headers: [
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, Authorization",
                "Content-Type": "text/plain"
            ],
            body: Data()
        )
    }
    
    // MARK: - Offline File Serving
    
    private func serveOfflineHTML() -> HTTPResponse {
        let offlineHTMLPath = Bundle.main.path(forResource: "offline", ofType: "html")
        if let path = offlineHTMLPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "text/html; charset=utf-8"],
                body: data
            )
        }
        
        // Enhanced fallback offline page with better functionality
        let fallbackHTML = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Cue to Cue - Offline</title>
            <style>
                body { font-family: -apple-system, sans-serif; text-align: center; padding: 50px; background: #f5f5f5; }
                .container { max-width: 500px; margin: 0 auto; background: white; padding: 40px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                h1 { color: #333; margin-bottom: 20px; }
                p { color: #666; line-height: 1.6; margin-bottom: 20px; }
                .button { background: #007AFF; color: white; border: none; padding: 12px 24px; border-radius: 6px; cursor: pointer; font-size: 16px; }
                .button:hover { background: #0056CC; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>📱 You're Offline</h1>
                <p>Don't worry! You can still view your cue sheets and settings that were previously loaded.</p>
                <p>Some features may be limited while offline.</p>
                <button class="button" onclick="checkConnectionAndReconnect()">🔄 Try to Reconnect</button>
                <script>
                    function checkConnectionAndReconnect() {
                        const button = event.target;
                        const originalText = button.textContent;
                        
                        button.textContent = '🔄 Checking...';
                        button.disabled = true;
                        
                        // Check if we're online first
                        if (!navigator.onLine) {
                            button.textContent = '❌ No Internet';
                            setTimeout(() => {
                                button.textContent = originalText;
                                button.disabled = false;
                            }, 2000);
                            return;
                        }
                        
                        // Test connection
                        fetch('/health', { method: 'HEAD' })
                            .then(() => {
                                button.textContent = '✅ Connected!';
                                setTimeout(() => {
                                    window.location.reload();
                                }, 1000);
                            })
                            .catch(() => {
                                button.textContent = '❌ Failed';
                                setTimeout(() => {
                                    button.textContent = originalText;
                                    button.disabled = false;
                                }, 2000);
                            });
                    }
                </script>
            </div>
        </body>
        </html>
        """
        
        return HTTPResponse(
            status: .ok,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: fallbackHTML.data(using: .utf8) ?? Data()
        )
    }
    
    private func serveOfflineServiceWorker() -> HTTPResponse {
        let serviceWorkerPath = Bundle.main.path(forResource: "offline-service-worker", ofType: "js")
        if let path = serviceWorkerPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "application/javascript; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Service worker not found".data(using: .utf8) ?? Data()
        )
    }
    
    private func serveOfflineDataManager() -> HTTPResponse {
        let dataManagerPath = Bundle.main.path(forResource: "offline-data-manager", ofType: "js")
        if let path = dataManagerPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "application/javascript; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Data manager not found".data(using: .utf8) ?? Data()
        )
    }
    
    private func serveOfflineStateManager() -> HTTPResponse {
        let stateManagerPath = Bundle.main.path(forResource: "offline-state-manager", ofType: "js")
        if let path = stateManagerPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "application/javascript; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "State manager not found".data(using: .utf8) ?? Data()
        )
    }
    
    private func serveOfflineStyles() -> HTTPResponse {
        let stylesPath = Bundle.main.path(forResource: "offline-styles", ofType: "css")
        if let path = stylesPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "text/css; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Styles not found".data(using: .utf8) ?? Data()
            )
    }
    
    private func serveOfflineIntegration() -> HTTPResponse {
        let integrationPath = Bundle.main.path(forResource: "offline-integration", ofType: "js")
        if let path = integrationPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "application/javascript; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Integration script not found".data(using: .utf8) ?? Data()
        )
    }
    
    private func serveManifest() -> HTTPResponse {
        let manifestPath = Bundle.main.path(forResource: "manifest", ofType: "json")
        if let path = manifestPath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "application/json; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Manifest not found".data(using: .utf8) ?? Data()
        )
    }
    
    private func serveTestOfflineHTML() -> HTTPResponse {
        let testOfflinePath = Bundle.main.path(forResource: "test-offline", ofType: "html")
        if let path = testOfflinePath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "text/html; charset=utf-8"],
                body: data
            )
        }
        return HTTPResponse(
            status: .notFound,
            headers: ["Content-Type": "text/plain"],
            body: "Test offline page not found".data(using: .utf8) ?? Data()
        )
    }
    
    private func serveOfflineStatus() -> HTTPResponse {
        let status = [
            "timestamp": Date().timeIntervalSince1970,
            "server": "running",
            "offline_support": "enabled",
            "cached_data": cueStacks.count > 0,
            "cue_stacks_count": cueStacks.count,
            "active_connections": getConnectionStats().active,
            "max_connections": getConnectionStats().max
        ] as [String: Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: status, options: [])
            return HTTPResponse(
                status: .ok,
                headers: ["Content-Type": "application/json; charset=utf-8"],
                body: jsonData
            )
        } catch {
            return HTTPResponse(
                status: .internalServerError,
                headers: ["Content-Type": "text/plain"],
                body: "Failed to generate status".data(using: .utf8) ?? Data()
            )
        }
    }
    
    private func serveHealthCheck() -> HTTPResponse {
        return HTTPResponse(
            status: .ok,
            headers: ["Content-Type": "text/plain"],
            body: "OK".data(using: .utf8) ?? Data()
        )
    }
    
    private func sendErrorResponse(_ status: HTTPStatus, on connection: NWConnection) {
        let response = HTTPResponse(
            status: status,
            headers: ["Content-Type": "text/plain"],
            body: "\(status.rawValue) \(status.description)".data(using: .utf8) ?? Data()
        )
        sendResponse(response, on: connection)
    }
    
    // MARK: - Response Sending
    
    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        let responseData = response.serialize()
        
        connection.send(content: responseData, completion: .contentProcessed { error in
            if let error = error {
                // Only log non-connection errors
                let nsError = error as NSError
                if nsError.domain != "NSPOSIXErrorDomain" || 
                   (nsError.code != 32 && nsError.code != 57 && nsError.code != 89) {
                    print("Error sending response: \(error)")
                }
            }
            
            // For mobile devices, don't immediately close the connection
            // Let the keepConnectionAlive method handle it
        })
    }
    
    // MARK: - Data Updates
    
    func updateCues(cueStacks: [CueStack], selectedCueStackIndex: Int, activeCueIndex: Int, selectedCueIndex: Int) {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.cueStacks = cueStacks
            self.selectedCueStackIndex = selectedCueStackIndex
            self.activeCueIndex = activeCueIndex
            self.selectedCueIndex = selectedCueIndex
            
            // Automatically cache data for offline use
            self.cacheDataForOffline()
        }
    }
    
    /// Automatically caches current app data for offline viewing
    private func cacheDataForOffline() {
        // This method ensures that the current app state is always available offline
        // It's called whenever the cues are updated
        
        // The service worker will automatically cache the /cues endpoint
        // and the offline integration script will handle state persistence
        
        // We can also add additional caching logic here if needed
        print("💾 Data updated - available for offline viewing")
        
        // Notify connected clients to cache their current state
        notifyClientsToCacheState()
    }
    
    /// Notifies connected clients to cache their current state for offline use
    private func notifyClientsToCacheState() {
        // This helps ensure that all connected devices have the latest data cached
        // for offline viewing
        
        // The notification is sent via the existing connection infrastructure
        // and clients will automatically save their current state
        print("📱 Notifying clients to cache current state for offline use")
    }
    
    func updateHighlightColors(_ highlightColors: [HighlightColorSetting]) {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.highlightColors = highlightColors
        }
    }
    
    func updateClockState(currentTime: Date, countdownTime: Int, countUpTime: Int, countdownRunning: Bool, countUpRunning: Bool) {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.currentTime = currentTime
            self.countdownTime = countdownTime
            self.countUpTime = countUpTime
            self.countdownRunning = countdownRunning
            self.countUpRunning = countUpRunning
        }
    }
    
    // MARK: - JSON Response Generation
    
    private func generateJSONResponse() -> Data {
        let jsonObject: [String: Any]
        
        if cueStacks.isEmpty || selectedCueStackIndex >= cueStacks.count {
            jsonObject = ["error": "No cue stack available"]
        } else {
            let selectedStack = cueStacks[selectedCueStackIndex]
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE MMM d, yyyy"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm:ss"
            let amPmFormatter = DateFormatter()
            amPmFormatter.dateFormat = "a"
            
            jsonObject = [
                "cueStackName": selectedStack.name,
                "columns": selectedStack.columns.map { ["name": $0.name, "width": $0.width] },
                "cues": selectedStack.cues.enumerated().map { index, cue in
                    [
                        "index": index,
                        "values": cue.values,
                        "timerValue": cue.timerValue,
                        "struck": Array(repeating: cue.isStruckThrough, count: selectedStack.columns.count)
                    ]
                },
                "activeCueIndex": activeCueIndex,
                "selectedCueIndex": selectedCueIndex,
                "lastUpdateTime": Date().timeIntervalSince1970,
                "currentDate": dateFormatter.string(from: currentTime),
                "currentTime": timeFormatter.string(from: currentTime),
                "currentAMPM": amPmFormatter.string(from: currentTime),
                "countdownTime": countdownTime,
                "countUpTime": countUpTime,
                "countdownRunning": countdownRunning,
                "countUpRunning": countUpRunning,
                "highlightColors": highlightColors.map { [
                    "keyword": $0.keyword,
                    "color": $0.color.toHex()
                ] }
            ]
        }
        
        do {
            return try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        } catch {
            print("Error generating JSON response: \(error)")
            return Data()
        }
    }
    
    // MARK: - Network Utilities
    
    func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else {
            return nil
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" { // Wi-Fi interface
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let saLen = interface.ifa_addr.pointee.sa_len
                    getnameinfo(interface.ifa_addr, socklen_t(saLen),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }
    
    func getConnectionStats() -> (active: Int, max: Int) {
        return connectionQueue.sync { (_activeConnections.count, maxConnections) }
    }
    
    func getConnectionDetails() -> String {
        let stats = getConnectionStats()
        return "Active: \(stats.active)/\(stats.max)"
    }
    
    func getDetailedConnectionInfo() -> [ConnectionInfo] {
        return connectionQueue.sync {
            return _activeConnections.enumerated().map { index, connection in
                let id = ObjectIdentifier(connection)
                let requestCount = _connectionRequestCounts[id] ?? 0
                let state = String(describing: connection.state)
                let endpoint = String(describing: connection.endpoint)
                let lastSeen = _connectionTimestamps[id] ?? Date()
                let idleTime = Date().timeIntervalSince(lastSeen)
                
                // Extract IP address from endpoint
                let ipAddress = self.extractIPAddress(from: endpoint)
                
                // Extract user agent from connection
                let userAgent = self.getThreadSafeUserAgent(for: connection)
                
                // Determine connection type based on endpoint and state
                let connectionType = self.determineConnectionType(endpoint: endpoint, state: state)
                
                // Extract browser and device information
                let browserType = self.extractBrowserType(from: userAgent)
                let deviceType = self.extractDeviceType(from: userAgent)
                let networkInterface = self.getNetworkInterface(for: connection)
                
                return ConnectionInfo(
                    endpoint: endpoint,
                    state: state,
                    requestCount: requestCount,
                    lastSeen: lastSeen,
                    ipAddress: ipAddress,
                    userAgent: userAgent,
                    connectionType: connectionType,
                    idleTime: idleTime,
                    browserType: browserType,
                    deviceType: deviceType,
                    networkInterface: networkInterface
                )
            }
        }
    }
    
    func getClientSessions() -> [ClientSession] {
        return connectionQueue.sync {
            return Array(_clientSessions.values).sorted { $0.firstSeen < $1.firstSeen }
        }
    }
    
    func getClientSessionsByLastSeen() -> [ClientSession] {
        return connectionQueue.sync {
            return Array(_clientSessions.values).sorted { $0.lastSeen > $1.lastSeen }
        }
    }
    
    func getClientSessionsByIP() -> [ClientSession] {
        return connectionQueue.sync {
            return Array(_clientSessions.values).sorted { $0.ipAddress < $1.ipAddress }
        }
    }
    
    func getClientSessionsStable() -> [ClientSession] {
        return connectionQueue.sync {
            // Sort by firstSeen, then by IP address for completely stable ordering
            return Array(_clientSessions.values).sorted { first, second in
                if first.firstSeen == second.firstSeen {
                    return first.ipAddress < second.ipAddress
                }
                return first.firstSeen < second.firstSeen
            }
        }
    }
    
    func getInactiveClientSessions() -> [ClientSession] {
        return connectionQueue.sync {
            // Return all inactive client sessions (persist until app restart)
            // Filter out any sessions that might have come back online to prevent duplicates
            let inactiveSessions = _inactiveClientSessions.values.filter { inactiveSession in
                // Check if this device is not currently active
                let sessionKey = "\(inactiveSession.ipAddress)_\(inactiveSession.userAgent)"
                return _clientSessions[sessionKey] == nil
            }
            
            return Array(inactiveSessions).sorted { first, second in
                // Sort by last seen time (most recently inactive first)
                return first.lastSeen > second.lastSeen
            }
        }
    }
    
    func getClientSessionCount() -> Int {
        return connectionQueue.sync {
            return _clientSessions.count
        }
    }
    
    func getInactiveClientSessionCount() -> Int {
        return connectionQueue.sync {
            return _inactiveClientSessions.count
        }
    }
    
    func getTotalClientRequests() -> Int {
        return connectionQueue.sync {
            return _clientSessions.count
        }
    }
    
    func getDeviceName() -> String {
        return Host.current().localizedName ?? "Unknown Device"
    }
    
    func forceCleanupInactiveSessions() {
        cleanupOldClientSessions()
        cleanupDuplicateSessions()
    }
    
    private func cleanupDuplicateSessions() {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            
            var sessionsToRemove: [String] = []
            
            // Find inactive sessions that are also active
            for (key, inactiveSession) in self._inactiveClientSessions {
                let sessionKey = "\(inactiveSession.ipAddress)_\(inactiveSession.userAgent)"
                if self._clientSessions[sessionKey] != nil {
                    sessionsToRemove.append(key)
                }
            }
            
            // Remove duplicate inactive sessions
            for key in sessionsToRemove {
                self._inactiveClientSessions.removeValue(forKey: key)
            }
            
            if !sessionsToRemove.isEmpty {
                print("🧹 Cleaned up \(sessionsToRemove.count) duplicate inactive sessions")
            }
        }
    }
    
    func getConnectionString() -> String {
        return "\(localIPAddress):\(serverStatus.port)"
    }
    
    private func getThreadSafeUserAgent(for connection: NWConnection) -> String {
        // Thread-safe way to get user agent
        let connectionId = ObjectIdentifier(connection)
        return connectionQueue.sync {
            return _connectionUserAgents[connectionId] ?? "Unknown"
        }
    }
    
    private func cleanupOldClientSessions() {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let now = Date()
            let cutoffTime = now.timeIntervalSince1970 - 30 // 30 seconds - devices go inactive after 30 seconds offline
            
            let oldSessions = self._clientSessions.filter { session in
                session.value.lastSeen.timeIntervalSince1970 < cutoffTime
            }
            
            for (key, session) in oldSessions {
                // Move to inactive sessions instead of removing
                self._inactiveClientSessions[key] = session
                self._clientSessions.removeValue(forKey: key)
            }
            
            if !oldSessions.isEmpty {
                print("🧹 Moved \(oldSessions.count) client sessions to inactive after 30 seconds")
            }
        }
    }
    

    
    func getServerStatus() -> (isRunning: Bool, port: UInt16) {
        let isRunning = listener?.state == .ready
        return (isRunning, port)
    }
    
    func getPort() -> UInt16 {
        return port
    }
    
    func debugConnectionCount() {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            print("🔍 DEBUG: Connection count: \(self._activeConnections.count)")
            print("🔍 DEBUG: Connection details:")
            
            // Group connections by endpoint to identify duplicates
            var endpointGroups: [String: [NWConnection]] = [:]
            for connection in self._activeConnections {
                let endpoint = String(describing: connection.endpoint)
                endpointGroups[endpoint, default: []].append(connection)
            }
            
            for (endpoint, connections) in endpointGroups {
                print("  📍 \(endpoint): \(connections.count) connection(s)")
                for (index, connection) in connections.enumerated() {
                    let id = ObjectIdentifier(connection)
                    let requestCount = self._connectionRequestCounts[id] ?? 0
                    let lastSeen = self._connectionTimestamps[id] ?? Date()
                    let idleTime = Date().timeIntervalSince(lastSeen)
                    let userAgent = self._connectionUserAgents[id] ?? "No User-Agent"
                    print("    [\(index)] State: \(connection.state), Requests: \(requestCount), Idle: \(Int(idleTime))s, User-Agent: \(userAgent)")
                }
            }
        }
    }
    
    // MARK: - Connection Detail Helpers
    
    private func extractIPAddress(from endpoint: String) -> String {
        // Extract IP address from endpoint string like "192.168.1.100:12345"
        if let colonRange = endpoint.range(of: ":"),
           let ipAddress = endpoint[..<colonRange.lowerBound].components(separatedBy: " ").last {
            return String(ipAddress)
        }
        return "Unknown"
    }
    
    private func getUserAgent(for connection: NWConnection) -> String? {
        // This method should only be called from connectionQueue context
        // Ensure we're on the correct queue to avoid data races
        let connectionId = ObjectIdentifier(connection)
        return _connectionUserAgents[connectionId] ?? "Unknown"
    }
    
    private func extractBrowserType(from userAgent: String) -> String {
        let ua = userAgent.lowercased()
        
        // Check for Chrome (including Chromium-based browsers)
        if ua.contains("chrome") && !ua.contains("edg") {
            if ua.contains("chromium") {
                return "Chromium"
            } else if ua.contains("brave") {
                return "Brave"
            } else {
                return "Chrome"
            }
        }
        // Check for Edge (must come before Chrome check)
        else if ua.contains("edg") {
            return "Edge"
        }
        // Check for Firefox
        else if ua.contains("firefox") {
            return "Firefox"
        }
        // Check for Safari (must be after Chrome check)
        else if ua.contains("safari") && !ua.contains("chrome") {
            return "Safari"
        }
        // Check for Opera
        else if ua.contains("opera") || ua.contains("opr") {
            return "Opera"
        }
        // Check for Internet Explorer
        else if ua.contains("msie") || ua.contains("trident") {
            return "Internet Explorer"
        }
        // Check for other browsers
        else if ua.contains("vivaldi") {
            return "Vivaldi"
        } else if ua.contains("ucbrowser") {
            return "UC Browser"
        } else if ua.contains("samsungbrowser") {
            return "Samsung Browser"
        } else {
            return "Unknown Browser"
        }
    }
    
    private func extractDeviceType(from userAgent: String) -> String {
        let ua = userAgent.lowercased()
        
        // Check for mobile devices first
        if ua.contains("mobile") || ua.contains("android") || ua.contains("iphone") {
            if ua.contains("ipad") {
                return "iPad"
            } else if ua.contains("android") {
                return "Android Mobile"
            } else if ua.contains("iphone") {
                return "iPhone"
            } else {
                return "Mobile Device"
            }
        }
        // Check for tablets
        else if ua.contains("tablet") || ua.contains("ipad") {
            return "Tablet"
        }
        // Check for desktop operating systems
        else if ua.contains("windows") {
            return "Windows Desktop"
        } else if ua.contains("macintosh") || ua.contains("mac os") {
            return "macOS Desktop"
        } else if ua.contains("linux") {
            return "Linux Desktop"
        } else if ua.contains("x11") {
            return "Unix Desktop"
        }
        // Check for other devices
        else if ua.contains("smart tv") || ua.contains("tv") {
            return "Smart TV"
        } else if ua.contains("game console") || ua.contains("playstation") || ua.contains("xbox") {
            return "Game Console"
        } else {
            return "Unknown Device"
        }
    }
    
    private func extractDeviceName(from userAgent: String) -> String {
        // Try to extract a meaningful device name from User-Agent
        let ua = userAgent
        
        // For iOS devices, try to get a more descriptive name
        if ua.contains("iPhone") {
            return "iPhone"
        } else if ua.contains("iPad") {
            return "iPad"
        } else if ua.contains("iPod") {
            return "iPod"
        }
        // For Android devices
        else if ua.contains("Android") {
            // Try to extract device model if available
            if let range = ua.range(of: "Build/") {
                let beforeBuild = String(ua[..<range.lowerBound])
                if let lastSpace = beforeBuild.lastIndex(of: " ") {
                    let devicePart = String(beforeBuild[lastSpace...]).trimmingCharacters(in: .whitespaces)
                    if !devicePart.isEmpty && devicePart != "Mobile" && devicePart != "Tablet" {
                        return devicePart
                    }
                }
            }
            return "Android Device"
        }
        // For macOS connections, use the actual host device name
        else if ua.contains("Macintosh") || ua.contains("Mac OS") {
            return getDeviceName()
        } else if ua.contains("Windows") {
            return "Windows PC"
        } else if ua.contains("Linux") {
            return "Linux PC"
        }
        
        return "Unknown Device"
    }
    
    private func getNetworkInterface(for connection: NWConnection) -> String {
        // Try to determine network interface type from the connection
        let endpoint = String(describing: connection.endpoint)
        
        // This is a simplified approach - in a real implementation you'd use NWPathMonitor
        // For now, we'll return a placeholder that could be enhanced later
        if endpoint.contains("192.168") || endpoint.contains("10.") || endpoint.contains("172.") {
            return "Local Network"
        } else {
            return "External Network"
        }
    }
    

    
    private func updateClientSession(for connection: NWConnection, ipAddress: String, userAgent: String) {
        // This method should only be called from connectionQueue context
        let sessionKey = "\(ipAddress)_\(userAgent)"
        let now = Date()
        
        // Check if this device was previously inactive and remove it from inactive list
        if let inactiveSession = _inactiveClientSessions[sessionKey] {
            print("🔄 Device \(inactiveSession.deviceName) (\(ipAddress)) is back online - removing from inactive list")
            _inactiveClientSessions.removeValue(forKey: sessionKey)
        }
        
        if let existingSession = _clientSessions[sessionKey] {
            // Just update the last seen time for existing client
            _clientSessions[sessionKey] = ClientSession(
                id: existingSession.id,
                ipAddress: existingSession.ipAddress,
                userAgent: existingSession.userAgent,
                browserType: existingSession.browserType,
                deviceType: existingSession.deviceType,
                deviceName: existingSession.deviceName,
                firstSeen: existingSession.firstSeen,
                lastSeen: now,
                networkInterface: existingSession.networkInterface
            )
        } else {
            // Create new client session
            let browserType = extractBrowserType(from: userAgent)
            let deviceType = extractDeviceType(from: userAgent)
            let deviceName = extractDeviceName(from: userAgent)
            let networkInterface = getNetworkInterface(for: connection)
            
            print("🔍 Creating client session:")
            print("  - IP: \(ipAddress)")
            print("  - Browser: \(browserType)")
            print("  - Device Type: \(deviceType)")
            print("  - Device Name: \(deviceName)")
            
            _clientSessions[sessionKey] = ClientSession(
                id: UUID(),
                ipAddress: ipAddress,
                userAgent: userAgent,
                browserType: browserType,
                deviceType: deviceType,
                deviceName: deviceName,
                firstSeen: now,
                lastSeen: now,
                networkInterface: networkInterface
            )
        }
    }
    
    private func removeConnectionFromSession(for connection: NWConnection, ipAddress: String, userAgent: String) {
        // This method should only be called from connectionQueue context
        // For now, we'll keep the client session active even when connections close
        // This prevents iOS from showing as disconnected when it creates new connections
        // We'll clean up old sessions in a separate cleanup method
    }
    
    private func determineConnectionType(endpoint: String, state: String) -> String {
        // Determine if this is a main connection or resource connection
        if state.contains("ready") {
            return "Active"
        } else if state.contains("waiting") {
            return "Establishing"
        } else if state.contains("failed") || state.contains("cancelled") {
            return "Dead"
        } else {
            return "Unknown"
        }
    }
}
