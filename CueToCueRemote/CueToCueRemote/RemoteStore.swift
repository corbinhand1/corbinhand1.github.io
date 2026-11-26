import Foundation
import SwiftUI

@MainActor
final class RemoteStore: ObservableObject {
    @AppStorage("serverAddress") var serverAddress = ""
    @AppStorage("username") var username = ""

    @Published var token: String? = Keychain.get("token")
    @Published var sheet: Sheet?
    @Published var selectedStackID: String?
    @Published var live = false
    @Published var busy = false
    @Published var error: String?

    private var socket: LiveSocket?
    private var refreshTask: Task<Void, Never>?

    var isSignedIn: Bool { token != nil && sheet != nil }

    private var api: API? {
        guard let url = API.normalize(serverAddress) else { return nil }
        return API(baseURL: url, token: token)
    }

    // MARK: Connect

    func signIn(address: String, username: String, password: String) async {
        serverAddress = address
        self.username = username
        guard let url = API.normalize(address) else { error = APIError.badURL.localizedDescription; return }
        busy = true; defer { busy = false }
        do {
            let t = try await API(baseURL: url).login(username: username, password: password)
            Keychain.set(t, for: "token")
            token = t
            error = nil
            sheet = try await API(baseURL: url, token: t).currentSheet()
            selectedStackID = sheet?.cueStackId
            startLive()
        } catch {
            self.error = Self.message(error)
        }
    }

    /// Reconnect on launch with the saved token.
    func resume() async {
        guard token != nil, let api else { return }
        do {
            let s = try await api.currentSheet()
            sheet = s
            selectedStackID = s.cueStackId
            startLive()
        } catch {
            self.error = Self.message(error)
        }
    }

    func signOut() {
        socket?.stop(); socket = nil
        Keychain.set(nil, for: "token")
        token = nil; sheet = nil; live = false
    }

    private func startLive() {
        guard let url = api?.webSocketURL else { return }
        let s = LiveSocket(
            onChange: { [weak self] in Task { @MainActor in self?.scheduleRefresh() } },
            onState: { [weak self] up in Task { @MainActor in self?.live = up } })
        socket = s
        s.start(url: url)
    }

    // MARK: Data

    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !Task.isCancelled { await refresh() }
        }
    }

    func refresh() async {
        guard let api, let id = selectedStackID else { return }
        do {
            sheet = try await api.sheet(stackID: id)
        } catch {
            self.error = Self.message(error)
        }
    }

    func selectStack(_ id: String) async {
        selectedStackID = id
        await refresh()
    }

    func edit(cue: SheetCue, column: Int, value: String) async -> Bool {
        guard let api else { return false }
        do {
            try await api.edit(cueID: cue.id, column: column, value: value)
            applyLocal(cueID: cue.id, column: column, value: value)
            return true
        } catch {
            self.error = Self.message(error)
            return false
        }
    }

    /// Adds a blank cue at the end and returns its id so the editor can open on it.
    func addCue() async -> String? {
        guard let api, let sheet else { return nil }
        do {
            let id = try await api.addCue(stackID: sheet.cueStackId,
                                          values: Array(repeating: "", count: sheet.columns.count))
            await refresh()
            return id
        } catch { self.error = Self.message(error); return nil }
    }

    func delete(_ cue: SheetCue) async {
        guard let api else { return }
        do {
            try await api.deleteCue(id: cue.id)
            sheet?.cues.removeAll { $0.id == cue.id }
        } catch { self.error = Self.message(error); await refresh() }
    }

    private func applyLocal(cueID: String, column: Int, value: String) {
        guard let i = sheet?.cues.firstIndex(where: { $0.id == cueID }),
              let n = sheet?.cues[i].values.count, column < n else { return }
        sheet?.cues[i].values[column] = value
    }

    private static func message(_ error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription { return d }
        if (error as? URLError)?.code == .notConnectedToInternet { return "No internet connection." }
        if error is URLError { return "Can't reach the Mac. Is Cue to Cue running and the address right?" }
        return error.localizedDescription
    }
}
