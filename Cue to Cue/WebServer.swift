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

// MARK: - WebServer Class

class WebServer: ObservableObject {
    
    // MARK: - Properties
    
    private var listener: NWListener?
    private var port: UInt16
    private var _serverStartTime: Date?
    
    // Published properties for UI updates
    @Published var connectionStats: (active: Int, max: Int) = (0, 100)
    @Published var detailedConnectionInfo: [ConnectionInfo] = []
    @Published var serverStatus: (isRunning: Bool, port: UInt16) = (false, 8080)
    @Published var localIPAddress: String = "Unknown"
    
    // MARK: - Dependencies
    
    private let connectionManager: ConnectionManager
    private let httpHandler: HTTPHandler
    private let offlineFileServer: OfflineFileServer
    private let dataSyncManager: DataSyncManager
    private let networkUtilities: NetworkUtilities
    
    // MARK: - Initialization
    
    init() {
        self.port = 8080
        
        // Initialize dependencies
        self.dataSyncManager = DataSyncManager()
        self.networkUtilities = NetworkUtilities()
        self.offlineFileServer = OfflineFileServer()
        
        // Create a temporary HTTPHandler for ConnectionManager initialization
        let tempHTTPHandler = HTTPHandler(dataSyncManager: dataSyncManager, offlineFileServer: offlineFileServer, networkUtilities: networkUtilities, connectionManager: nil)
        self.connectionManager = ConnectionManager(httpHandler: tempHTTPHandler)
        
        // Now create the real HTTPHandler with the connection manager
        self.httpHandler = HTTPHandler(dataSyncManager: dataSyncManager, offlineFileServer: offlineFileServer, networkUtilities: networkUtilities, connectionManager: connectionManager)
        
        // Initialize published properties safely for initialization
        initializePublishedProperties()
        
        // Set up bindings to connection manager
        setupBindings()
    }
    
    // MARK: - Server Management
    
    func start(port: UInt16) {
        // Stop any existing server first
        stop()
        
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
        
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleListenerStateChange(state)
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
                        self?.connectionManager.handleNewConnection(connection)
        }
        
        listener?.start(queue: .global(qos: .userInitiated))
        
        // Start periodic connection cleanup and monitoring
            connectionManager.startConnectionCleanup()
            connectionManager.startConnectionMonitoring()
        
        // Initialize published properties
        updatePublishedProperties()
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        self?.serverStatus = (isRunning: false, port: port)
                    }
                }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        
        // Stop connection manager
        connectionManager.stop()
        
        // Update published properties
        DispatchQueue.main.async { [weak self] in
            self?.serverStatus = (isRunning: false, port: self?.port ?? 8080)
            self?.connectionStats = (active: 0, max: 100)
            self?.detailedConnectionInfo = []
        }
    }
    
    // MARK: - Listener State Management
    
    private func handleListenerStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            break
        case .failed(_):
            break
        case .cancelled:
            break
        case .waiting(_):
            break
        case .setup:
            break
        @unknown default:
            break
        }
    }
    
    // MARK: - Data Updates
    
    func updateCues(cueStacks: [CueStack], selectedCueStackIndex: Int, activeCueIndex: Int, selectedCueIndex: Int) {
        dataSyncManager.updateCues(cueStacks: cueStacks, selectedCueStackIndex: selectedCueStackIndex, activeCueIndex: activeCueIndex, selectedCueIndex: selectedCueIndex)
    }
    
    func updateHighlightColors(_ highlightColors: [HighlightColorSetting]) {
        dataSyncManager.updateHighlightColors(highlightColors)
    }
    
    func updateClockState(currentTime: Date, countdownTime: Int, countUpTime: Int, countdownRunning: Bool, countUpRunning: Bool) {
        dataSyncManager.updateClockState(currentTime: currentTime, countdownTime: countdownTime, countUpTime: countUpTime, countdownRunning: countdownRunning, countUpRunning: countUpRunning)
    }
    
    // MARK: - Network Utilities
    
    func getLocalIPAddress() -> String? {
        return NetworkUtilities.getLocalIPAddress()
    }
    
    func getConnectionStats() -> (active: Int, max: Int) {
        return connectionManager.getConnectionStats()
    }
    
    func getConnectionDetails() -> String {
        return connectionManager.getConnectionDetails()
    }
    
    func getDetailedConnectionInfo() -> [ConnectionInfo] {
        return connectionManager.getDetailedConnectionInfo()
    }
    
    func getClientSessions() -> [ClientSession] {
        return connectionManager.getClientSessions()
    }
    
    func getClientSessionsByLastSeen() -> [ClientSession] {
        return connectionManager.getClientSessionsByLastSeen()
    }
    
    func getClientSessionsByIP() -> [ClientSession] {
        return connectionManager.getClientSessionsByIP()
    }
    
    func getClientSessionsStable() -> [ClientSession] {
        return connectionManager.getClientSessionsStable()
    }
    
    func getInactiveClientSessions() -> [ClientSession] {
        return connectionManager.getInactiveClientSessions()
    }
    
    func getClientSessionCount() -> Int {
        return connectionManager.getClientSessionCount()
    }
    
    func getInactiveClientSessionCount() -> Int {
        return connectionManager.getInactiveClientSessionCount()
    }
    
    func getTotalClientRequests() -> Int {
        return connectionManager.getTotalClientRequests()
    }
    
    func getDeviceName() -> String {
        return NetworkUtilities.getDeviceName()
    }
    
    func forceCleanupInactiveSessions() {
        connectionManager.forceCleanupInactiveSessions()
    }
    
    func getConnectionString() -> String {
        return "\(localIPAddress):\(serverStatus.port)"
    }
    
    func getServerStatus() -> (isRunning: Bool, port: UInt16) {
        let isRunning = listener?.state == .ready
        return (isRunning, port)
    }
    
    func getPort() -> UInt16 {
        return port
    }
    
    func debugConnectionCount() {
        connectionManager.debugConnectionCount()
    }
    
    // MARK: - Published Properties Management
    
    private func initializePublishedProperties() {
        // Initialize with default values on main queue
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Set initial values for published properties
            self.connectionStats = (active: 0, max: 100)
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
    
    private func setupBindings() {
        // Bind connection manager's published properties to our published properties
        connectionManager.$connectionStats
            .assign(to: &$connectionStats)
        
        connectionManager.$detailedConnectionInfo
            .assign(to: &$detailedConnectionInfo)
    }
    
    private func updatePublishedProperties() {
        // Update server status
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.serverStatus = (isRunning: self.listener?.state == .ready, port: self.port)
            
            // Update local IP address
            if let ipAddress = self.getLocalIPAddress() {
                self.localIPAddress = ipAddress
            }
        }
    }
    
    func refreshPublishedProperties() {
        connectionManager.refreshPublishedProperties()
        updatePublishedProperties()
    }
}