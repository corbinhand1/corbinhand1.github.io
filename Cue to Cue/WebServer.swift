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
    private static var isListening = false
    
    // Published properties for UI updates
    @Published var connectionStats: (active: Int, max: Int) = (0, 100)
    @Published var detailedConnectionInfo: [ConnectionInfo] = []
    @Published var serverStatus: (isRunning: Bool, port: UInt16) = (false, 8080)
    @Published var localIPAddress: String = "Unknown"
    
    // MARK: - Dependencies
    
    private let connectionManager: ConnectionManager
    private let httpHandler: HTTPHandler
    private let offlineFileServer: OfflineFileServer
    let dataSyncManager: DataSyncManager
    private let networkUtilities: NetworkUtilities
    let authManager: AuthenticationManager
    private let timerServer: AuthoritativeTimerServer
    let broadcastHub: LANBroadcastHub
    private var lanCancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(dataSyncManager: DataSyncManager, timerServer: AuthoritativeTimerServer) {
        self.port = 8080
        
        // Use the provided DataSyncManager and timerServer instead of creating new ones
        self.dataSyncManager = dataSyncManager
        self.timerServer = timerServer
        self.networkUtilities = NetworkUtilities()
        self.offlineFileServer = OfflineFileServer()
        self.authManager = AuthenticationManager(dataSyncManager: dataSyncManager)

        let broadcastHub = LANBroadcastHub()
        broadcastHub.dataSyncManager = dataSyncManager
        broadcastHub.timerServer = timerServer
        dataSyncManager.broadcastHub = broadcastHub
        self.broadcastHub = broadcastHub
        
        // Create a temporary HTTPHandler for ConnectionManager initialization
        let tempHTTPHandler = HTTPHandler(dataSyncManager: dataSyncManager, offlineFileServer: offlineFileServer, networkUtilities: networkUtilities, connectionManager: nil, authManager: authManager, timerServer: timerServer)
        self.connectionManager = ConnectionManager(httpHandler: tempHTTPHandler, broadcastHub: broadcastHub)
        
        // Now create the real HTTPHandler with the connection manager
        self.httpHandler = HTTPHandler(dataSyncManager: dataSyncManager, offlineFileServer: offlineFileServer, networkUtilities: networkUtilities, connectionManager: connectionManager, authManager: authManager, timerServer: timerServer)
        self.connectionManager.setHTTPHandler(self.httpHandler)
        
        #if DEBUG
        // Sample data for development only. Release builds never inject
        // fake cues into a real show.
        self.dataSyncManager.createTestDataIfNeeded()
        #endif
        
        // Initialize published properties safely for initialization
        initializePublishedProperties()
        
        // Set up bindings to connection manager
        setupBindings()
        setupLANObservers()
        
        #if DEBUG
        // Development-only LAN account with a known password. Never create
        // it in Release: anyone on the venue network could log in and edit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.authManager.createTestUserIfNeeded()
        }
        #endif
    }
    
    // MARK: - Server Management
    
    func start(port: UInt16) {
        guard !Self.isListening, listener == nil else { return }
        Self.isListening = true

        self.port = port
        self._serverStartTime = Date()

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        // TCP options live on the *transport* protocol. (This used to cast
        // internetProtocol, which is the IP layer, so keepalive was never
        // enabled and dead viewers were never detected.) A viewer that
        // vanishes (iPad asleep, Wi-Fi drop) is now dropped after ~25 s.
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 10
            tcpOptions.keepaliveInterval = 5
            tcpOptions.keepaliveCount = 3
            tcpOptions.connectionTimeout = 30
            tcpOptions.noDelay = true
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

            // Announce on the local network so the iPhone remote can find this Mac
            // without typing an address (Bonjour service "_cuetocue._tcp").
            let macName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            listener?.service = NWListener.Service(name: macName, type: "_cuetocue._tcp")

            listener?.start(queue: .global(qos: .userInitiated))

            connectionManager.startConnectionCleanup()
            connectionManager.startConnectionMonitoring()
            updatePublishedProperties()
        } catch {
            Self.isListening = false
            DispatchQueue.main.async { [weak self] in
                self?.serverStatus = (isRunning: false, port: port)
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        Self.isListening = false
        LANLogState.hasLoggedServerReady = false
        LANLogState.lastLoggedViewerCount = -1
        
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
            serverStatus = (isRunning: true, port: port)
            localIPAddress = getLocalIPAddress() ?? "Unknown"
            guard !LANLogState.hasLoggedServerReady else { break }
            LANLogState.hasLoggedServerReady = true
            print("✅ LAN server ready on port \(port) — http://\(localIPAddress):\(port)")
        case .failed(let error):
            Self.isListening = false
            serverStatus = (isRunning: false, port: port)
            print("❌ LAN server failed: \(error)")
        case .cancelled:
            serverStatus = (isRunning: false, port: port)
            print("🛑 LAN server stopped")
        case .waiting(let error):
            print("⏳ LAN server waiting: \(error)")
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

    private func setupLANObservers() {
        dataSyncManager.$selectedCueIndex
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dataSyncManager.bumpShowVersion()
                self?.broadcastHub.broadcastShowStateIfNeeded()
            }
            .store(in: &lanCancellables)

        dataSyncManager.$selectedCueStackIndex
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dataSyncManager.bumpShowVersion()
                self?.broadcastHub.broadcastShowStateIfNeeded()
            }
            .store(in: &lanCancellables)

        timerServer.$countdownTime
            .combineLatest(timerServer.$countdownRunning, timerServer.$countUpTime, timerServer.$countUpRunning)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.broadcastHub.broadcastTimerStateIfNeeded()
            }
            .store(in: &lanCancellables)

        // Phase 4: Mac app edits → debounced LAN snapshot
        dataSyncManager.$cueStacks
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dataSyncManager.publishLANSnapshotFromMacIfNeeded()
            }
            .store(in: &lanCancellables)

        dataSyncManager.$countdownPlaylist
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dataSyncManager.publishLANSnapshotFromMacIfNeeded()
            }
            .store(in: &lanCancellables)

        dataSyncManager.$highlightColors
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.dataSyncManager.publishLANSnapshotFromMacIfNeeded()
            }
            .store(in: &lanCancellables)
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