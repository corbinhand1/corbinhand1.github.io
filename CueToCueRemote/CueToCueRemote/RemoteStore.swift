import Foundation
import SwiftUI
import LocalAuthentication

@MainActor
final class RemoteStore: ObservableObject {
    @AppStorage("serverAddress") var serverAddress = ""
    @AppStorage("username") var username = ""

    @AppStorage("faceIDEnabled") var faceIDEnabled = false

    @Published var token: String? = Keychain.get("token")
    /// Starts locked when Face ID protection is on, so the show isn't visible until you unlock.
    @Published var locked: Bool = {
        UserDefaults.standard.bool(forKey: "faceIDEnabled") && Keychain.get("token") != nil
    }()
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

    func signIn(address: String, username: String, password: String, rememberWithFaceID: Bool = false) async {
        serverAddress = address
        self.username = username
        guard let url = API.normalize(address) else { error = APIError.badURL.localizedDescription; return }
        busy = true; defer { busy = false }
        do {
            let t = try await API(baseURL: url).login(username: username, password: password)
            Keychain.set(t, for: "token")
            token = t
            error = nil
            if rememberWithFaceID, Biometrics.isAvailable {
                faceIDEnabled = Keychain.setProtected(password, for: "password")
                if !faceIDEnabled { error = "Signed in, but \(Biometrics.name) couldn't be turned on for this device." }
            } else if !rememberWithFaceID {
                disableFaceID()
            }
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

    // MARK: Face ID

    /// Unlocks the app with Face ID, then reconnects.
    func unlock() async {
        guard let ctx = await Biometrics.authenticate(reason: "Unlock your cue sheet") else { return }
        locked = false
        if sheet == nil { await resume() } else { await refresh() }
        // The saved login may have expired; sign in again with the Face ID-protected password.
        if sheet == nil, faceIDEnabled { await signInSaved(context: ctx) }
    }

    /// One-tap sign in from the sign-in screen using the Face ID-protected password.
    func signInWithFaceID() async {
        guard let ctx = await Biometrics.authenticate(reason: "Sign in to Cue Remote") else { return }
        await signInSaved(context: ctx)
    }

    private func signInSaved(context: LAContext) async {
        let pw = await Task.detached { Keychain.getProtected("password", context: context) }.value
        guard let pw else { error = "Couldn't read your saved password. Sign in with it once more."; return }
        await signIn(address: serverAddress, username: username, password: pw, rememberWithFaceID: true)
    }

    func disableFaceID() {
        Keychain.setProtected(nil, for: "password")
        faceIDEnabled = false
        locked = false
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
