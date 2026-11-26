//
//  AuthenticationTests.swift
//  Cue to CueTests
//
//  LAN account security: no default accounts, salted password hashes with
//  legacy upgrade, default-password warnings, password changes, lockout,
//  and that account changes are actually saved. Uses a temp folder, never
//  the real ~/Documents/auth_data.json.
//

import XCTest
import CryptoKit
@testable import Cue_to_Cue

@MainActor
final class AuthenticationTests: XCTestCase {

    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("CueToCueAuthTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeManager() -> AuthenticationManager {
        AuthenticationManager(dataSyncManager: DataSyncManager(), storageDirectory: dir)
    }

    private func legacyHash(_ password: String) -> String {
        SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func writeAuthFile(users: [User]) throws {
        try JSONEncoder().encode(AuthData(users: users)).write(to: dir.appendingPathComponent("auth_data.json"))
    }

    // MARK: Defaults

    func testFreshInstallHasNoAccounts() {
        XCTAssertTrue(makeManager().users.isEmpty, "no admin/admin123 on new installs")
    }

    func testCommonAndShortPasswordsRejected() {
        let auth = makeManager()
        if case .failure(let e) = auth.createUser(username: "admin", password: "admin123", isAdmin: true),
           case .commonPassword = e {} else { XCTFail("admin123 must be refused") }
        if case .failure(let e) = auth.createUser(username: "stage", password: "short"),
           case .weakPassword = e {} else { XCTFail("short password must be refused") }
        XCTAssertTrue(auth.users.isEmpty)
    }

    // MARK: Persistence (used to save the old list)

    func testCreatedAndDeletedUsersAreSaved() throws {
        let auth = makeManager()
        guard case .success(let user) = auth.createUser(username: "stagemgr", password: "correct horse battery") else {
            return XCTFail("create failed")
        }
        XCTAssertEqual(makeManager().users.map(\.username), ["stagemgr"], "new user survives a relaunch")

        _ = auth.createUser(username: "lx-op", password: "another good one", isAdmin: true)
        XCTAssertNoThrow(try auth.deleteUser(user.id).get())
        XCTAssertEqual(makeManager().users.map(\.username), ["lx-op"], "deletion survives a relaunch")
    }

    // MARK: Hashing

    func testNewPasswordsUseSaltedPBKDF2() {
        let a = PasswordHasher.hash("correct horse battery", iterations: 1_000)
        let b = PasswordHasher.hash("correct horse battery", iterations: 1_000)
        XCTAssertTrue(a.hasPrefix("pbkdf2-sha256$1000$"))
        XCTAssertNotEqual(a, b, "salted: same password, different hashes")
        XCTAssertTrue(PasswordHasher.verify("correct horse battery", against: a))
        XCTAssertFalse(PasswordHasher.verify("wrong", against: a))
    }

    func testLegacyHashVerifiesAndIsUpgradedOnLogin() throws {
        try writeAuthFile(users: [User(username: "ops", passwordHash: legacyHash("legacy-pass-1"))])
        let auth = makeManager()
        XCTAssertTrue(auth.users[0].usesLegacyPasswordHash)

        guard case .success = auth.login(username: "ops", password: "legacy-pass-1") else { return XCTFail("login failed") }
        XCTAssertFalse(auth.users[0].usesLegacyPasswordHash)
        let reloaded = makeManager()
        XCTAssertFalse(reloaded.users[0].usesLegacyPasswordHash, "upgrade is saved")
        guard case .success = reloaded.login(username: "ops", password: "legacy-pass-1") else { return XCTFail("upgraded hash must still work") }
    }

    // MARK: Default-password warning and change

    func testOldDefaultAdminIsFlaggedUntilPasswordChanged() throws {
        let admin = User(username: "admin", passwordHash: legacyHash("admin123"), isAdmin: true)
        try writeAuthFile(users: [admin, User(username: "fine", passwordHash: legacyHash("unique-pass-9"))])
        let auth = makeManager()
        XCTAssertEqual(auth.accountsUsingDefaultPassword, [admin.id])

        guard case .success(let login) = auth.login(username: "admin", password: "admin123") else { return XCTFail() }
        XCTAssertEqual(auth.tokens.count, 1)

        if case .failure = auth.changePassword(userId: admin.id, newPassword: "password123") {} else {
            XCTFail("can't change to another default")
        }
        XCTAssertNoThrow(try auth.changePassword(userId: admin.id, newPassword: "venue-specific-pass").get())
        XCTAssertTrue(auth.accountsUsingDefaultPassword.isEmpty)
        XCTAssertTrue(auth.tokens.isEmpty, "signed out everywhere")
        if case .success = auth.validateToken(login.token ?? "") { XCTFail("old session must be revoked") }

        let reloaded = makeManager()
        XCTAssertTrue(reloaded.accountsUsingDefaultPassword.isEmpty)
        if case .success = reloaded.login(username: "admin", password: "admin123") { XCTFail("old password must stop working") }
        guard case .success = reloaded.login(username: "admin", password: "venue-specific-pass") else { return XCTFail() }
    }

    // MARK: Lockout

    func testLockoutAfterRepeatedFailures() {
        let auth = makeManager()
        _ = auth.createUser(username: "audio", password: "right-password-1")
        for _ in 0..<AuthenticationManager.maxFailedLogins {
            if case .success = auth.login(username: "audio", password: "guess") { XCTFail() }
        }
        guard case .failure(let error) = auth.login(username: "AUDIO", password: "right-password-1"),
              case .tooManyAttempts = error else {
            return XCTFail("even the right password is refused while locked out")
        }
        // Other accounts are unaffected.
        _ = auth.createUser(username: "video", password: "right-password-2")
        guard case .success = auth.login(username: "video", password: "right-password-2") else { return XCTFail() }
    }

    func testLANLoginDoesNotChangeMacCurrentUser() {
        let auth = makeManager()
        _ = auth.createUser(username: "viewer", password: "viewer-pass-123")
        _ = auth.login(username: "viewer", password: "viewer-pass-123")
        XCTAssertNil(auth.currentUser, "a browser sign-in must not hide the Mac's Delete button")
    }
}
