import Foundation
import CryptoKit
import Security

/// How safe the link to the Mac is, judged from its address.
enum ConnectionSecurity: Equatable {
    case encrypted          // https
    case tailscale          // plain http, but inside Tailscale's encrypted WireGuard tunnel
    case localNetwork       // plain http on your own network: readable by others on that Wi-Fi
    case unsafe             // plain http to a public address: never send a password here

    var title: String {
        switch self {
        case .encrypted: return "Encrypted (https)"
        case .tailscale: return "Encrypted by Tailscale"
        case .localNetwork: return "Local network (not encrypted)"
        case .unsafe: return "Not encrypted over the internet"
        }
    }

    var symbol: String {
        switch self {
        case .encrypted, .tailscale: return "lock.fill"
        case .localNetwork: return "lock.open.fill"
        case .unsafe: return "exclamationmark.triangle.fill"
        }
    }

    static func classify(_ url: URL) -> ConnectionSecurity {
        if url.scheme == "https" { return .encrypted }
        let host = (url.host ?? "").lowercased()
        if host.hasSuffix(".ts.net") { return .tailscale }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            switch (parts[0], parts[1]) {
            case (100, 64...127): return .tailscale                      // Tailscale CGNAT range
            case (10, _), (192, 168), (127, _), (169, 254): return .localNetwork
            case (172, 16...31): return .localNetwork
            default: return .unsafe
            }
        }
        if host == "localhost" || host.hasSuffix(".local") || !host.contains(".") || host == "::1" { return .localNetwork }
        return .unsafe
    }
}

enum Proof {
    /// Asks the server to prove it issued our session token (HMAC over a fresh random nonce),
    /// without ever sending the token. A look-alike server on the network can't answer correctly.
    static func verify(baseURL: URL, token: String) async -> Bool {
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return false }
        let nonce = bytes.map { String(format: "%02x", $0) }.joined()
        let kid = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        guard let url = URL(string: baseURL.absoluteString + "/auth/proof") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["kid": kid, "nonce": nonce])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let got = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["proof"] as? String else { return false }
        let key = SymmetricKey(data: Data(token.utf8))
        let want = Data(HMAC<SHA256>.authenticationCode(for: Data(nonce.utf8), using: key))
        guard let gotData = Data(hex: got) else { return false }
        return want.count == gotData.count && zip(want, gotData).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0   // constant time
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            data.append(b); i = j
        }
        self = data
    }
}
