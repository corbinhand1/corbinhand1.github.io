import Foundation

/// Listens to the Mac's /ws feed. We don't parse the payloads: any change
/// message just means "refetch the sheet", which keeps this simple and always
/// consistent with what the Mac holds.
final class LiveSocket {
    private var task: URLSessionWebSocketTask?
    private var stopped = true
    private let onChange: () -> Void
    private let onState: (Bool) -> Void

    init(onChange: @escaping () -> Void, onState: @escaping (Bool) -> Void) {
        self.onChange = onChange
        self.onState = onState
    }

    func start(url: URL) {
        stop()
        stopped = false
        connect(url)
    }

    func stop() {
        stopped = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func connect(_ url: URL) {
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        receive(t, url: url)
        ping(t)
    }

    private func receive(_ t: URLSessionWebSocketTask, url: URL) {
        t.receive { [weak self] result in
            guard let self, !self.stopped, t === self.task else { return }
            switch result {
            case .success(let msg):
                self.onState(true)
                if case .string(let s) = msg, Self.isChange(s) { self.onChange() }
                self.receive(t, url: url)
            case .failure:
                self.onState(false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, !self.stopped else { return }
                    self.connect(url)
                }
            }
        }
    }

    private func ping(_ t: URLSessionWebSocketTask) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, !self.stopped, t === self.task else { return }
            t.sendPing { _ in }
            self.ping(t)
        }
    }

    private static func isChange(_ text: String) -> Bool {
        guard let d = text.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let type = o["type"] as? String else { return false }
        return type == "snapshot" || type == "cue_patch" || type == "stack_changed"
    }
}
