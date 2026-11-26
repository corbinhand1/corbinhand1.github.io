import Foundation
import Network

struct FoundMac: Identifiable, Equatable {
    let name: String
    var address: String?          // "192.168.1.20:8080" once resolved
    var id: String { name }
}

/// Finds Macs running Cue to Cue on the local network (Bonjour "_cuetocue._tcp").
@MainActor
final class MacFinder: ObservableObject {
    @Published var found: [FoundMac] = []
    @Published var searching = false
    private var browser: NWBrowser?

    func start() {
        stop()
        searching = true
        let b = NWBrowser(for: .bonjour(type: "_cuetocue._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in await self?.update(results) }
        }
        b.start(queue: .main)
        browser = b
        // Stop spinning after a while; results still arrive if a Mac shows up later.
        Task { try? await Task.sleep(nanoseconds: 4_000_000_000); self.searching = false }
    }

    func stop() { browser?.cancel(); browser = nil }

    private func update(_ results: Set<NWBrowser.Result>) async {
        var out: [FoundMac] = []
        for r in results {
            guard case let .service(name, _, _, _) = r.endpoint else { continue }
            out.append(FoundMac(name: name, address: await Self.resolve(r.endpoint)))
        }
        found = out.sorted { $0.name < $1.name }
    }

    /// Turns a Bonjour service into "ip:port" by opening (and immediately closing) a connection.
    nonisolated static func resolve(_ endpoint: NWEndpoint) async -> String? {
        await withCheckedContinuation { cont in
            let params = NWParameters.tcp
            if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
            let conn = NWConnection(to: endpoint, using: params)
            let lock = NSLock()
            var finished = false
            func finish(_ value: String?) {
                lock.lock(); defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                conn.cancel()
                cont.resume(returning: value)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, port)? = conn.currentPath?.remoteEndpoint {
                        let ip = "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"
                        finish("\(ip):\(port.rawValue)")
                    } else { finish(nil) }
                case .failed, .cancelled: finish(nil)
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish(nil) }
        }
    }

    /// One-shot lookup of a specific, previously paired Mac. Used to follow it when its IP changes.
    static func find(named name: String, timeout: TimeInterval = 2.5) async -> FoundMac? {
        await withCheckedContinuation { cont in
            let browser = NWBrowser(for: .bonjour(type: "_cuetocue._tcp", domain: nil), using: .tcp)
            let lock = NSLock()
            var finished = false
            func finish(_ mac: FoundMac?) {
                lock.lock(); defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                browser.cancel()
                cont.resume(returning: mac)
            }
            browser.browseResultsChangedHandler = { results, _ in
                for r in results {
                    if case let .service(n, _, _, _) = r.endpoint, n == name {
                        Task { finish(FoundMac(name: n, address: await resolve(r.endpoint))) }
                        return
                    }
                }
            }
            browser.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}
