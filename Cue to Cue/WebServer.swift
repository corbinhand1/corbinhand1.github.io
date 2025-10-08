//
//  WebServer.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/31/24.
//

import Foundation
import Network
import Darwin 

class WebServer {
    private var listener: NWListener?
    private var port: UInt16
    private var activeConnections: [UUID: NWConnection] = [:]
    private var cueStacks: [CueStack] = []
    private var selectedCueStackIndex: Int = 0
    private var activeCueIndex: Int = -1
    private var selectedCueIndex: Int = -1
    
    // Clock-related properties
    private var currentTime: Date = Date()
    private var countdownTime: Int = 0
    private var countUpTime: Int = 0
    private var countdownRunning: Bool = false
    private var countUpRunning: Bool = false
    
    // Highlight colors for web client
    private var highlightColors: [HighlightColorSetting] = []
    
    // Serial queue for synchronizing access to shared resources
    private let connectionQueue = DispatchQueue(label: "WebServer.connectionQueue")
    
    init() {
        self.port = 8080 // Default port
    }
    
    func start(port: UInt16) {
        self.port = port
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("Server ready on port \(port)")
                case .failed(let error):
                    print("Server failure: \(error)")
                default:
                    break
                }
            }
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: .global())
        } catch {
            print("Failed to create listener: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        connectionQueue.async { [weak self] in
            for (_, connection) in self?.activeConnections ?? [:] {
                connection.cancel()
            }
            self?.activeConnections.removeAll()
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        let id = UUID()
        connectionQueue.async { [weak self] in
            self?.activeConnections[id] = connection
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveRequest(on: connection, id: id)
            case .failed(let error):
                print("Connection failed: \(error)")
                self?.cleanupConnection(id)
            case .cancelled:
                self?.cleanupConnection(id)
            default:
                break
            }
        }
        connection.start(queue: .global())
    }
    
    private func receiveRequest(on connection: NWConnection, id: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, let request = String(data: data, encoding: .utf8) {
                self.routeRequest(request, on: connection)
            }
            
            if error != nil || isComplete {
                self.cleanupConnection(id)
            } else {
                self.receiveRequest(on: connection, id: id)
            }
        }
    }
    
    private func routeRequest(_ request: String, on connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            sendResponse("400 Bad Request".data(using: .utf8)!, for: "text/plain", on: connection)
            return
        }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else {
            sendResponse("400 Bad Request".data(using: .utf8)!, for: "text/plain", on: connection)
            return
        }
        
        let method = components[0]
        let path = components[1]
        
        // Add CORS headers for all responses
        let corsHeaders = "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n"
        
        switch (method, path) {
        case ("GET", "/"), ("GET", "/index.html"):
            sendResponseWithCORS(CompleteHTML.content.data(using: .utf8)!, for: "text/html", on: connection, corsHeaders: corsHeaders)
            
        case ("GET", "/cues"):
            let jsonData = connectionQueue.sync { generateJsonResponse() }
            sendResponseWithCORS(jsonData, for: "application/json", on: connection, corsHeaders: corsHeaders)
            
        case ("GET", "/offline.html"):
            sendOfflineFile("offline.html", on: connection, corsHeaders: corsHeaders)
        case ("GET", "/test-offline.html"):
            sendOfflineFile("test-offline.html", on: connection, corsHeaders: corsHeaders)
            
        case ("GET", "/offline-service-worker.js"):
            sendOfflineFile("offline-service-worker.js", on: connection, corsHeaders: corsHeaders)
            
        case ("GET", "/offline-data-manager.js"):
            sendOfflineFile("offline-data-manager.js", on: connection, corsHeaders: corsHeaders)
            
        case ("GET", "/offline-state-manager.js"):
            sendOfflineFile("offline-state-manager.js", on: connection, corsHeaders: corsHeaders)
            
        case ("GET", "/offline-integration.js"):
            sendOfflineFile("offline-integration.js", on: connection, corsHeaders: corsHeaders)
            
        case ("GET", "/offline-styles.css"):
            sendOfflineFile("offline-styles.css", on: connection, corsHeaders: corsHeaders)
            
        case ("GET", "/manifest.json"):
            sendOfflineFile("manifest.json", on: connection, corsHeaders: corsHeaders)
            
        case ("GET", "/health"):
            let healthData = ["status": "ok", "timestamp": Date().timeIntervalSince1970] as [String : Any]
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: healthData)
                sendResponseWithCORS(jsonData, for: "application/json", on: connection, corsHeaders: corsHeaders)
            } catch {
                sendResponseWithCORS("{\"status\":\"error\"}".data(using: .utf8)!, for: "application/json", on: connection, corsHeaders: corsHeaders)
            }
            
        case ("OPTIONS", _):
            // Handle CORS preflight requests
            let response = "HTTP/1.1 200 OK\r\n\(corsHeaders)Content-Length: 0\r\nConnection: close\r\n\r\n"
            if let responseData = response.data(using: .utf8) {
                connection.send(content: responseData, completion: .contentProcessed { _ in })
            }
            
        default:
            sendResponseWithCORS("404 Not Found".data(using: .utf8)!, for: "text/plain", on: connection, corsHeaders: corsHeaders)
        }
    }
    
    private func sendOfflineFile(_ filename: String, on connection: NWConnection, corsHeaders: String) {
        guard let filePath = Bundle.main.path(forResource: filename, ofType: nil) else {
            sendResponseWithCORS("404 File Not Found".data(using: .utf8)!, for: "text/plain", on: connection, corsHeaders: corsHeaders)
            return
        }
        
        do {
            let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let contentType = getContentType(for: filename)
            sendResponseWithCORS(fileData, for: contentType, on: connection, corsHeaders: corsHeaders)
        } catch {
            sendResponseWithCORS("500 Internal Server Error".data(using: .utf8)!, for: "text/plain", on: connection, corsHeaders: corsHeaders)
        }
    }
    
    private func getContentType(for filename: String) -> String {
        let pathExtension = (filename as NSString).pathExtension.lowercased()
        
        switch pathExtension {
        case "html":
            return "text/html"
        case "js":
            return "application/javascript"
        case "css":
            return "text/css"
        case "json":
            return "application/json"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "svg":
            return "image/svg+xml"
        case "ico":
            return "image/x-icon"
        case "woff":
            return "font/woff"
        case "woff2":
            return "font/woff2"
        case "ttf":
            return "font/ttf"
        case "otf":
            return "font/otf"
        default:
            return "application/octet-stream"
        }
    }
    
    private func sendResponseWithCORS(_ data: Data, for contentType: String, on connection: NWConnection, corsHeaders: String) {
        let response = "HTTP/1.1 200 OK\r\n\(corsHeaders)Content-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        guard let responseHeader = response.data(using: .utf8) else {
            print("Failed to encode response header")
            return
        }
        let responseData = responseHeader + data
        
        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("Error sending response: \(error)")
            }
            // Cleanup the connection after sending the response
            self?.connectionQueue.async {
                if let id = self?.activeConnections.first(where: { $0.value === connection })?.key {
                    self?.cleanupConnection(id)
                }
            }
        })
    }
    
    private func sendResponse(_ data: Data, for contentType: String, on connection: NWConnection) {
        let response = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        guard let responseHeader = response.data(using: .utf8) else {
            print("Failed to encode response header")
            return
        }
        let responseData = responseHeader + data
        
        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                print("Error sending response: \(error)")
            }
            // Cleanup the connection after sending the response
            self?.connectionQueue.async {
                if let id = self?.activeConnections.first(where: { $0.value === connection })?.key {
                    self?.cleanupConnection(id)
                }
            }
        })
    }
    
    private func cleanupConnection(_ id: UUID) {
        connectionQueue.async { [weak self] in
            if let connection = self?.activeConnections.removeValue(forKey: id) {
                connection.cancel()
                
            }
        }
    }
    
    func updateCues(cueStacks: [CueStack], selectedCueStackIndex: Int, activeCueIndex: Int, selectedCueIndex: Int) {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            self.cueStacks = cueStacks
            self.selectedCueStackIndex = selectedCueStackIndex
            self.activeCueIndex = activeCueIndex
            self.selectedCueIndex = selectedCueIndex
            
            // Send updates to all connected clients
            let updatedData = self.generateJsonResponse()
            for (_, connection) in self.activeConnections {
                self.sendResponse(updatedData, for: "application/json", on: connection)
            }
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
            
            // Note: Web viewer gets updates through polling /cues endpoint every 100ms
            // No need to push updates since HTTP connections are not persistent
        }
    }
    
    func updateHighlightColors(_ highlightColors: [HighlightColorSetting]) {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            self.highlightColors = highlightColors
        }
    }
    
    private func formatTimeForWeb(_ seconds: Int) -> String {
        let isNegative = seconds < 0
        let absSeconds = abs(seconds)
        let hours = absSeconds / 3600
        let minutes = (absSeconds % 3600) / 60
        let remainingSeconds = absSeconds % 60
        let timeFormat = String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        return isNegative ? "-\(timeFormat)" : timeFormat
    }
    
    private func sendToAllClients(data: [String: Any]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                print("Failed to convert JSON data to String")
                return
            }
            let responseData = jsonString.data(using: .utf8) ?? Data()
            
            for (_, connection) in activeConnections {
                sendResponse(responseData, for: "application/json", on: connection)
            }
        } catch {
            print("Error serializing JSON: \(error)")
        }
    }
    
    private func generateJsonResponse() -> Data {
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
                        "isStruckThrough": cue.isStruckThrough
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
                ]}
            ]
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonObject)
            return data
        } catch {
            print("Error generating JSON response: \(error)")
            return Data()
        }
    }
    
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
}
