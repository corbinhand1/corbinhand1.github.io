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
    case badRequest = 400
    case unauthorized = 401
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case internalServerError = 500
    
    var description: String {
        switch self {
        case .ok: return "OK"
        case .badRequest: return "Bad Request"
        case .unauthorized: return "Unauthorized"
        case .forbidden: return "Forbidden"
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
        guard let headerTerminator = data.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            return nil
        }

        let headerData = data.subdata(in: 0..<headerTerminator.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let requestComponents = requestLine.components(separatedBy: " ")
        guard requestComponents.count >= 2 else { return nil }

        guard let method = HTTPMethod(rawValue: requestComponents[0]) else { return nil }
        let path = requestComponents[1].components(separatedBy: "?").first ?? requestComponents[1]

        var headers: [String: String] = [:]
        var contentLength = 0

        for line in lines.dropFirst() {
            if line.isEmpty { break }

            if line.contains(": ") {
                let headerComponents = line.components(separatedBy: ": ")
                if headerComponents.count >= 2 {
                    let key = headerComponents[0].lowercased()
                    let value = headerComponents[1...].joined(separator: ": ")
                    headers[key] = value
                    if key == "content-length" {
                        contentLength = Int(value.trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }
            }
        }

        let bodyStart = headerTerminator.upperBound
        let expectedMessageLength = bodyStart + contentLength
        guard data.count >= expectedMessageLength else { return nil }

        var body: Data?
        if contentLength > 0 {
            body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        }

        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    /// Removes and returns the first complete HTTP message from `buffer`, if present.
    static func extractNextCompleteMessage(from buffer: inout Data) -> Data? {
        guard let headerTerminator = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            return nil
        }

        let headerData = buffer.subdata(in: 0..<headerTerminator.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        var contentLength = 0
        for line in headerString.components(separatedBy: "\r\n").dropFirst() {
            if line.isEmpty { break }
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count)
                    .trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
                break
            }
        }

        let messageLength = headerTerminator.upperBound + contentLength
        guard buffer.count >= messageLength else { return nil }

        let message = buffer.subdata(in: 0..<messageLength)
        buffer.removeSubrange(0..<messageLength)
        return message
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
