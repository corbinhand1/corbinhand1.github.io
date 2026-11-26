//
//  WebsiteSyncManager.swift
//  Cue to Cue
//
//  Publishes the open show to the website (GitHub Pages) and manages the
//  library of published show files. See GitHubPublisher for how files are
//  written and WebsiteLibrary for what is written.
//

import Foundation
import Combine

enum SyncNotificationType {
    case success
    case failure
    case info
}

enum WebsiteSyncError: LocalizedError {
    case noViewerPassword
    case viewerPasswordMismatch

    var errorDescription: String? {
        switch self {
        case .noViewerPassword:
            return "Set a viewer password in File ▸ Website… first. The website uses it to lock your show files so only your crew can read them."
        case .viewerPasswordMismatch:
            return "The viewer password saved in this app doesn't match the website's. Enter the website's current password in File ▸ Website…."
        }
    }
}

enum WebsiteSyncSettingsKeys {
    /// Legacy plain-text location; migrated to the Keychain on first launch.
    static let githubToken = "githubToken"
    static let repoOwner = "repoOwner"
    static let repoName = "repoName"
    static let autoSyncEnabled = "autoSyncEnabled"
    static let lastPublishedAt = "websiteLastPublishedAt"
    static let lastPublishedFile = "websiteLastPublishedFile"
    static let lastCommitURL = "websiteLastCommitURL"

    static let defaultRepoOwner = "corbinhand1"
    static let defaultRepoName = "corbinhand1.github.io"
    static let siteURL = URL(string: "https://nebulacreative.org/cuetocue/")!
}

@MainActor
final class WebsiteSyncManager: ObservableObject {

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success
        case failed(String)
    }

    enum ConnectionState: Equatable {
        case unknown
        case checking
        case notConfigured
        case connected(login: String)
        case failed(String)
    }

    @Published var isSyncing = false
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncTime: Date?
    @Published var lastSyncFilename: String?
    @Published var lastCommitURL: URL?
    @Published var connection: ConnectionState = .unknown
    @Published var library = ShowLibraryIndex()
    @Published var isLoadingLibrary = false
    @Published var libraryError: String?

    private let defaults: UserDefaults
    private let tokenStore: GitHubTokenStore
    private let viewerPasswordStore: GitHubTokenStore
    /// PBKDF2 rounds for new site keys. Lowered in tests.
    var keyIterations = WebsiteCipher.defaultIterations
    private var cachedCipher: (password: String, cipher: WebsiteCipher)?
    private let makePublisher: (String, GitHubRepository) -> GitHubPublisher

    init(defaults: UserDefaults = .standard,
         tokenStore: GitHubTokenStore? = nil,
         viewerPasswordStore: GitHubTokenStore? = nil,
         makePublisher: ((String, GitHubRepository) -> GitHubPublisher)? = nil) {
        self.defaults = defaults
        // The app itself is the host for unit tests; keep test runs away from
        // the real Keychain.
        let runningTests = NSClassFromString("XCTestCase") != nil
        self.tokenStore = tokenStore ?? (runningTests ? InMemoryGitHubTokenStore() : KeychainGitHubTokenStore())
        self.viewerPasswordStore = viewerPasswordStore ?? (runningTests ? InMemoryGitHubTokenStore() : KeychainGitHubTokenStore(
            account: "viewer-password", label: "Cue to Cue website viewer password"))
        self.makePublisher = makePublisher ?? { GitHubPublisher(token: $0, repository: $1) }
        if tokenStore != nil || !runningTests {
            migrateLegacyToken()
        }
        lastSyncTime = defaults.object(forKey: WebsiteSyncSettingsKeys.lastPublishedAt) as? Date
        lastSyncFilename = defaults.string(forKey: WebsiteSyncSettingsKeys.lastPublishedFile)
        lastCommitURL = defaults.string(forKey: WebsiteSyncSettingsKeys.lastCommitURL).flatMap(URL.init(string:))
        if !hasToken { connection = .notConfigured }
    }

    // MARK: - Settings

    var repository: GitHubRepository {
        get {
            GitHubRepository(
                owner: nonEmpty(defaults.string(forKey: WebsiteSyncSettingsKeys.repoOwner)) ?? WebsiteSyncSettingsKeys.defaultRepoOwner,
                name: nonEmpty(defaults.string(forKey: WebsiteSyncSettingsKeys.repoName)) ?? WebsiteSyncSettingsKeys.defaultRepoName)
        }
        set {
            defaults.set(newValue.owner.trimmingCharacters(in: .whitespaces), forKey: WebsiteSyncSettingsKeys.repoOwner)
            defaults.set(newValue.name.trimmingCharacters(in: .whitespaces), forKey: WebsiteSyncSettingsKeys.repoName)
            objectWillChange.send()
            connection = hasToken ? .unknown : .notConfigured
        }
    }

    var isAutoSyncEnabled: Bool {
        get { defaults.bool(forKey: WebsiteSyncSettingsKeys.autoSyncEnabled) }
        set {
            defaults.set(newValue, forKey: WebsiteSyncSettingsKeys.autoSyncEnabled)
            objectWillChange.send()
        }
    }

    var hasToken: Bool { tokenStore.readToken() != nil }

    /// Save (or clear, with nil/empty) the token. Stored in the Keychain.
    func setToken(_ token: String?) throws {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        try tokenStore.writeToken(trimmed?.isEmpty == false ? trimmed : nil)
        objectWillChange.send()
        connection = hasToken ? .unknown : .notConfigured
    }

    // MARK: - Viewer password

    var hasViewerPassword: Bool { viewerPasswordStore.readToken() != nil }

    /// Set the password the crew types to open the website.
    ///
    /// - If the site isn't locked yet, it's saved and the next publish locks it.
    /// - If it's the site's current password (e.g. set up from another Mac), it's saved.
    /// - Otherwise the site is re-locked with it in one commit, using the
    ///   previously saved password to read the existing files.
    func setViewerPassword(_ password: String) async throws {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defer { objectWillChange.send() }
        guard hasToken else {
            try viewerPasswordStore.writeToken(trimmed)
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        let github = try publisher()
        guard let siteKey = try await readSiteKey(github) else {
            try viewerPasswordStore.writeToken(trimmed)
            return
        }
        if let cipher = try? WebsiteCipher(password: trimmed, siteKey: siteKey) {
            cachedCipher = (trimmed, cipher)
            try viewerPasswordStore.writeToken(trimmed)
            await refreshLibrary()
            return
        }
        guard let old = viewerPasswordStore.readToken(),
              let oldCipher = try? WebsiteCipher(password: old, siteKey: siteKey) else {
            throw NSError(domain: "WebsiteSync", code: 3, userInfo: [NSLocalizedDescriptionKey:
                "That isn't the website's current password, and this app doesn't have the current one, so it can't change it. Enter the password the website uses now first."])
        }
        let newCipher = try WebsiteCipher.create(password: trimmed, iterations: keyIterations)
        var changes: [GitHubFileChange] = [.write(path: WebsiteCipher.sitePath, data: try newCipher.siteKeyData())]
        let indexFile = try await github.readFile(WebsitePayload.libraryIndexPath)
        let index = ShowLibraryIndex.decode(try indexFile.map(oldCipher.open))
        let paths = [WebsitePayload.dataPath, WebsitePayload.libraryIndexPath] + index.shows.map { WebsitePayload.showPath($0.slug) }
        for path in paths {
            let file = path == WebsitePayload.libraryIndexPath ? indexFile : try await github.readFile(path)
            guard let file else { continue }
            changes.append(.write(path: path, data: try newCipher.seal(try oldCipher.open(file))))
        }
        _ = try await github.commit(changes, message: "Change the website viewer password from Cue to Cue")
        cachedCipher = (trimmed, newCipher)
        try viewerPasswordStore.writeToken(trimmed)
        library = index
    }

    private func readSiteKey(_ github: GitHubPublisher) async throws -> WebsiteSiteKey? {
        WebsiteCipher.decodeSiteKey(try await github.readFile(WebsiteCipher.sitePath))
    }

    private func cipher(password: String, siteKey: WebsiteSiteKey) throws -> WebsiteCipher {
        if let cached = cachedCipher, cached.password == password, cached.cipher.siteKey == siteKey {
            return cached.cipher
        }
        do {
            let cipher = try WebsiteCipher(password: password, siteKey: siteKey)
            cachedCipher = (password, cipher)
            return cipher
        } catch WebsiteEncryptionError.wrongPassword {
            throw WebsiteSyncError.viewerPasswordMismatch
        }
    }

    /// The cipher to write with. If the site isn't locked yet, also returns the
    /// changes that lock it: the key file plus encrypted copies of show files
    /// earlier publishes left readable.
    private func cipherForWriting(_ github: GitHubPublisher) async throws -> (WebsiteCipher, [GitHubFileChange]) {
        guard let password = viewerPasswordStore.readToken() else { throw WebsiteSyncError.noViewerPassword }
        if let siteKey = try await readSiteKey(github) {
            return (try cipher(password: password, siteKey: siteKey), [])
        }
        let cipher = try WebsiteCipher.create(password: password, iterations: keyIterations)
        cachedCipher = (password, cipher)
        var changes: [GitHubFileChange] = [.write(path: WebsiteCipher.sitePath, data: try cipher.siteKeyData())]
        let indexFile = try await github.readFile(WebsitePayload.libraryIndexPath)
        if let indexFile, !WebsiteCipher.isEncrypted(indexFile) {
            changes.append(.write(path: WebsitePayload.libraryIndexPath, data: try cipher.seal(indexFile)))
            for show in ShowLibraryIndex.decode(indexFile).shows {
                let path = WebsitePayload.showPath(show.slug)
                if let file = try await github.readFile(path), !WebsiteCipher.isEncrypted(file) {
                    changes.append(.write(path: path, data: try cipher.seal(file)))
                }
            }
        }
        return (cipher, changes)
    }

    /// Read the library index, decrypting it if needed.
    private func readLibrary(_ github: GitHubPublisher, cipher: WebsiteCipher) async throws -> ShowLibraryIndex {
        ShowLibraryIndex.decode(try await github.readFile(WebsitePayload.libraryIndexPath).map(cipher.open))
    }

    /// Earlier builds stored the token in plain text in preferences. Copy it
    /// into the Keychain, but leave the plain-text copy until the user removes
    /// it: older installed copies of the app share these preferences and still
    /// read it from there.
    private func migrateLegacyToken() {
        guard let legacy = nonEmpty(defaults.string(forKey: WebsiteSyncSettingsKeys.githubToken)),
              tokenStore.readToken() == nil else { return }
        try? tokenStore.writeToken(legacy)
    }

    /// A plain-text copy of the token is still in the preferences file.
    var hasLegacyPlainTextToken: Bool {
        nonEmpty(defaults.string(forKey: WebsiteSyncSettingsKeys.githubToken)) != nil
    }

    func removeLegacyPlainTextToken() {
        defaults.removeObject(forKey: WebsiteSyncSettingsKeys.githubToken)
        objectWillChange.send()
    }

    private func publisher() throws -> GitHubPublisher {
        guard let token = tokenStore.readToken() else { throw GitHubError.notConfigured }
        return makePublisher(token, repository)
    }

    // MARK: - Connection

    /// Check the token and repository, then load the show library.
    func checkConnection() async {
        guard hasToken else {
            connection = .notConfigured
            return
        }
        connection = .checking
        do {
            let info = try await publisher().validate()
            if info.canPush {
                connection = .connected(login: info.login)
                await refreshLibrary()
            } else {
                connection = .failed("Signed in as \(info.login), but this token can't write to \(repository).")
            }
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }

    func refreshLibrary() async {
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }
        do {
            let github = try publisher()
            var data = try await github.readFile(WebsitePayload.libraryIndexPath)
            if let file = data, WebsiteCipher.isEncrypted(file) {
                guard let password = viewerPasswordStore.readToken() else { throw WebsiteSyncError.noViewerPassword }
                guard let siteKey = try await readSiteKey(github) else { throw WebsiteEncryptionError.corruptFile }
                data = try cipher(password: password, siteKey: siteKey).open(file)
            }
            library = ShowLibraryIndex.decode(data)
            libraryError = nil
        } catch {
            libraryError = error.localizedDescription
        }
    }

    // MARK: - Publishing

    /// Publish the open show as the website's current show and add it to the
    /// library. `completion` is kept for existing callers.
    func syncCueData(
        cueStacks: [CueStack],
        selectedCueStackIndex: Int,
        filename: String,
        settingsManager: SettingsManager,
        completion: @escaping (Bool, String?) -> Void = { _, _ in }
    ) {
        guard !isSyncing else {
            completion(false, "Publishing is already in progress")
            return
        }
        let highlightColors = settingsManager.settings.highlightColors
        Task {
            let result = await publish(cueStacks: cueStacks, selectedCueStackIndex: selectedCueStackIndex,
                                       highlightColors: highlightColors, filename: filename)
            switch result {
            case .success: completion(true, nil)
            case .failure(let error): completion(false, error.localizedDescription)
            }
        }
    }

    @discardableResult
    func publish(cueStacks: [CueStack], selectedCueStackIndex: Int,
                 highlightColors: [HighlightColorSetting], filename: String) async -> Result<GitHubCommitResult, Error> {
        guard !cueStacks.isEmpty else {
            let message = "There are no cue stacks to publish."
            syncStatus = .failed(message)
            return .failure(NSError(domain: "WebsiteSync", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
        }
        isSyncing = true
        syncStatus = .syncing
        defer { isSyncing = false }

        do {
            let github = try publisher()
            let (cipher, lockChanges) = try await cipherForWriting(github)
            // Start from the library on GitHub, so shows published from another
            // Mac aren't dropped.
            let existing = try await readLibrary(github, cipher: cipher)
            let cleanName = filename.isEmpty ? "Untitled.cuestack" : filename
            let bundle = try WebsitePayload.bundle(
                cueStacks: cueStacks, selectedCueStackIndex: selectedCueStackIndex,
                highlightColors: highlightColors, filename: cleanName, existingLibrary: existing,
                cipher: cipher)
            let written = Set(bundle.changes.map(\.path))
            let changes = lockChanges.filter { !written.contains($0.path) } + bundle.changes
            let result = try await github.commit(changes, message: "Publish \(cleanName) from Cue to Cue")

            library = bundle.library
            syncStatus = .success
            lastSyncTime = Date()
            lastSyncFilename = cleanName
            lastCommitURL = result.htmlURL
            defaults.set(lastSyncTime, forKey: WebsiteSyncSettingsKeys.lastPublishedAt)
            defaults.set(cleanName, forKey: WebsiteSyncSettingsKeys.lastPublishedFile)
            defaults.set(result.htmlURL?.absoluteString, forKey: WebsiteSyncSettingsKeys.lastCommitURL)
            if case .connected = connection {} else if let login = try? await github.validate().login { connection = .connected(login: login) }
            return .success(result)
        } catch {
            syncStatus = .failed(error.localizedDescription)
            if let gitHubError = error as? GitHubError {
                switch gitHubError {
                case .notConfigured: connection = .notConfigured
                case .unauthorized, .forbidden, .notFound: connection = .failed(gitHubError.localizedDescription)
                default: break
                }
            }
            return .failure(error)
        }
    }

    func autoSyncIfEnabled(
        cueStacks: [CueStack],
        selectedCueStackIndex: Int,
        filename: String,
        settingsManager: SettingsManager
    ) {
        guard isAutoSyncEnabled, hasToken, hasViewerPassword else { return }
        syncCueData(cueStacks: cueStacks, selectedCueStackIndex: selectedCueStackIndex,
                    filename: filename, settingsManager: settingsManager)
    }

    // MARK: - Library management

    /// Remove a show from the website library (its file and its listing).
    /// The current show can't be removed; publish another show first.
    func removeShow(slug: String) async throws {
        guard slug != library.current else {
            throw NSError(domain: "WebsiteSync", code: 2, userInfo: [NSLocalizedDescriptionKey:
                "That's the show the website opens by default. Publish a different show first, then remove this one."])
        }
        try await updateLibrary(message: "Remove show \(slug) from Cue to Cue",
                                extraChanges: [.delete(path: WebsitePayload.showPath(slug))]) { index, time in
            index.remove(slug: slug, at: time)
        }
    }

    /// Change the name the website shows for a published show.
    func renameShow(slug: String, to name: String) async throws {
        try await updateLibrary(message: "Rename show \(slug) from Cue to Cue", extraChanges: []) { index, time in
            index.rename(slug: slug, to: name, at: time)
        }
    }

    private func updateLibrary(message: String, extraChanges: [GitHubFileChange],
                               change: (inout ShowLibraryIndex, String) -> Void) async throws {
        isSyncing = true
        defer { isSyncing = false }
        let github = try publisher()
        let (cipher, lockChanges) = try await cipherForWriting(github)
        var index = try await readLibrary(github, cipher: cipher)
        let time = ISO8601DateFormatter.withFractionalSeconds.string(from: Date())
        change(&index, time)
        // Only delete files the library actually lists, so a missing file
        // can't make GitHub reject the commit.
        let deletions = extraChanges.filter { change in
            if case .delete(let path) = change {
                return library.shows.contains { WebsitePayload.showPath($0.slug) == path }
            }
            return true
        }
        let changes = deletions + [.write(path: WebsitePayload.libraryIndexPath, data: try cipher.seal(index.encoded()))]
        let written = Set(changes.map(\.path))
        _ = try await github.commit(lockChanges.filter { !written.contains($0.path) } + changes, message: message)
        library = index
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
