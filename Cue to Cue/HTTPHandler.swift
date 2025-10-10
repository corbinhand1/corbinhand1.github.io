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
    private let authManager: AuthenticationManager
    
    init(dataSyncManager: DataSyncManager, offlineFileServer: OfflineFileServer, networkUtilities: NetworkUtilities, connectionManager: ConnectionManager?, authManager: AuthenticationManager) {
        self.dataSyncManager = dataSyncManager
        self.offlineFileServer = offlineFileServer
        self.networkUtilities = networkUtilities
        self.connectionManager = connectionManager
        self.authManager = authManager
    }
    
    // MARK: - Request Processing
    
    private func createCORSHeaders(_ additionalHeaders: [String: String] = [:]) -> [String: String] {
        var headers = additionalHeaders
        headers["Access-Control-Allow-Origin"] = "*"
        headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
        headers["Access-Control-Max-Age"] = "86400"
        return headers
    }
    
    func processRequest(_ data: Data, on connection: NWConnection) -> HTTPResponse {
        guard let request = HTTPRequest(from: data) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "text/plain"]),
                body: "500 Internal Server Error".data(using: .utf8) ?? Data()
            )
        }
        
        // Handle CORS preflight requests
        if request.method == .options {
            return HTTPResponse(
                status: .ok,
                headers: createCORSHeaders(),
                body: Data()
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
        case (.get, "/health"), (.head, "/health"):
            return offlineFileServer.serveHealthCheck()
        // Authentication endpoints
        case (.post, "/auth/login"):
            return handleLogin(request)
        case (.post, "/auth/logout"):
            return handleLogout(request)
        case (.get, "/auth/me"):
            return handleGetCurrentUser(request)
        case (.get, "/auth/permissions"):
            return handleGetPermissions(request)
        case (.post, "/auth/register"):
            return handleRegister(request)
        // Protected edit endpoints
        case (.put, let path) where path.hasPrefix("/cues/"):
            return handleEditCue(request)
        case (.post, "/cues"):
            return handleAddCue(request)
        case (.delete, let path) where path.hasPrefix("/cues/"):
            return handleDeleteCue(request)
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
        
        // Check if JSON generation failed (empty data indicates error)
        if jsonData.isEmpty {
            // Return a simple error response without logging spam
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json; charset=utf-8"]),
                body: createErrorJSON(message: "No data available")
            )
        }
        
        return HTTPResponse(
            status: .ok,
            headers: createCORSHeaders(["Content-Type": "application/json; charset=utf-8"]),
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
        print("🔍 sendResponse() called with status: \(response.status.rawValue)")
        let responseData = response.serialize()
        print("🔍 Response data size: \(responseData.count) bytes")
        
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
    
    // MARK: - Authentication Handlers
    
    private func handleLogin(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body,
              let loginRequest = try? JSONDecoder().decode(LoginRequest.self, from: body) else {
            return HTTPResponse(
                status: .badRequest,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Invalid request body")
            )
        }
        
        let result = authManager.login(username: loginRequest.username, password: loginRequest.password)
        
        switch result {
        case .success(let loginResponse):
            let responseData = try? JSONEncoder().encode(loginResponse)
            return HTTPResponse(
                status: .ok,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: responseData ?? Data()
            )
        case .failure(let error):
            let errorResponse = LoginResponse(success: false, message: error.localizedDescription)
            let responseData = try? JSONEncoder().encode(errorResponse)
            return HTTPResponse(
                status: .unauthorized,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: responseData ?? Data()
            )
        }
    }
    
    private func handleLogout(_ request: HTTPRequest) -> HTTPResponse {
        // Extract token from Authorization header
        if let authHeader = request.headers["authorization"],
           authHeader.hasPrefix("Bearer ") {
            let token = String(authHeader.dropFirst(7)) // Remove "Bearer " prefix
            // Invalidate token (optional - tokens expire naturally)
            print("User logged out with token: \(token)")
        }
        
        authManager.logout()
        
        let response: [String: Any] = ["success": true, "message": "Logged out successfully"]
        let responseData = try? JSONSerialization.data(withJSONObject: response)
        
        return HTTPResponse(
            status: .ok,
            headers: createCORSHeaders(["Content-Type": "application/json"]),
            body: responseData ?? Data()
        )
    }
    
    private func handleGetCurrentUser(_ request: HTTPRequest) -> HTTPResponse {
        print("🔍 handleGetCurrentUser() called")
        guard let user = getCurrentUser(from: request) else {
            print("❌ No authenticated user found - returning 401")
            return HTTPResponse(
                status: .unauthorized,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Not authenticated")
            )
        }
        
        print("🔍 Found user: \(user.username)")
        let userResponse = UserResponse(user: user, permissions: authManager.getUserPermissions(for: user.id, cueStacks: dataSyncManager.cueStacks))
        
        do {
            let responseData = try JSONEncoder().encode(userResponse)
            print("✅ UserResponse encoded successfully, size: \(responseData.count) bytes")
            return HTTPResponse(
                status: .ok,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: responseData
            )
        } catch {
            print("❌ Failed to encode UserResponse: \(error)")
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Failed to encode user data")
            )
        }
    }
    
    private func handleGetPermissions(_ request: HTTPRequest) -> HTTPResponse {
        guard let user = getCurrentUser(from: request) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Not authenticated")
            )
        }
        
        let permissions = authManager.getUserPermissions(for: user.id, cueStacks: dataSyncManager.cueStacks)
        let responseData = try? JSONEncoder().encode(permissions)
        
        return HTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: responseData ?? Data()
        )
    }
    
    private func handleRegister(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body,
              let registerRequest = try? JSONDecoder().decode(CreateUserRequest.self, from: body) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Invalid request body")
            )
        }
        
        // Check if current user is admin
        guard let currentUser = getCurrentUser(from: request),
              currentUser.isAdmin else {
            return HTTPResponse(
                status: .forbidden,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Admin access required")
            )
        }
        
        let result = authManager.createUser(
            username: registerRequest.username,
            password: registerRequest.password,
            isAdmin: registerRequest.isAdmin,
            permissions: registerRequest.permissions
        )
        
        switch result {
        case .success(let user):
            let userResponse = UserResponse(user: user, permissions: authManager.getUserPermissions(for: user.id, cueStacks: dataSyncManager.cueStacks))
            let responseData = try? JSONEncoder().encode(userResponse)
            return HTTPResponse(
                status: .ok,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: responseData ?? Data()
            )
        case .failure(let error):
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: error.localizedDescription)
            )
        }
    }
    
    // MARK: - Authentication Helpers
    
    private func getCurrentUser(from request: HTTPRequest) -> User? {
        guard let authHeader = request.headers["authorization"],
              authHeader.hasPrefix("Bearer ") else {
            return nil
        }
        
        let token = String(authHeader.dropFirst(7)) // Remove "Bearer " prefix
        
        switch authManager.validateToken(token) {
        case .success(let user):
            return user
        case .failure(let error):
            print("❌ Token validation failed: \(error)")
            return nil
        }
    }
    
    private func createErrorJSON(message: String) -> Data {
        let errorDict = ["error": message]
        return (try? JSONSerialization.data(withJSONObject: errorDict)) ?? Data()
    }
    
    // MARK: - Protected Edit Endpoints
    
    private func handleEditCue(_ request: HTTPRequest) -> HTTPResponse {
        // Require authentication
        guard let user = getCurrentUser(from: request) else {
            return HTTPResponse(
                status: .unauthorized,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Authentication required")
            )
        }
        
        guard let body = request.body else {
            print("❌ No request body")
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "No request body")
            )
        }
        
        print("🔍 Request body size: \(body.count) bytes")
        if let bodyString = String(data: body, encoding: .utf8) {
            print("🔍 Request body content: \(bodyString)")
        }
        
        guard let editRequest = try? JSONDecoder().decode(EditCueRequest.self, from: body) else {
            print("❌ Failed to decode EditCueRequest")
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Invalid request body")
            )
        }
        
        print("🔍 Decoded request: cueId=\(editRequest.cueId), columnIndex=\(editRequest.columnIndex), newValue='\(editRequest.newValue)'")
        
        // Find the cue and its cue stack
        guard let (cueStack, _) = dataSyncManager.findCue(by: editRequest.cueId) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Cue not found")
            )
        }
        
        // Check permission for this column
        let canEdit = authManager.canUserEditColumn(user.id, cueStackId: cueStack.id, columnIndex: editRequest.columnIndex)
        
        guard canEdit else {
            return HTTPResponse(
                status: .forbidden,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Permission denied for this column")
            )
        }
        
        // Update the cue value
        let updateSuccess = dataSyncManager.updateCueValue(cueId: editRequest.cueId, columnIndex: editRequest.columnIndex, newValue: editRequest.newValue)
        
        guard updateSuccess else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Failed to update cue")
            )
        }
        
        print("✅ Saved: \(editRequest.newValue) to column \(editRequest.columnIndex)")
        
        // Return success response
        let response: [String: Any] = ["success": true, "message": "Cue updated successfully"]
        let responseData = try? JSONSerialization.data(withJSONObject: response)
        
        return HTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: responseData ?? Data()
        )
    }
    
    private func handleAddCue(_ request: HTTPRequest) -> HTTPResponse {
        // Require authentication
        guard let user = getCurrentUser(from: request) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Authentication required")
            )
        }
        
        guard let body = request.body,
              let addRequest = try? JSONDecoder().decode(AddCueRequest.self, from: body) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Invalid request body")
            )
        }
        
        // Find the cue stack
        guard dataSyncManager.cueStacks.contains(where: { $0.id == addRequest.cueStackId }) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Cue stack not found")
            )
        }
        
        // Check if user has any permissions for this cue stack
        let userPermissions = authManager.permissions.filter { $0.userId == user.id && $0.cueStackId == addRequest.cueStackId }
        guard !userPermissions.isEmpty || user.isAdmin else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Permission denied for this cue stack")
            )
        }
        
        // Create new cue
        guard let newCueId = dataSyncManager.addCue(to: addRequest.cueStackId, values: addRequest.values, timerValue: addRequest.timerValue) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Failed to add cue")
            )
        }
        
        // Return success response
        let response: [String: Any] = ["success": true, "message": "Cue added successfully", "cueId": newCueId.uuidString]
        let responseData = try? JSONSerialization.data(withJSONObject: response)
        
        return HTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: responseData ?? Data()
        )
    }
    
    private func handleDeleteCue(_ request: HTTPRequest) -> HTTPResponse {
        // Require authentication
        guard let user = getCurrentUser(from: request) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Authentication required")
            )
        }
        
        // Extract cue ID from path
        let pathComponents = request.path.components(separatedBy: "/")
        guard pathComponents.count >= 3,
              let cueIdString = pathComponents.last,
              let cueId = UUID(uuidString: cueIdString) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Invalid cue ID")
            )
        }
        
        // Find the cue and its cue stack
        guard let (cueStack, _) = dataSyncManager.findCue(by: cueId) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Cue not found")
            )
        }
        
        // Check if user has any permissions for this cue stack
        let userPermissions = authManager.permissions.filter { $0.userId == user.id && $0.cueStackId == cueStack.id }
        guard !userPermissions.isEmpty || user.isAdmin else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Permission denied for this cue stack")
            )
        }
        
        // Delete the cue
        guard dataSyncManager.deleteCue(cueId: cueId) else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Failed to delete cue")
            )
        }
        
        // Return success response
        let response: [String: Any] = ["success": true, "message": "Cue deleted successfully"]
        let responseData = try? JSONSerialization.data(withJSONObject: response)
        
        return HTTPResponse(
            status: .ok,
            headers: ["Content-Type": "application/json"],
            body: responseData ?? Data()
        )
    }
}
