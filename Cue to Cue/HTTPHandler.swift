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
    private let timerServer: AuthoritativeTimerServer
    
    init(dataSyncManager: DataSyncManager, offlineFileServer: OfflineFileServer, networkUtilities: NetworkUtilities, connectionManager: ConnectionManager?, authManager: AuthenticationManager, timerServer: AuthoritativeTimerServer) {
        self.dataSyncManager = dataSyncManager
        self.offlineFileServer = offlineFileServer
        self.networkUtilities = networkUtilities
        self.connectionManager = connectionManager
        self.authManager = authManager
        self.timerServer = timerServer
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
        case (.get, let path) where path.hasPrefix("/stack/"):
            return serveStackJSON(id: String(path.dropFirst("/stack/".count)))
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
        case (.get, "/timer-state"):
            return serveTimerState()
        case (.get, "/show-state"):
            return serveShowState()
        case (.post, "/timer-command"):
            return handleTimerCommand(request)
        case (.post, "/select-cue-stack"):
            return handleCueStackSelection(request)
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
            if isOfflineStateSyncRequest(request) {
                return acknowledgeOfflineStateSync()
            }
            return handleAddCue(request)
        case (.delete, let path) where path.hasPrefix("/cues/"):
            return handleDeleteCue(request)
        case (.post, "/ops"):
            return handleRemoteOp(request)
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
    
    /// Timer and cue state live on the main thread; HTTP connections arrive on a background queue.
    private func onMainThread<T>(_ work: () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }
    
    private func serveHTML() -> HTTPResponse {
        let htmlData = CompleteHTML.content.data(using: .utf8) ?? Data()
        return HTTPResponse(
            status: .ok,
            // Always fetch the page fresh, so viewers get updates right away.
            headers: ["Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store"],
            body: htmlData
        )
    }
    
    private func serveJSON() -> HTTPResponse {
        let jsonData = onMainThread {
            dataSyncManager.generateJSONResponseForWebClient(timerServer: timerServer)
        }

        if jsonData.isEmpty {
            return HTTPResponse(
                status: .serviceUnavailable,
                headers: createCORSHeaders(["Content-Type": "application/json; charset=utf-8"]),
                body: createErrorJSON(message: "Cue data temporarily unavailable")
            )
        }
        
        return HTTPResponse(
            status: .ok,
            headers: createCORSHeaders(["Content-Type": "application/json; charset=utf-8"]),
            body: jsonData
        )
    }
    
    /// Which cue is live (for viewers polling over HTTP when the WebSocket is down).
    private func serveShowState() -> HTTPResponse {
        let payload = onMainThread { dataSyncManager.buildShowStatePayload() } ?? [:]
        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        return HTTPResponse(
            status: .ok,
            headers: createCORSHeaders(["Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store"]),
            body: body
        )
    }

    /// A viewer browsing another stack (the Mac's live stack comes from /cues and the WebSocket).
    private func serveStackJSON(id: String) -> HTTPResponse {
        let jsonData = onMainThread {
            dataSyncManager.webClientJSON(forStackID: id.removingPercentEncoding ?? id, timerServer: timerServer)
        }
        guard let jsonData else {
            return HTTPResponse(
                status: .notFound,
                headers: createCORSHeaders(["Content-Type": "application/json; charset=utf-8"]),
                body: createErrorJSON(message: "No cue stack with that id")
            )
        }
        return HTTPResponse(
            status: .ok,
            headers: createCORSHeaders(["Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store"]),
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
    
    private func serveTimerState() -> HTTPResponse {
        let timerState = onMainThread {
            timerServer.getTimerState()
        }
        
        do {
            let jsonData = try JSONEncoder().encode(timerState)
            return HTTPResponse(
                status: .ok,
                headers: createCORSHeaders(["Content-Type": "application/json; charset=utf-8"]),
                body: jsonData
            )
        } catch {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json; charset=utf-8"]),
                body: createErrorJSON(message: "Failed to encode timer state")
            )
        }
    }
    
    private func handleTimerCommand(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body else {
            return HTTPResponse(
                status: .badRequest,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "No request body")
            )
        }
        
        do {
            let command = try JSONDecoder().decode(TimerCommand.self, from: body)
            timerServer.executeCommand(command)
            
            let response: [String: Any] = ["success": true, "message": "Timer command executed"]
            let responseData = try JSONSerialization.data(withJSONObject: response)
            
            return HTTPResponse(
                status: .ok,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: responseData
            )
        } catch {
            return HTTPResponse(
                status: .badRequest,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Invalid timer command")
            )
        }
    }
    
    private func handleCueStackSelection(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = request.body else {
            return HTTPResponse(
                status: .badRequest,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "No request body")
            )
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let cueStackIndex = json["cueStackIndex"] as? Int else {
                return HTTPResponse(
                    status: .badRequest,
                    headers: createCORSHeaders(["Content-Type": "application/json"]),
                    body: createErrorJSON(message: "Invalid cue stack index")
                )
            }
            
            // Validate the cue stack index
            let cueStacks = dataSyncManager.cueStacks
            guard cueStackIndex >= 0 && cueStackIndex < cueStacks.count else {
                return HTTPResponse(
                    status: .badRequest,
                    headers: createCORSHeaders(["Content-Type": "application/json"]),
                    body: createErrorJSON(message: "Invalid cue stack index: \(cueStackIndex)")
                )
            }
            
            // IMPORTANT: Do NOT update the global selectedCueStackIndex
            // This would affect the macOS app. Instead, we'll handle web client
            // cue stack selection separately in the JSON response generation.
            
            // Store the web client's selected cue stack index for this session
            // We'll use this in generateJSONResponseForWebClient() method
            dataSyncManager.setWebClientCueStackIndex(cueStackIndex)
            
            let response: [String: Any] = [
                "success": true, 
                "message": "Cue stack selected for web client",
                "selectedIndex": cueStackIndex,
                "cueStackName": cueStacks[cueStackIndex].name
            ]
            let responseData = try JSONSerialization.data(withJSONObject: response)
            
            return HTTPResponse(
                status: .ok,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: responseData
            )
        } catch {
            return HTTPResponse(
                status: .badRequest,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Invalid request format")
            )
        }
    }
    
    // MARK: - Response Sending
    
    func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        let responseData = response.serialize()
        
        connection.send(content: responseData, completion: .contentProcessed { error in
            if let error = error {
                // Only log non-connection errors
                let nsError = error as NSError
                if nsError.domain != "NSPOSIXErrorDomain" || 
                   (nsError.code != 32 && nsError.code != 54 && nsError.code != 57 && nsError.code != 89) {
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
            let _ = String(authHeader.dropFirst(7)) // Remove "Bearer " prefix
            // Invalidate token (optional - tokens expire naturally)
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
        guard let user = getCurrentUser(from: request) else {
            return HTTPResponse(
                status: .unauthorized,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Not authenticated")
            )
        }
        
        let userResponse = UserResponse(user: user, permissions: authManager.getUserPermissions(for: user.id, cueStacks: dataSyncManager.cueStacks))
        
        do {
            let responseData = try JSONEncoder().encode(userResponse)
            return HTTPResponse(
                status: .ok,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: responseData
            )
        } catch {
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
        case .failure(_):
            return nil
        }
    }
    
    private func createErrorJSON(message: String) -> Data {
        let errorDict = ["error": message]
        return (try? JSONSerialization.data(withJSONObject: errorDict)) ?? Data()
    }

    private func isOfflineStateSyncRequest(_ request: HTTPRequest) -> Bool {
        guard let body = request.body,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }
        return json["action"] as? String == "sync"
    }

    private func acknowledgeOfflineStateSync() -> HTTPResponse {
        let response: [String: Any] = [
            "success": true,
            "message": "Offline UI state is stored locally on this device"
        ]
        let responseData = (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
        return HTTPResponse(
            status: .ok,
            headers: createCORSHeaders(["Content-Type": "application/json"]),
            body: responseData
        )
    }
    
    // MARK: - Protected Edit Endpoints

    private enum CueEditOutcome {
        case success
        case notFound
        case forbidden
        case failed
    }

    private func handleEditCue(_ request: HTTPRequest) -> HTTPResponse {
        guard let user = getCurrentUser(from: request) else {
            return HTTPResponse(
                status: .unauthorized,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Authentication required")
            )
        }

        guard let body = request.body else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "No request body")
            )
        }

        guard let editRequest = try? JSONDecoder().decode(EditCueRequest.self, from: body) else {
            print("❌ LAN edit failed: could not decode request body")
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Invalid request body")
            )
        }

        let outcome = onMainThread { () -> CueEditOutcome in
            guard let (cueStack, _) = dataSyncManager.findCue(by: editRequest.cueId) else {
                return .notFound
            }

            guard authManager.canUserEditColumn(
                user.id,
                cueStackId: cueStack.id,
                columnIndex: editRequest.columnIndex
            ) else {
                return .forbidden
            }

            return dataSyncManager.updateCueValueSync(
                cueId: editRequest.cueId,
                columnIndex: editRequest.columnIndex,
                newValue: editRequest.newValue
            ) ? .success : .failed
        }

        switch outcome {
        case .success:
            let response: [String: Any] = ["success": true, "message": "Cue updated successfully"]
            let responseData = try? JSONSerialization.data(withJSONObject: response)
            return HTTPResponse(
                status: .ok,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: responseData ?? Data()
            )
        case .notFound:
            return HTTPResponse(
                status: .notFound,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Cue not found")
            )
        case .forbidden:
            return HTTPResponse(
                status: .forbidden,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Permission denied for this column")
            )
        case .failed:
            print("❌ LAN edit failed: updateCueValueSync returned false for \(editRequest.cueId)")
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Failed to update cue")
            )
        }
    }
    
    private func handleAddCue(_ request: HTTPRequest) -> HTTPResponse {
        // Require authentication
        guard let user = getCurrentUser(from: request) else {
            return HTTPResponse(
                status: .unauthorized,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Authentication required")
            )
        }
        
        guard let body = request.body,
              let addRequest = try? JSONDecoder().decode(AddCueRequest.self, from: body) else {
            return HTTPResponse(
                status: .badRequest,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Invalid request body")
            )
        }
        
        // Find the cue stack
        guard dataSyncManager.cueStacks.contains(where: { $0.id == addRequest.cueStackId }) else {
            return HTTPResponse(
                status: .notFound,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Cue stack not found")
            )
        }
        
        // Check if user has any permissions for this cue stack
        let userPermissions = authManager.permissions.filter { $0.userId == user.id && $0.cueStackId == addRequest.cueStackId }
        guard !userPermissions.isEmpty || user.isAdmin else {
            return HTTPResponse(
                status: .forbidden,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Permission denied for this cue stack")
            )
        }
        
        // Create new cue
        let newCueId = onMainThread {
            dataSyncManager.addCueSync(
                to: addRequest.cueStackId,
                values: addRequest.values,
                timerValue: addRequest.timerValue
            )
        }

        guard let cueId = newCueId else {
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Failed to add cue")
            )
        }
        
        // Return success response
        let response: [String: Any] = ["success": true, "message": "Cue added successfully", "cueId": cueId.uuidString]
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
        
        // Find, authorize, and delete on the main thread.
        let outcome = onMainThread { () -> CueEditOutcome in
            guard let (cueStack, _) = dataSyncManager.findCue(by: cueId) else {
                return .notFound
            }

            let userPermissions = authManager.permissions.filter {
                $0.userId == user.id && $0.cueStackId == cueStack.id
            }
            guard !userPermissions.isEmpty || user.isAdmin else {
                return .forbidden
            }

            return dataSyncManager.deleteCueSync(cueId: cueId) ? .success : .failed
        }

        switch outcome {
        case .success:
            let response: [String: Any] = ["success": true, "message": "Cue deleted successfully"]
            let responseData = try? JSONSerialization.data(withJSONObject: response)
            return HTTPResponse(
                status: .ok,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: responseData ?? Data()
            )
        case .notFound:
            return HTTPResponse(
                status: .notFound,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Cue not found")
            )
        case .forbidden:
            return HTTPResponse(
                status: .forbidden,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Permission denied for this cue stack")
            )
        case .failed:
            return HTTPResponse(
                status: .internalServerError,
                headers: createCORSHeaders(["Content-Type": "application/json"]),
                body: createErrorJSON(message: "Failed to delete cue")
            )
        }
    }

    // MARK: - Structural edit operations (insert, move, strike, timer, delete, columns)

    /// POST /ops with {"op": "...", ...}. Cue ops need any permission on the stack
    /// (like add/delete); column ops need an admin.
    private func handleRemoteOp(_ request: HTTPRequest) -> HTTPResponse {
        func json(_ status: HTTPStatus, _ object: [String: Any]) -> HTTPResponse {
            HTTPResponse(status: status, headers: createCORSHeaders(["Content-Type": "application/json"]),
                         body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        }
        guard let user = getCurrentUser(from: request) else {
            return json(.unauthorized, ["error": "Authentication required"])
        }
        guard let body = request.body,
              let op = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let name = op["op"] as? String else {
            return json(.badRequest, ["error": "Invalid request body"])
        }

        return onMainThread {
            guard let stackID = dataSyncManager.stackIDForRemoteOp(op) else {
                return json(.notFound, ["error": "Cue or cue stack not found"])
            }
            if DataSyncManager.isColumnOp(name) {
                guard user.isAdmin else { return json(.forbidden, ["error": "Only administrators can change columns"]) }
            } else {
                let hasAccess = authManager.permissions.contains { $0.userId == user.id && $0.cueStackId == stackID }
                guard user.isAdmin || hasAccess else {
                    return json(.forbidden, ["error": "Permission denied for this cue stack"])
                }
            }
            switch dataSyncManager.applyRemoteOpSync(op) {
            case .success(let newID):
                var out: [String: Any] = ["success": true]
                if let newID { out["cueId"] = newID.uuidString }
                return json(.ok, out)
            case .failure(let e):
                if case .notFound = e { return json(.notFound, ["error": e.message]) }
                return json(.badRequest, ["error": e.message])
            }
        }
    }
}
