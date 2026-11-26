import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int, String)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .badURL: return "That address doesn't look right."
        case .http(401, _): return "Session expired. Sign in again."
        case .http(403, let m): return m.isEmpty ? "You don't have permission to edit that." : m
        case .http(let code, let m): return m.isEmpty ? "Server returned \(code)." : m
        case .notSignedIn: return "Not signed in."
        }
    }
}

/// Talks to the Mac app's built-in server. `baseURL` is whatever reaches it:
/// a LAN address, a Tailscale name, or a tunnel hostname.
struct API {
    var baseURL: URL
    var token: String?

    /// Accepts "192.168.1.5:8080", "mac.tailnet.ts.net:8080", "https://x.trycloudflare.com".
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, auth: Bool = false) throws -> URLRequest {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw APIError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if auth {
            guard let token else { throw APIError.notSignedIn }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    @discardableResult
    private func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ServerError.self, from: data))?.error
                ?? (try? JSONDecoder().decode(LoginResult.self, from: data))?.message ?? ""
            throw APIError.http(http.statusCode, msg)
        }
        return data
    }

    func login(username: String, password: String) async throws -> String {
        let data = try await send(request("/auth/login", method: "POST",
                                          body: ["username": username, "password": password]))
        let result = try JSONDecoder().decode(LoginResult.self, from: data)
        guard result.success, let token = result.token else {
            throw APIError.http(401, result.message ?? "Login failed.")
        }
        return token
    }

    /// The stack the Mac is currently showing viewers (includes the stack list).
    func currentSheet() async throws -> Sheet {
        try JSONDecoder().decode(Sheet.self, from: await send(request("/cues")))
    }

    func sheet(stackID: String) async throws -> Sheet {
        let enc = stackID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stackID
        return try JSONDecoder().decode(Sheet.self, from: await send(request("/stack/\(enc)")))
    }

    func edit(cueID: String, column: Int, value: String) async throws {
        try await send(request("/cues/\(cueID)", method: "PUT",
                               body: ["cueId": cueID, "columnIndex": column, "newValue": value], auth: true))
    }

    func addCue(stackID: String, values: [String]) async throws {
        try await send(request("/cues", method: "POST",
                               body: ["cueStackId": stackID, "values": values, "timerValue": ""], auth: true))
    }

    func deleteCue(id: String) async throws {
        try await send(request("/cues/\(id)", method: "DELETE", auth: true))
    }

    /// ws:// or wss:// URL for live change notifications.
    var webSocketURL: URL? {
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        c?.scheme = (baseURL.scheme == "https") ? "wss" : "ws"
        c?.path = "/ws"
        return c?.url
    }
}
