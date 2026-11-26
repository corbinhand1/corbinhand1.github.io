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
    /// Edits waiting to be sent to the Mac (saved on disk, so they survive relaunch).
    @Published private(set) var pending: [PendingEdit] = Outbox.loadPending()

    var unsent: [PendingEdit] { pending.filter { $0.conflictRemote == nil } }
    var conflicts: [PendingEdit] { pending.filter { $0.conflictRemote != nil } }
    var unsentCueIDs: Set<String> { Set(pending.map(\.cueID)) }

    private var socket: LiveSocket?
    private var refreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var flushing = false

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
            let s = try await API(baseURL: url, token: t).currentSheet()
            Outbox.saveSheet(s)
            sheet = overlay(s)
            selectedStackID = s.cueStackId
            startLive()
            ensureRetry()
        } catch {
            self.error = Self.message(error)
        }
    }

    /// Reconnect on launch with the saved token.
    func resume() async {
        guard token != nil, let api else { return }
        do {
            let s = try await api.currentSheet()
            Outbox.saveSheet(s)
            sheet = overlay(s)
            selectedStackID = s.cueStackId
            startLive()
            ensureRetry()
        } catch {
            // Offline at launch: open the last-seen sheet so you can keep editing.
            if error is URLError, let cached = Outbox.loadSheet() {
                sheet = overlay(cached)
                selectedStackID = cached.cueStackId
                startLive()
                ensureRetry()
            } else {
                self.error = Self.message(error)
            }
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
        retryTask?.cancel(); retryTask = nil
        pending = []; Outbox.clearAll()
        socket?.stop(); socket = nil
        Keychain.set(nil, for: "token")
        token = nil; sheet = nil; live = false
    }

    private func startLive() {
        guard let url = api?.webSocketURL else { return }
        let s = LiveSocket(
            onChange: { [weak self] in Task { @MainActor in self?.scheduleRefresh() } },
            onState: { [weak self] up in
                Task { @MainActor in
                    guard let self else { return }
                    let wasDown = !self.live
                    self.live = up
                    if up && wasDown { self.ensureRetry() }   // back online: send what's waiting
                }
            })
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
            let s = try await api.sheet(stackID: id)
            Outbox.saveSheet(s)
            sheet = overlay(s)
        } catch {
            // Offline is normal here; the Live badge already says so.
            if !(error is URLError) { self.error = Self.message(error) }
        }
    }

    func selectStack(_ id: String) async {
        selectedStackID = id
        await refresh()
    }

    // MARK: Editing with an outbox

    private func cell(_ cue: SheetCue, _ col: Int) -> String { col < cue.values.count ? cue.values[col] : "" }

    /// Saves an edit. It shows immediately and is sent in the background; if
    /// the Mac can't be reached it waits in the outbox and goes out when
    /// the connection returns. `base` is the value you started from, used to
    /// notice if someone else changed the same cell meanwhile.
    @discardableResult
    func edit(cue: SheetCue, column: Int, value: String, base: String? = nil) async -> Bool {
        guard let sheet else { return false }
        let baseValue = base ?? cell(cue, column)
        if let i = pending.firstIndex(where: { $0.cueID == cue.id && $0.column == column }) {
            pending[i].newValue = value
            if pending[i].conflictRemote == nil && value == pending[i].base { pending.remove(at: i) }
        } else if value != baseValue {
            let num = cue.values.first ?? ""
            let desc = When.stripped(sheet.descriptionColumn < cue.values.count ? cue.values[sheet.descriptionColumn] : "")
            let label = [num.isEmpty ? nil : "Cue \(num)", desc.isEmpty ? nil : desc].compactMap { $0 }.joined(separator: " · ")
            pending.append(PendingEdit(stackID: sheet.cueStackId, cueID: cue.id, column: column,
                                       columnName: column < sheet.columns.count ? sheet.columns[column].name : "Column",
                                       cueLabel: label.isEmpty ? "Cue" : label,
                                       base: baseValue, newValue: value))
        }
        applyLocal(cueID: cue.id, column: column, value: value)
        Outbox.savePending(pending)
        ensureRetry()
        return true
    }

    /// Re-applies unsent edits on top of a freshly loaded sheet so they don't visually vanish.
    private func overlay(_ s: Sheet) -> Sheet {
        var s = s
        for e in pending where e.stackID == s.cueStackId {
            if let i = s.cues.firstIndex(where: { $0.id == e.cueID }), e.column < s.cues[i].values.count {
                s.cues[i].values[e.column] = e.newValue
            }
        }
        return s
    }

    /// Keeps trying to send the outbox every few seconds until it's empty.
    func ensureRetry() {
        guard retryTask == nil, !unsent.isEmpty else { return }
        retryTask = Task { [weak self] in
            while let self, !Task.isCancelled, !self.unsent.isEmpty {
                await self.flush()
                if self.unsent.isEmpty { break }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            self?.retryTask = nil
        }
    }

    /// Sends waiting edits one by one, skipping any the Mac has changed in the meantime.
    func flush() async {
        guard !flushing, let api, token != nil else { return }
        flushing = true; defer { flushing = false }
        var sheets: [String: Sheet] = [:]
        var sentAny = false

        for id in unsent.map(\.id) {
            guard let e = pending.first(where: { $0.id == id }), e.conflictRemote == nil else { continue }
            do {
                if sheets[e.stackID] == nil { sheets[e.stackID] = try await api.sheet(stackID: e.stackID) }
                guard let remoteCue = sheets[e.stackID]?.cues.first(where: { $0.id == e.cueID }) else {
                    drop(id, reason: "\(e.cueLabel) no longer exists on the Mac, so your \(e.columnName) edit was discarded.")
                    continue
                }
                let remote = cell(remoteCue, e.column)
                if remote == e.newValue { drop(id); continue }            // already there
                if remote != e.base {                                      // someone else changed it
                    if let i = pending.firstIndex(where: { $0.id == id }) { pending[i].conflictRemote = remote }
                    Outbox.savePending(pending); continue
                }
                try await api.edit(cueID: e.cueID, column: e.column, value: e.newValue)
                drop(id); sentAny = true
            } catch let APIError.http(code, msg) where [400, 403, 404].contains(code) {
                drop(id, reason: msg.isEmpty ? "Your \(e.columnName) edit on \(e.cueLabel) was rejected (\(code))." : msg)
            } catch let APIError.http(401, _) {
                self.error = APIError.http(401, "").localizedDescription
                return
            } catch {
                return   // offline or server busy: keep everything and try again later
            }
        }
        if sentAny { await refresh() }
    }

    private func drop(_ id: UUID, reason: String? = nil) {
        pending.removeAll { $0.id == id }
        Outbox.savePending(pending)
        if let reason { error = reason }
    }

    /// Resolve a conflict: send your version anyway, or keep what's on the Mac.
    func resolve(_ id: UUID, keepMine: Bool) async {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        if keepMine {
            pending[i].base = pending[i].conflictRemote ?? pending[i].base
            pending[i].conflictRemote = nil
            Outbox.savePending(pending)
            ensureRetry()
        } else {
            drop(id)
            await refresh()
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
