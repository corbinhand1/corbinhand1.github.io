//
//  HTTPHandler.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/31/24.
//

import Foundation
import Network
import SwiftUI

class HTTPHandler {
    
    // MARK: - Dependencies
    private let dataSyncManager: DataSyncManager
    private let offlineFileServer: OfflineFileServer
    private let networkUtilities: NetworkUtilities
    private let connectionManager: ConnectionManager?
    
    init(dataSyncManager: DataSyncManager, offlineFileServer: OfflineFileServer, networkUtilities: NetworkUtilities, connectionManager: ConnectionManager?) {
        self.dataSyncManager = dataSyncManager
        self.offlineFileServer = offlineFileServer
        self.networkUtilities = networkUtilities
        self.connectionManager = connectionManager
    }
    
    // MARK: - Request Processing
    
    func processRequest(_ data: Data, on connection: NWConnection) -> HTTPResponse {
        guard let request = HTTPRequest(from: data) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: ["Content-Type": "text/plain"],
                body: "500 Internal Server Error".data(using: .utf8) ?? Data()
            )
        }
        
        // Route the request
        return routeRequest(request)
    }
    
    // MARK: - Request Routing
    
    private func routeRequest(_ request: HTTPRequest) -> HTTPResponse {
        switch (request.method, request.path) {
        case (.get, "/"):
            return serveHTML()
        case (.get, "/cues"):
            return serveJSON()
        case (.get, "/offline.html"):
            return offlineFileServer.serveOfflineHTML()
        case (.get, "/offline-service-worker.js"):
            return offlineFileServer.serveOfflineServiceWorker()
        case (.get, "/offline-data-manager.js"):
            return offlineFileServer.serveOfflineDataManager()
        case (.get, "/offline-state-manager.js"):
            return offlineFileServer.serveOfflineStateManager()
        case (.get, "/offline-styles.css"):
            return offlineFileServer.serveOfflineStyles()
        case (.get, "/offline-integration.js"):
            return offlineFileServer.serveOfflineIntegration()
        case (.get, "/manifest.json"):
            return offlineFileServer.serveManifest()
        case (.get, "/test-offline.html"):
            return offlineFileServer.serveTestOfflineHTML()
        case (.get, "/digital-7-mono.ttf"):
            return offlineFileServer.serveDigital7MonoFont()
        case (.get, "/offline-status"):
            return serveOfflineStatus()
        case (.get, "/health"):
            return offlineFileServer.serveHealthCheck()
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
    
    // MARK: - Response Generation
    
    private func serveHTML() -> HTTPResponse {
        let htmlData = CompleteHTML.content.data(using: .utf8) ?? Data()
        return HTTPResponse(
            status: .ok,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: htmlData
        )
    }
    
    private func serveJSON() -> HTTPResponse {
        let jsonData = dataSyncManager.generateJSONResponse()
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
    
    private func serveOfflineStatus() -> HTTPResponse {
        // Get connection stats from connection manager
        let activeConnections = connectionManager?.getConnectionStats().active ?? 0
        let maxConnections = connectionManager?.getConnectionStats().max ?? 100
        
        return offlineFileServer.serveOfflineStatus(
            cueStacksCount: dataSyncManager.cueStacks.count,
            activeConnections: activeConnections,
            maxConnections: maxConnections
        )
    }
    
    // MARK: - Response Sending
    
    func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
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
    
    func sendErrorResponse(_ status: HTTPStatus, on connection: NWConnection) {
        let response = HTTPResponse(
            status: status,
            headers: ["Content-Type": "text/plain"],
            body: "\(status.rawValue) \(status.description)".data(using: .utf8) ?? Data()
        )
        sendResponse(response, on: connection)
    }
}
