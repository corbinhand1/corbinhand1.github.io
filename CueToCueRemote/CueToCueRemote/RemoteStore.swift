import Foundation
import SwiftUI
import LocalAuthentication

@MainActor
final class RemoteStore: ObservableObject {
    @AppStorage("serverAddress") var serverAddress = ""
    @AppStorage("username") var username = ""

    @AppStorage("faceIDEnabled") var faceIDEnabled = false
    /// Admins can change columns; everyone with access to a stack can restructure its cues.
    @AppStorage("isAdmin") var isAdmin = false
    /// Bonjour name of the Mac we paired with on the local network (so we can find it again if its IP changes).
    @AppStorage("bonjourName") var bonjourName = ""
    /// Address used when away from home (Tailscale name or tunnel URL).
    @AppStorage("remoteAddress") var remoteAddress = ""
    /// True while `remoteAddress` was saved automatically from the Mac (false once you type your own).
    @AppStorage("remoteAddressAuto") var remoteAddressAuto = true
    /// Whether the Mac reported a Tailscale address the last time we asked (nil = not asked yet).
    @Published var macHasTailscale: Bool?
    var lastReroute = Date.distantPast
    private var rerouteTask: Task<Void, Never>?

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
    @Published var toast: Toast?
    @Published var undoStack: [HistoryEntry] = []
    @Published var redoStack: [HistoryEntry] = []
    var toastTask: Task<Void, Never>?

    var unsent: [PendingEdit] { pending.filter { $0.conflictRemote == nil } }
    var conflicts: [PendingEdit] { pending.filter { $0.conflictRemote != nil } }
    var unsentCueIDs: Set<String> { Set(pending.map(\.cueID)) }

    private var socket: LiveSocket?
    private var refreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var flushing = false

    var isSignedIn: Bool { token != nil && sheet != nil }

    var api: API? {
        guard let url = API.normalize(serverAddress) else { return nil }
        return API(baseURL: url, token: token)
    }

    // MARK: Connect

    func signIn(address: String, username: String, password: String, rememberWithFaceID: Bool = false,
                foundName: String? = nil) async {
        serverAddress = address
        if let foundName {
            bonjourName = foundName
        } else if let u = API.normalize(address), [.tailscale, .encrypted].contains(ConnectionSecurity.classify(u)) {
            remoteAddress = address; remoteAddressAuto = false      // a hand-typed address that works away from home
        }
        self.username = username
        guard let url = API.normalize(address) else { error = APIError.badURL.localizedDescription; return }
        if ConnectionSecurity.classify(url) == .unsafe {
            error = "That address is on the public internet without encryption, so your password could be read on the way. Use https, your Tailscale name, or your Wi-Fi address."
            return
        }
        busy = true; defer { busy = false }
        do {
            let login = try await API(baseURL: url).login(username: username, password: password)
            let t = login.token
            isAdmin = login.isAdmin
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
            Task { await learnRemoteAddress() }
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
            Task { await learnRemoteAddress() }
        } catch {
            // Can't reach the saved address: look for the Mac on this network, else use the away address.
            if error is URLError, await reroute() { await resume(); return }
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

    // MARK: Finding the Mac

    /// Re-aims at the Mac: first on the local network by its Bonjour name, otherwise the away address.
    /// Returns true if the address changed. Only follows the Mac we paired with.
    @discardableResult
    func reroute() async -> Bool {
        lastReroute = Date()
        let before = serverAddress
        var candidates: [String] = []
        if !bonjourName.isEmpty, let mac = await MacFinder.find(named: bonjourName), let addr = mac.address { candidates.append(addr) }
        if !remoteAddress.isEmpty { candidates.append(remoteAddress) }
        for addr in candidates where addr != before {
            guard let url = API.normalize(addr), ConnectionSecurity.classify(url) != .unsafe else { continue }
            // Only follow an address that proves it is the Mac that issued our session. This stops a
            // look-alike on a venue network from collecting the session token or password.
            if let token, await Proof.verify(baseURL: url, token: token) {
                serverAddress = addr
                return true
            }
        }
        if !candidates.isEmpty, !candidates.contains(before) {
            error = "Found a Mac, but couldn't confirm it's yours. Sign in again from the sign-in screen to reconnect."
        }
        return false
    }

    /// If the link stays down for a few seconds (you walked off the Wi-Fi), look for the Mac again:
    /// first on this network, then at its saved Tailscale address.
    private func scheduleRerouteIfStillDown() {
        guard rerouteTask == nil, token != nil else { return }
        rerouteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.rerouteTask = nil
            guard !self.live, Date().timeIntervalSince(self.lastReroute) > 15 else { return }
            if await self.reroute() { self.startLive(); await self.refresh() }
        }
    }

    /// While connected, ask the Mac for its Tailscale address and save it, so the phone can
    /// connect automatically when you're off the Wi-Fi.
    func learnRemoteAddress() async {
        guard let api, token != nil else { return }
        guard let info = try? await api.networkInfo() else { return }
        macHasTailscale = info.tailscale != nil
        guard let ts = info.tailscale, remoteAddress.isEmpty || remoteAddressAuto else { return }
        let address = "\(ts):\(info.port)"
        if remoteAddress != address { remoteAddress = address }
        remoteAddressAuto = true
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
        socket?.stop()
        guard let url = api?.webSocketURL else { return }
        let s = LiveSocket(
            onChange: { [weak self] in Task { @MainActor in self?.scheduleRefresh() } },
            onState: { [weak self] up in
                Task { @MainActor in
                    guard let self else { return }
                    let wasDown = !self.live
                    self.live = up
                    if up && wasDown { self.ensureRetry() }   // back online: send what's waiting
                    if !up { self.scheduleRerouteIfStillDown() }
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
            // Offline is normal here; the Live badge already says so. Try finding the Mac again.
            if error is URLError {
                if Date().timeIntervalSince(lastReroute) > 15, await reroute() { startLive(); await refresh() }
            } else { self.error = Self.message(error) }
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
    func edit(cue: SheetCue, column: Int, value: String, base: String? = nil, recordHistory: Bool = true) async -> Bool {
        guard let sheet else { return false }
        let baseValue = base ?? cell(cue, column)
        if recordHistory && value != baseValue {
            let name = column < sheet.columns.count ? sheet.columns[column].name : "Cell"
            record("Edit \(name)",
                   undo: { [weak self] in await self?.edit(cue: cue, column: column, value: baseValue, base: value, recordHistory: false) ?? false },
                   redo: { [weak self] in await self?.edit(cue: cue, column: column, value: value, base: baseValue, recordHistory: false) ?? false })
        }
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

    func applyLocal(cueID: String, column: Int, value: String) {
        guard let i = sheet?.cues.firstIndex(where: { $0.id == cueID }),
              let n = sheet?.cues[i].values.count, column < n else { return }
        sheet?.cues[i].values[column] = value
    }

    static func message(_ error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription { return d }
        if let e = error as? URLError {
            switch e.code {
            case .notConnectedToInternet, .dataNotAllowed:
                return "Your iPhone says it can't reach the network. If you're on Wi-Fi, check Settings → Cue Remote → Local Network is on."
            case .timedOut:
                return "The Mac didn't answer. Check that Cue to Cue is open on the Mac and both are on the same Wi-Fi."
            case .cannotConnectToHost, .networkConnectionLost:
                return "Reached the Mac's address, but Cue to Cue's server isn't answering there. Make sure Cue to Cue is open and its web server is on."
            case .cannotFindHost, .dnsLookupFailed:
                return "Couldn't find that address. Check it, or pick your Mac from the list."
            case .appTransportSecurityRequiresSecureConnection:
                return "iOS blocked an unencrypted connection to that address."
            default:
                return "Can't reach the Mac (error \(e.code.rawValue)). Check Wi-Fi and Local Network access."
            }
        }
        return error.localizedDescription
    }
}
