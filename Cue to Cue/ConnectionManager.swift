//
//  ConnectionManager.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/31/24.
//

import Foundation
import Network
import Combine

class ConnectionManager: ObservableObject {
    
    // MARK: - Properties
    
    private var _activeConnections: [NWConnection] = []
    private var _connectionRequestCounts: [ObjectIdentifier: Int] = [:]
    private var _connectionTimestamps: [ObjectIdentifier: Date] = [:]
    private var _connectionUserAgents: [ObjectIdentifier: String] = [:]
    private var _clientSessions: [String: ClientSession] = [:] // Group by client IP + User-Agent
    private var _inactiveClientSessions: [String: ClientSession] = [:] // Store inactive sessions until app restart
    private let maxConnections = 100 // Support 100+ devices
    
    // Connection management - use serial queue for thread safety
    private let connectionQueue = DispatchQueue(label: "ConnectionManager.connectionQueue")
    
    // Published properties for UI updates
    @Published var connectionStats: (active: Int, max: Int) = (0, 100)
    @Published var detailedConnectionInfo: [ConnectionInfo] = []
    
    // MARK: - Dependencies
    private let httpHandler: HTTPHandler
    
    init(httpHandler: HTTPHandler) {
        self.httpHandler = httpHandler
        initializePublishedProperties()
    }
    
    // MARK: - Connection Management
    
    func handleNewConnection(_ connection: NWConnection) {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check connection limit
            if self._activeConnections.count >= self.maxConnections {
                connection.cancel()
                return
            }
            
            // Check for duplicate connections from the same endpoint
            let connectionEndpoint = String(describing: connection.endpoint)
            let existingConnections = self._activeConnections.filter { 
                String(describing: $0.endpoint) == connectionEndpoint 
            }
            
            if existingConnections.count >= 1 {
                connection.cancel()
                return
            }
            
            self._activeConnections.append(connection)
            self._connectionRequestCounts[ObjectIdentifier(connection)] = 0
            self._connectionTimestamps[ObjectIdentifier(connection)] = Date()
            
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
            receiveRequest(on: connection)
        case .failed:
            cleanupConnection(connection)
        case .cancelled:
            cleanupConnection(connection)
        case .waiting:
            // Give mobile connections time to establish
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) { [weak self] in
                if case .waiting = connection.state {
                    self?.cleanupConnection(connection)
                }
            }
        case .preparing:
            break
        case .setup:
            break
        @unknown default:
            break
        }
    }
    
    func cleanupConnection(_ connection: NWConnection) {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            if let index = self._activeConnections.firstIndex(where: { $0 === connection }) {
                self._activeConnections.remove(at: index)
                // Remove request count tracking
                let id = ObjectIdentifier(connection)
                let _ = self._connectionRequestCounts[id] ?? 0 // Track request count
                let userAgent = self._connectionUserAgents[id] ?? "Unknown"
                let ipAddress = NetworkUtilities.extractIPAddress(from: String(describing: connection.endpoint))
                
                // Clean up tracking data
                self._connectionRequestCounts.removeValue(forKey: id)
                self._connectionTimestamps.removeValue(forKey: id)
                self._connectionUserAgents.removeValue(forKey: id)
                
                // Update client session
                self.removeConnectionFromSession(for: connection, ipAddress: ipAddress, userAgent: userAgent)
            }
            // Update published properties safely
            self.updatePublishedProperties()
        }
        connection.cancel()
    }
    
    func incrementRequestCount(for connection: NWConnection) {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            let id = ObjectIdentifier(connection)
            let currentCount = self._connectionRequestCounts[id] ?? 0
            self._connectionRequestCounts[id] = currentCount + 1
            self._connectionTimestamps[id] = Date() // Update last seen time
            
            // Update published properties safely
            self.updatePublishedProperties()
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
        // Extract and store User-Agent header
        if let request = HTTPRequest(from: data),
           let userAgent = request.headers["user-agent"] {
            // Store User-Agent on connectionQueue to avoid data races
            connectionQueue.async { [weak self] in
                guard let self = self else { return }
                let connectionId = ObjectIdentifier(connection)
                self._connectionUserAgents[connectionId] = userAgent
                
                // Update client session
                let ipAddress = NetworkUtilities.extractIPAddress(from: String(describing: connection.endpoint))
                self.updateClientSession(for: connection, ipAddress: ipAddress, userAgent: userAgent)
            }
        }
        
        // Route the request through HTTP handler
        let response = httpHandler.processRequest(data, on: connection)
        
        // Send the response
        httpHandler.sendResponse(response, on: connection)
    }
    
    private func continueListening(on connection: NWConnection) {
        // Continue listening for more requests on the same connection
        // This enables HTTP Keep-Alive and connection reuse
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { [weak self] in
            // Only continue if connection is still alive
            if connection.state == .ready {
                self?.receiveRequest(on: connection)
            } else {
                // Connection is dead, clean it up
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
    
    // MARK: - Client Session Management
    
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
            let browserType = NetworkUtilities.extractBrowserType(from: userAgent)
            let deviceType = NetworkUtilities.extractDeviceType(from: userAgent)
            let deviceName = NetworkUtilities.extractDeviceName(from: userAgent)
            let networkInterface = NetworkUtilities.getNetworkInterface(for: connection)
            
            
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
    
    // MARK: - Cleanup and Monitoring
    
    func startConnectionCleanup() {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.cleanupStaleConnections()
        }
    }
    
    func startConnectionMonitoring() {
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
            
            let staleConnections = self._activeConnections.filter { connection in
                // Remove connections that are definitely dead
                if case .failed = connection.state { return true }
                if case .cancelled = connection.state { return true }
                
                // Also remove connections that have been idle for too long
                let id = ObjectIdentifier(connection)
                if let lastSeen = self._connectionTimestamps[id] {
                    let idleTime = Date().timeIntervalSince(lastSeen)
                    if idleTime > 300 { // 5 minutes of inactivity
                        return true
                    }
                }
                
                return false
            }
            
            
            for connection in staleConnections {
                if let index = self._activeConnections.firstIndex(where: { $0 === connection }) {
                    self._activeConnections.remove(at: index)
                    // Clean up associated data
                    let id = ObjectIdentifier(connection)
                    let userAgent = self._connectionUserAgents[id] ?? "Unknown"
                    let ipAddress = NetworkUtilities.extractIPAddress(from: String(describing: connection.endpoint))
                    
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
            }
        }
    }
    
    // MARK: - Published Properties Management
    
    private func initializePublishedProperties() {
        // Initialize with default values on main queue
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Set initial values for published properties
            self.connectionStats = (active: 0, max: self.maxConnections)
            self.detailedConnectionInfo = []
        }
    }
    
    func updatePublishedProperties() {
        // This method is called from connectionQueue context, so we can safely access private properties
        
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
                let ipAddress = NetworkUtilities.extractIPAddress(from: endpoint)
                
                // Extract user agent from connection (we'll need to store this)
                let userAgent = self.getThreadSafeUserAgent(for: connection)
                
                // Determine connection type based on endpoint and state
                let connectionType = NetworkUtilities.determineConnectionType(endpoint: endpoint, state: state)
                
                // Extract browser and device information
                let browserType = NetworkUtilities.extractBrowserType(from: userAgent)
                let deviceType = NetworkUtilities.extractDeviceType(from: userAgent)
                let networkInterface = NetworkUtilities.getNetworkInterface(for: connection)
                
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
    
    func refreshPublishedProperties() {
        // This method can be called from any thread, including main thread
        connectionQueue.async { [weak self] in
            self?.updatePublishedProperties()
        }
    }
    
    // MARK: - Public Interface
    
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
                let ipAddress = NetworkUtilities.extractIPAddress(from: endpoint)
                
                // Extract user agent from connection
                let userAgent = self.getThreadSafeUserAgent(for: connection)
                
                // Determine connection type based on endpoint and state
                let connectionType = NetworkUtilities.determineConnectionType(endpoint: endpoint, state: state)
                
                // Extract browser and device information
                let browserType = NetworkUtilities.extractBrowserType(from: userAgent)
                let deviceType = NetworkUtilities.extractDeviceType(from: userAgent)
                let networkInterface = NetworkUtilities.getNetworkInterface(for: connection)
                
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
            }
        }
    }
    
    func debugConnectionCount() {
        // Debug method kept for potential future use but logging removed
    }
    
    // MARK: - Helper Methods
    
    private func getThreadSafeUserAgent(for connection: NWConnection) -> String {
        // Thread-safe way to get user agent
        let connectionId = ObjectIdentifier(connection)
        return connectionQueue.sync {
            return _connectionUserAgents[connectionId] ?? "Unknown"
        }
    }
    
    func stop() {
        // Close all active connections
        connectionQueue.async { [weak self] in
            self?._activeConnections.forEach { connection in
                connection.cancel()
            }
            self?._activeConnections.removeAll()
        }
    }
}
