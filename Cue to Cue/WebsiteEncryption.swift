//
//  WebsiteEncryption.swift
//  Cue to Cue
//
//  The website is a public GitHub Pages site, so anything published there can
//  be downloaded by anyone. Show files are therefore encrypted with the viewer
//  password before they are uploaded; the viewer page decrypts them in the
//  browser after the password is entered.
//
//  Format (the viewer page, cuetocue/site-lock.js, reads the same thing):
//
//    cuetocue/site-key.json  (not secret)
//      { "version": 1, "kdf": "PBKDF2-SHA256", "iterations": 600000,
//        "salt": base64, "check": Envelope }
//
//    any encrypted file
//      { "encrypted": Envelope }
//
//    Envelope = { "version": 1, "iv": base64 (12 bytes),
//                 "data": base64 (AES-256-GCM ciphertext followed by its 16-byte tag) }
//
//  The key is PBKDF2-SHA256(password, salt, iterations), 32 bytes. "check"
//  encrypts a fixed string so a wrong password is detected immediately.
//

import Foundation
import CryptoKit
import CommonCrypto

enum WebsiteEncryptionError: LocalizedError, Equatable {
    case wrongPassword
    case corruptFile
    case keyDerivationFailed

    var errorDescription: String? {
        switch self {
        case .wrongPassword:
            return "The viewer password doesn't match the one the website was locked with."
        case .corruptFile:
            return "An encrypted file on the website couldn't be read."
        case .keyDerivationFailed:
            return "Couldn't prepare the encryption key."
        }
    }
}

struct WebsiteEnvelope: Codable, Equatable {
    var version: Int = 1
    var iv: String
    var data: String
}

struct WebsiteSiteKey: Codable, Equatable {
    var version: Int = 1
    var kdf: String = "PBKDF2-SHA256"
    var iterations: Int
    var salt: String
    var check: WebsiteEnvelope
}

private struct EncryptedFile: Codable {
    var encrypted: WebsiteEnvelope
}

/// Encrypts and decrypts website files with a key derived from the viewer password.
struct WebsiteCipher {
    static let sitePath = "cuetocue/site-key.json"
    static let defaultIterations = 600_000
    private static let checkPlaintext = Data("cuetocue-site-key-v1".utf8)

    let siteKey: WebsiteSiteKey
    private let key: SymmetricKey

    /// Open an existing site. Throws `.wrongPassword` if the password doesn't match.
    init(password: String, siteKey: WebsiteSiteKey) throws {
        guard let salt = Data(base64Encoded: siteKey.salt), siteKey.iterations > 0 else {
            throw WebsiteEncryptionError.corruptFile
        }
        let key = try Self.deriveKey(password: password, salt: salt, iterations: siteKey.iterations)
        guard let check = try? Self.open(siteKey.check, key: key), check == Self.checkPlaintext else {
            throw WebsiteEncryptionError.wrongPassword
        }
        self.key = key
        self.siteKey = siteKey
    }

    /// Lock a site with a new password (fresh random salt).
    static func create(password: String, iterations: Int = defaultIterations) throws -> WebsiteCipher {
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw WebsiteEncryptionError.keyDerivationFailed }
        let key = try deriveKey(password: password, salt: salt, iterations: iterations)
        let siteKey = WebsiteSiteKey(iterations: iterations, salt: salt.base64EncodedString(),
                                     check: try seal(checkPlaintext, key: key))
        return try WebsiteCipher(password: password, siteKey: siteKey)
    }

    static func decodeSiteKey(_ data: Data?) -> WebsiteSiteKey? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(WebsiteSiteKey.self, from: data)
    }

    func siteKeyData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(siteKey)
    }

    /// Encrypt a file's contents into the `{ "encrypted": … }` wrapper.
    func seal(_ plaintext: Data) throws -> Data {
        try JSONEncoder().encode(EncryptedFile(encrypted: Self.seal(plaintext, key: key)))
    }

    /// Decrypt a file. Files that aren't encrypted (written by older builds)
    /// are returned unchanged.
    func open(_ file: Data) throws -> Data {
        guard let wrapper = try? JSONDecoder().decode(EncryptedFile.self, from: file) else { return file }
        do {
            return try Self.open(wrapper.encrypted, key: key)
        } catch {
            throw WebsiteEncryptionError.wrongPassword
        }
    }

    static func isEncrypted(_ file: Data) -> Bool {
        (try? JSONDecoder().decode(EncryptedFile.self, from: file)) != nil
    }

    // MARK: - Primitives

    private static func seal(_ plaintext: Data, key: SymmetricKey) throws -> WebsiteEnvelope {
        let box = try AES.GCM.seal(plaintext, using: key)
        return WebsiteEnvelope(iv: Data(box.nonce).base64EncodedString(),
                               data: (box.ciphertext + box.tag).base64EncodedString())
    }

    private static func open(_ envelope: WebsiteEnvelope, key: SymmetricKey) throws -> Data {
        guard let iv = Data(base64Encoded: envelope.iv),
              let combined = Data(base64Encoded: envelope.data), combined.count >= 16 else {
            throw WebsiteEncryptionError.corruptFile
        }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv),
                                        ciphertext: combined.dropLast(16),
                                        tag: combined.suffix(16))
        return try AES.GCM.open(box, using: key)
    }

    private static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw WebsiteEncryptionError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }
}
