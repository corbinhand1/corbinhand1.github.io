//
//  WebsitePublishingTests.swift
//  Cue to CueTests
//
//  Website publishing against a fake GitHub (URLProtocol): one-commit
//  publish, retries, error messages, the show library, and token storage.
//  Nothing here contacts the real GitHub.
//

import XCTest
@testable import Cue_to_Cue

// MARK: - Fake GitHub

final class FakeGitHub: URLProtocol {
    struct Recorded {
        let method: String
        let path: String
        let headers: [String: String]
        let body: [String: Any]?
    }

    static var files: [String: Data] = [:]          // path -> content on the default branch
    static var head = "commit0"
    static var requests: [Recorded] = []
    static var refConflictsRemaining = 0             // PATCH ref returns 422 this many times
    static var forcedStatus: (path: String, status: Int, headers: [String: String], message: String)?
    private static var blobs: [String: Data] = [:]
    private static var trees: [String: [String: Data]] = [:]
    private static var commits: [String: String] = [:] // commit -> tree
    private static var counter = 0

    static func reset() {
        files = [:]; head = "commit0"; requests = []; refConflictsRemaining = 0; forcedStatus = nil
        blobs = [:]; trees = ["tree0": [:]]; commits = ["commit0": "tree0"]; counter = 0
    }

    static func session() -> URLSession { GitHubPublisher.makeSession(protocolClasses: [FakeGitHub.self]) }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.github.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let path = url.path
        var bodyData = request.httpBody
        if bodyData == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 65536)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            bodyData = data
        }
        let body = bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let method = request.httpMethod ?? "GET"
        FakeGitHub.requests.append(Recorded(method: method, path: path, headers: request.allHTTPHeaderFields ?? [:], body: body))

        if let forced = FakeGitHub.forcedStatus, path.hasSuffix(forced.path) {
            return respond(forced.status, ["message": forced.message], headers: forced.headers)
        }

        let repo = "/repos/owner/site"
        switch (method, path) {
        case ("GET", "/user"):
            respond(200, ["login": "stage-manager"])
        case ("GET", repo):
            respond(200, ["default_branch": "main", "permissions": ["push": true]])
        case ("GET", let p) where p.hasPrefix(repo + "/contents/"):
            let file = String(p.dropFirst((repo + "/contents/").count)).removingPercentEncoding!
            if let data = FakeGitHub.files[file] { respondRaw(200, data) } else { respond(404, ["message": "Not Found"]) }
        case ("POST", repo + "/git/blobs"):
            FakeGitHub.counter += 1
            let sha = "blob\(FakeGitHub.counter)"
            FakeGitHub.blobs[sha] = Data(base64Encoded: body?["content"] as? String ?? "")
            respond(201, ["sha": sha])
        case ("GET", repo + "/git/ref/heads/main"):
            respond(200, ["object": ["sha": FakeGitHub.head]])
        case ("GET", let p) where p.hasPrefix(repo + "/git/commits/"):
            let sha = String(p.split(separator: "/").last!)
            respond(200, ["sha": sha, "tree": ["sha": FakeGitHub.commits[sha] ?? "tree0"]])
        case ("POST", repo + "/git/trees"):
            var tree = FakeGitHub.trees[body?["base_tree"] as? String ?? ""] ?? [:]
            for entry in body?["tree"] as? [[String: Any]] ?? [] {
                let p = entry["path"] as! String
                if let sha = entry["sha"] as? String { tree[p] = FakeGitHub.blobs[sha] } else { tree[p] = nil }
            }
            FakeGitHub.counter += 1
            let sha = "tree\(FakeGitHub.counter)"
            FakeGitHub.trees[sha] = tree
            respond(201, ["sha": sha])
        case ("POST", repo + "/git/commits"):
            FakeGitHub.counter += 1
            let sha = "commit\(FakeGitHub.counter)"
            FakeGitHub.commits[sha] = body?["tree"] as? String
            respond(201, ["sha": sha, "html_url": "https://github.com/owner/site/commit/\(sha)"])
        case ("PATCH", repo + "/git/refs/heads/main"):
            if FakeGitHub.refConflictsRemaining > 0 {
                FakeGitHub.refConflictsRemaining -= 1
                // Someone else pushed meanwhile.
                FakeGitHub.counter += 1
                let other = "commit\(FakeGitHub.counter)"
                FakeGitHub.commits[other] = FakeGitHub.commits[FakeGitHub.head]
                FakeGitHub.head = other
                return respond(422, ["message": "Update is not a fast forward"])
            }
            let sha = body?["sha"] as! String
            FakeGitHub.head = sha
            FakeGitHub.files = FakeGitHub.trees[FakeGitHub.commits[sha] ?? ""] ?? [:]
            respond(200, ["object": ["sha": sha]])
        default:
            respond(500, ["message": "unexpected \(method) \(path)"])
        }
    }

    private func respond(_ status: Int, _ json: [String: Any], headers: [String: String] = [:]) {
        respondRaw(status, try! JSONSerialization.data(withJSONObject: json), headers: headers)
    }

    private func respondRaw(_ status: Int, _ data: Data, headers: [String: String] = [:]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

// MARK: - Tests

@MainActor
final class WebsitePublishingTests: XCTestCase {

    private let repo = GitHubRepository(owner: "owner", name: "site")
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        FakeGitHub.reset()
        suite = "WebsitePublishingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func publisher() -> GitHubPublisher {
        GitHubPublisher(token: "test-token", repository: repo, session: FakeGitHub.session())
    }

    private func manager(token: String? = "test-token") -> WebsiteSyncManager {
        defaults.set("owner", forKey: WebsiteSyncSettingsKeys.repoOwner)
        defaults.set("site", forKey: WebsiteSyncSettingsKeys.repoName)
        return WebsiteSyncManager(defaults: defaults, tokenStore: InMemoryGitHubTokenStore(token: token)) { token, repo in
            GitHubPublisher(token: token, repository: repo, session: FakeGitHub.session())
        }
    }

    private func stacks(_ count: Int = 2) -> [CueStack] {
        (0..<count).map { i in
            CueStack(name: "Stack \(i)",
                     cues: [Cue(values: ["\(i)01", "Doors"], timerValue: "1:00"), Cue(values: ["\(i)02", "Walk in"])],
                     columns: [Column(name: "#", width: 50), Column(name: i == 0 ? "Description" : "Notes", width: 200)])
        }
    }

    private func json(_ path: String) throws -> [String: Any] {
        let data = try XCTUnwrap(FakeGitHub.files[path], "\(path) not on GitHub")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Slugs and library

    func testSlug() {
        XCTAssertEqual(WebsitePayload.slug(forFilename: "WT_LHR_26_Fall.cuestack"), "wt-lhr-26-fall")
        XCTAssertEqual(WebsitePayload.slug(forFilename: "Café Show (v2).json"), "cafe-show-v2")
        XCTAssertEqual(WebsitePayload.slug(forFilename: "!!!.cuestack"), "untitled")
    }

    func testLibraryPublishKeepsCustomNameAndOrdersNewestFirst() {
        var index = ShowLibraryIndex()
        let a = ShowLibraryEntry(slug: "a", name: "A", filename: "A.cuestack", lastPublished: "t1", stackCount: 1, cueCount: 1)
        let b = ShowLibraryEntry(slug: "b", name: "B", filename: "B.cuestack", lastPublished: "t2", stackCount: 1, cueCount: 1)
        index.publish(a, at: "t1")
        index.publish(b, at: "t2")
        index.rename(slug: "a", to: "Opening Night", at: "t3")
        var a2 = a; a2.lastPublished = "t4"; a2.stackCount = 5
        index.publish(a2, at: "t4")
        XCTAssertEqual(index.shows.map(\.slug), ["a", "b"])
        XCTAssertEqual(index.shows[0].name, "Opening Night", "republishing keeps the website name")
        XCTAssertEqual(index.shows[0].stackCount, 5)
        XCTAssertEqual(index.current, "a")
        index.remove(slug: "a", at: "t5")
        XCTAssertEqual(index.current, "b", "removing the current show falls back to the next")
    }

    func testPayloadUsesPerStackColumnsAndDropsDuplicateAllCues() throws {
        let payload = WebsitePayload.cueData(cueStacks: stacks(), selectedCueStackIndex: 0, highlightColors: [])
        XCTAssertNil(payload["allCues"])
        let available = try XCTUnwrap(payload["availableCueStacks"] as? [[String: Any]])
        XCTAssertEqual(available.count, 2)
        let second = available[1]
        XCTAssertEqual((second["columns"] as? [[String: Any]])?.map { $0["name"] as? String }, ["#", "Notes"])
        let cue = try XCTUnwrap((second["cues"] as? [[String: Any]])?.first)
        XCTAssertEqual(cue["Notes"] as? String, "Doors")
        XCTAssertEqual(cue["timerValue"] as? String, "1:00")
    }

    // MARK: Publisher

    func testCommitWritesAllFilesInOneCommit() async throws {
        let result = try await publisher().commit([
            .write(path: "cuetocue/a.json", data: Data("A".utf8)),
            .write(path: "cuetocue/b.json", data: Data("B".utf8)),
        ], message: "Publish")
        XCTAssertEqual(FakeGitHub.files["cuetocue/a.json"], Data("A".utf8))
        XCTAssertEqual(FakeGitHub.files["cuetocue/b.json"], Data("B".utf8))
        XCTAssertEqual(FakeGitHub.requests.filter { $0.path.hasSuffix("/git/commits") && $0.method == "POST" }.count, 1, "exactly one commit")
        XCTAssertEqual(result.htmlURL?.absoluteString, "https://github.com/owner/site/commit/\(result.sha)")
        XCTAssertTrue(FakeGitHub.requests.allSatisfy { $0.headers["Authorization"] == "Bearer test-token" })
        XCTAssertFalse(FakeGitHub.requests.contains { $0.method == "PUT" }, "no per-file Contents API writes")
    }

    func testCommitRetriesWhenBranchMoves() async throws {
        FakeGitHub.refConflictsRemaining = 2
        _ = try await publisher().commit([.write(path: "x.json", data: Data("1".utf8))], message: "m")
        XCTAssertEqual(FakeGitHub.files["x.json"], Data("1".utf8))
        XCTAssertEqual(FakeGitHub.requests.filter { $0.path.hasSuffix("/git/ref/heads/main") }.count, 3)
        XCTAssertEqual(FakeGitHub.requests.filter { $0.path.hasSuffix("/git/blobs") }.count, 1, "blobs are uploaded once")
    }

    func testCommitGivesUpAfterThreeConflicts() async {
        FakeGitHub.refConflictsRemaining = 5
        do {
            _ = try await publisher().commit([.write(path: "x.json", data: Data())], message: "m")
            XCTFail("expected conflict")
        } catch {
            XCTAssertEqual(error as? GitHubError, .conflict)
        }
    }

    func testReadFileUsesRawFormatAndReturnsNilWhenMissing() async throws {
        FakeGitHub.files["cuetocue/shows/index.json"] = Data("{}".utf8)
        let data = try await publisher().readFile("cuetocue/shows/index.json")
        XCTAssertEqual(data, Data("{}".utf8))
        XCTAssertEqual(FakeGitHub.requests.last?.headers["Accept"], "application/vnd.github.raw+json",
                       "raw format works for files of any size (the default format stops at 1 MB)")
        let missing = try await publisher().readFile("cuetocue/nope.json")
        XCTAssertNil(missing)
    }

    func testErrorsAreReadable() async {
        FakeGitHub.forcedStatus = ("/user", 401, [:], "Bad credentials")
        do { _ = try await publisher().validate(); XCTFail() } catch {
            XCTAssertEqual(error as? GitHubError, .unauthorized("Bad credentials"))
            XCTAssertTrue(error.localizedDescription.contains("new token"))
        }
        FakeGitHub.forcedStatus = ("/user", 403, ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "2000000000"], "API rate limit exceeded")
        do { _ = try await publisher().validate(); XCTFail() } catch {
            XCTAssertEqual(error as? GitHubError, .rateLimited(resetAt: Date(timeIntervalSince1970: 2_000_000_000)))
        }
        FakeGitHub.forcedStatus = ("/repos/owner/site", 404, [:], "Not Found")
        do { _ = try await publisher().validate(); XCTFail() } catch {
            XCTAssertEqual(error as? GitHubError, .notFound("Repository owner/site"))
        }
    }

    // MARK: Manager

    func testPublishWritesCurrentShowAndLibraryInOneCommit() async throws {
        // Another show is already in the library (e.g. published from another Mac).
        var existing = ShowLibraryIndex()
        existing.publish(ShowLibraryEntry(slug: "nyc-keynote", name: "NYC Keynote", filename: "NYC Keynote.cuestack",
                                          lastPublished: "2026-09-01T00:00:00Z", stackCount: 3, cueCount: 40), at: "2026-09-01T00:00:00Z")
        FakeGitHub.files[WebsitePayload.libraryIndexPath] = try existing.encoded()

        let manager = manager()
        let result = await manager.publish(cueStacks: stacks(3), selectedCueStackIndex: 1, highlightColors: [], filename: "WT_LHR_26_Fall.cuestack")
        if case .failure(let error) = result { return XCTFail(error.localizedDescription) }

        XCTAssertEqual(FakeGitHub.requests.filter { $0.path.hasSuffix("/git/commits") && $0.method == "POST" }.count, 1)
        let data = try json(WebsitePayload.dataPath)
        XCTAssertEqual((data["availableCueStacks"] as? [Any])?.count, 3)
        let metadata = try json(WebsitePayload.metadataPath)
        XCTAssertEqual(metadata["filename"] as? String, "WT_LHR_26_Fall.cuestack")
        XCTAssertEqual(metadata["totalCueStacks"] as? Int, 3)
        XCTAssertEqual(metadata["showSlug"] as? String, "wt-lhr-26-fall")
        XCTAssertEqual(FakeGitHub.files[WebsitePayload.showPath("wt-lhr-26-fall")], FakeGitHub.files[WebsitePayload.dataPath],
                       "the library copy matches the current data")

        let library = ShowLibraryIndex.decode(FakeGitHub.files[WebsitePayload.libraryIndexPath])
        XCTAssertEqual(library.current, "wt-lhr-26-fall")
        XCTAssertEqual(library.shows.map(\.slug), ["wt-lhr-26-fall", "nyc-keynote"], "existing shows are kept")
        XCTAssertEqual(library.shows[0].cueCount, 6)

        XCTAssertEqual(manager.syncStatus, .success)
        XCTAssertEqual(manager.lastSyncFilename, "WT_LHR_26_Fall.cuestack")
        XCTAssertEqual(defaults.string(forKey: WebsiteSyncSettingsKeys.lastPublishedFile), "WT_LHR_26_Fall.cuestack")
        XCTAssertNotNil(manager.lastCommitURL)
    }

    func testPublishWithoutTokenExplainsWhatToDo() async {
        let manager = manager(token: nil)
        let result = await manager.publish(cueStacks: stacks(), selectedCueStackIndex: 0, highlightColors: [], filename: "Show.cuestack")
        guard case .failure(let error) = result else { return XCTFail() }
        XCTAssertEqual(error as? GitHubError, .notConfigured)
        XCTAssertEqual(manager.connection, .notConfigured)
        XCTAssertTrue(FakeGitHub.requests.isEmpty)
    }

    func testRemoveAndRenameShows() async throws {
        let manager = manager()
        _ = await manager.publish(cueStacks: stacks(), selectedCueStackIndex: 0, highlightColors: [], filename: "Old Show.cuestack")
        _ = await manager.publish(cueStacks: stacks(), selectedCueStackIndex: 0, highlightColors: [], filename: "New Show.cuestack")

        do {
            try await manager.removeShow(slug: "new-show")
            XCTFail("the current show can't be removed")
        } catch {}

        try await manager.renameShow(slug: "old-show", to: "Opening Night")
        XCTAssertEqual(ShowLibraryIndex.decode(FakeGitHub.files[WebsitePayload.libraryIndexPath]).shows.first { $0.slug == "old-show" }?.name, "Opening Night")

        try await manager.removeShow(slug: "old-show")
        XCTAssertNil(FakeGitHub.files[WebsitePayload.showPath("old-show")])
        XCTAssertEqual(ShowLibraryIndex.decode(FakeGitHub.files[WebsitePayload.libraryIndexPath]).shows.map(\.slug), ["new-show"])
        XCTAssertNotNil(FakeGitHub.files[WebsitePayload.showPath("new-show")])
    }

    func testConnectionCheckLoadsLibrary() async throws {
        var existing = ShowLibraryIndex()
        existing.publish(ShowLibraryEntry(slug: "s", name: "S", filename: "S.cuestack", lastPublished: "t", stackCount: 1, cueCount: 1), at: "t")
        FakeGitHub.files[WebsitePayload.libraryIndexPath] = try existing.encoded()
        let manager = manager()
        await manager.checkConnection()
        XCTAssertEqual(manager.connection, .connected(login: "stage-manager"))
        XCTAssertEqual(manager.library.shows.map(\.slug), ["s"])
    }

    // MARK: Token storage

    func testLegacyPlainTextTokenIsCopiedToSecureStore() {
        defaults.set("ghp_legacy", forKey: WebsiteSyncSettingsKeys.githubToken)
        let store = InMemoryGitHubTokenStore()
        let manager = WebsiteSyncManager(defaults: defaults, tokenStore: store)
        XCTAssertEqual(store.readToken(), "ghp_legacy")
        XCTAssertTrue(manager.hasToken)
        XCTAssertTrue(manager.hasLegacyPlainTextToken, "kept until the user removes it (older app copies read it)")
        manager.removeLegacyPlainTextToken()
        XCTAssertNil(defaults.string(forKey: WebsiteSyncSettingsKeys.githubToken))
        XCTAssertTrue(manager.hasToken)
    }

    func testExistingKeychainTokenIsNotOverwrittenByLegacyCopy() {
        defaults.set("ghp_old", forKey: WebsiteSyncSettingsKeys.githubToken)
        let store = InMemoryGitHubTokenStore(token: "ghp_current")
        _ = WebsiteSyncManager(defaults: defaults, tokenStore: store)
        XCTAssertEqual(store.readToken(), "ghp_current")
    }

    func testSettingAndClearingToken() throws {
        let store = InMemoryGitHubTokenStore()
        let manager = WebsiteSyncManager(defaults: defaults, tokenStore: store)
        XCTAssertEqual(manager.connection, .notConfigured)
        try manager.setToken("  ghp_new \n")
        XCTAssertEqual(store.readToken(), "ghp_new")
        XCTAssertEqual(manager.connection, .unknown)
        try manager.setToken("")
        XCTAssertNil(store.readToken())
        XCTAssertEqual(manager.connection, .notConfigured)
    }
}
