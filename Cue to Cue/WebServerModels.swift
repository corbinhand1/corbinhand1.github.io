//
//  WebServerModels.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/31/24.
//

import Foundation
import Network

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
