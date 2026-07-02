//
//  BackupManager.swift
//  Cue to Cue
//
//  Phase 3 of the file-safety audit.
//
//  After every successful write through `DocumentStore.save`, the verified
//  bytes are written to two backup destinations:
//
//  Desktop — ~/Desktop/Cue to Cue Backups/<stem>.backup.<ext>
//      One latest copy per document, replaced after every successful save.
//      Easy to find on the Desktop.
//
//  Library — ~/Library/Application Support/Cue to Cue/Backups/<stem>.backup.<ext>
//      One latest copy per document in Cue to Cue's backup library.
//      Survives if you move or rename the document file.
//
//  Older sibling/history backups next to documents are no longer created,
//  but remain discoverable for restore.
//
//      - Atomic write (`Data.WritingOptions = [.atomic]`).
//      - NSFileCoordinator-coordinated writes.
//      - Encode-once. The exact bytes that just verified for the main
//        file are what get written to every tier — we never re-encode and
//        risk divergence.
//      - Refuse to write empty/seed payloads. Hard guard at the entry
//        point.
//      - Post-write decode verification. If verification fails for a
//        backup, the *previous* file in that tier is preserved.
//      - Background queue. Backup work never blocks Cmd+S.
//

import Foundation
import CryptoKit

final class BackupManager: @unchecked Sendable {

    static let shared = BackupManager()

    enum BackupError: LocalizedError {
        case empty
        case writeFailed(tier: String, underlying: Error)
        case verifyFailed(tier: String, underlying: Error)
        case collision(existingPath: String)
        case appSupportUnavailable
        case noMainFile

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Refusing to write a backup of an empty document."
            case .writeFailed(let tier, let e):
                return "Backup tier \(tier) failed to write: \(e.localizedDescription)"
            case .verifyFailed(let tier, let e):
                return "Backup tier \(tier) verification failed after write: \(e.localizedDescription)"
            case .collision(let path):
                return "A non-Cue to Cue file already exists at \(path); skipping that backup tier."
            case .appSupportUnavailable:
                return "Application Support directory is unavailable."
            case .noMainFile:
                return "Main file URL is missing; backup tiers that depend on the main file location were skipped."
            }
        }
    }

    /// Per-tier outcome of a fan-out.
    struct TierResult {
        let tier: String
        let url: URL?
        let succeeded: Bool
        let error: BackupError?
    }

    /// Aggregate report returned to the UI after every save.
    struct Report {
        let writtenCount: Int
        let totalCount: Int
        let tiers: [TierResult]
        var hasFailures: Bool { tiers.contains { !$0.succeeded } }
    }

    /// Discoverable backup snapshot, used by the Restore from Backup… sheet.
    struct Snapshot: Identifiable, Hashable {
        let id: URL
        let url: URL
        let tierLabel: String
        let date: Date
        let byteCount: Int64
        /// `true` when the file decodes cleanly as `SavedData`. Computed lazily.
        let isValid: Bool
        /// `true` when the file's sha256 matches the Tier 4 manifest entry,
        /// or `nil` if the tier doesn't have a manifest (Tiers 2 / 3).
        let manifestVerified: Bool?

        static func == (lhs: Snapshot, rhs: Snapshot) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// Manifest entry for Tier 4. Stored as JSON next to the snapshots.
    struct ManifestEntry: Codable {
        let filename: String
        let sha256: String
        let byteCount: Int64
        let timestamp: Date
    }

    private struct Manifest: Codable {
        var entries: [ManifestEntry]
    }

    // MARK: - Tunables

    /// Folder on the Desktop that holds the latest backup for each document.
    var desktopBackupFolderName: String = "Cue to Cue Backups"

    /// Folder name suffix for legacy sibling history folders (restore only).
    var siblingHistoryFolderSuffix: String = "backups"

    // MARK: - Dependencies

    private let fileManager = FileManager.default
    private let coordinator = NSFileCoordinator(filePresenter: nil)
    private let queue = DispatchQueue(label: "com.cuetocue.backups", qos: .utility)

    private init() {}

    // MARK: - Public entry point

    /// Fan out `verifiedData` (the exact bytes that already verified for the
    /// main file) to every backup tier. Runs on the background queue and
    /// reports back via `completion` on the main queue.
    ///
    /// - Parameters:
    ///   - verifiedData: bytes that just round-tripped for the main file.
    ///   - mainFileURL: the URL the main save targeted.
    ///   - savedData: the in-memory model. Used only for the empty-payload
    ///     guard; the bytes are what gets written.
    ///   - completion: fired on the main queue with the aggregate report.
    func fanOut(verifiedData: Data,
                mainFileURL: URL,
                savedData: SavedData,
                completion: @escaping (Report) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let report = self.fanOutSync(verifiedData: verifiedData, mainFileURL: mainFileURL, savedData: savedData)
            DispatchQueue.main.async { completion(report) }
        }
    }

    /// Synchronous fan-out, used by `fanOut` and reachable directly for tests.
    func fanOutSync(verifiedData: Data,
                    mainFileURL: URL,
                    savedData: SavedData) -> Report {
        var results: [TierResult] = []

        // Hard refusal: never write a backup of an empty document. This is
        // the same trap that, combined with the autosave bug, caused the
        // original data loss. Belt-and-braces: DocumentStore.save also
        // refuses, but BackupManager checks independently.
        if savedData.cueStacks.isEmpty {
            results.append(TierResult(tier: "Desktop", url: nil, succeeded: false, error: .empty))
            results.append(TierResult(tier: "Library", url: nil, succeeded: false, error: .empty))
            return Report(writtenCount: 0, totalCount: results.count, tiers: results)
        }

        results.append(writeDesktopBackup(verifiedData: verifiedData, mainFileURL: mainFileURL))
        results.append(writeLibraryBackup(verifiedData: verifiedData, mainFileURL: mainFileURL))

        let written = results.filter { $0.succeeded }.count
        return Report(writtenCount: written, totalCount: results.count, tiers: results)
    }

    // MARK: - Desktop backup

    private func writeDesktopBackup(verifiedData: Data, mainFileURL: URL) -> TierResult {
        let tier = "Desktop"
        do {
            let dst = try desktopBackupURL(for: mainFileURL)
            try ensureDirectory(dst.deletingLastPathComponent())
            let safeDst = safeReplacementURL(for: dst, mainFileURL: mainFileURL)
            try writeAtomicCoordinated(verifiedData, to: safeDst)
            try verifyDecodes(at: safeDst)
            return TierResult(tier: tier, url: safeDst, succeeded: true, error: nil)
        } catch let e as BackupError {
            return TierResult(tier: tier, url: nil, succeeded: false, error: e)
        } catch {
            return TierResult(tier: tier, url: nil, succeeded: false, error: .writeFailed(tier: tier, underlying: error))
        }
    }

    // MARK: - Library backup

    private func writeLibraryBackup(verifiedData: Data, mainFileURL: URL) -> TierResult {
        let tier = "Library"
        do {
            let dir = try appSupportBackupsDirectory()
            let dst = libraryBackupURL(for: mainFileURL, in: dir)
            try ensureDirectory(dir)
            try writeAtomicCoordinated(verifiedData, to: dst)
            try verifyDecodes(at: dst)
            updateManifest(in: dir, addingFile: dst, data: verifiedData)
            return TierResult(tier: tier, url: dst, succeeded: true, error: nil)
        } catch let e as BackupError {
            return TierResult(tier: tier, url: nil, succeeded: false, error: e)
        } catch {
            return TierResult(tier: tier, url: nil, succeeded: false, error: .writeFailed(tier: tier, underlying: error))
        }
    }

    private func safeReplacementURL(for dst: URL, mainFileURL: URL) -> URL {
        if fileManager.fileExists(atPath: dst.path) {
            if let data = try? Data(contentsOf: dst),
               (try? JSONDecoder().decode(SavedData.self, from: data)) != nil {
                return dst
            }
            let parent = dst.deletingLastPathComponent()
            let stem = mainFileURL.deletingPathExtension().lastPathComponent
            let ext = backupPayloadExtension(for: mainFileURL)
            let alt = nextNonCollidingURL(stem: "\(stem) Backup", extension: ext, in: parent)
            NSLog("BackupManager: \(dst.path) exists but is not a Cue to Cue backup; using \(alt.path) instead.")
            return alt
        }
        return dst
    }

    // Legacy tier writers removed — sibling and sibling-history backups are no longer created.

    // MARK: - Manifest

    private func manifestURL(in dir: URL) -> URL {
        dir.appendingPathComponent("Manifest.json")
    }

    private func loadManifest(in dir: URL) -> Manifest {
        let url = manifestURL(in: dir)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return Manifest(entries: [])
        }
        return manifest
    }

    private func writeManifest(_ manifest: Manifest, in dir: URL) {
        let url = manifestURL(in: dir)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(manifest)
            // Manifest is itself written atomically + coordinated.
            try writeAtomicCoordinated(data, to: url)
        } catch {
            NSLog("BackupManager: failed to write Manifest.json at \(url.path): \(error.localizedDescription)")
        }
    }

    private func updateManifest(in dir: URL, addingFile fileURL: URL, data: Data) {
        var manifest = loadManifest(in: dir)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let entry = ManifestEntry(
            filename: fileURL.lastPathComponent,
            sha256: hex,
            byteCount: Int64(data.count),
            timestamp: Date()
        )
        manifest.entries.removeAll { $0.filename == entry.filename }
        manifest.entries.append(entry)
        writeManifest(manifest, in: dir)
    }

    private func removeManifestEntry(in dir: URL, fileURL: URL) {
        var manifest = loadManifest(in: dir)
        let before = manifest.entries.count
        manifest.entries.removeAll { $0.filename == fileURL.lastPathComponent }
        if manifest.entries.count != before {
            writeManifest(manifest, in: dir)
        }
    }

    // MARK: - Public discovery (Restore from Backup… sheet)

    /// Returns every available backup snapshot for `mainFileURL`, across
    /// every tier, sorted newest first. Each snapshot includes a quick
    /// validity check (decodes as SavedData) and, where possible, a
    /// manifest verification.
    ///
    /// Safe to call on any thread; does I/O so callers should keep it off
    /// the main queue when listing many files.
    func discoverSnapshots(forMainFile mainFileURL: URL?) -> [Snapshot] {
        var out: [Snapshot] = []

        if let mainURL = mainFileURL {
            let stem = safeDocumentStem(for: mainURL)

            if let desktopURL = try? desktopBackupURL(for: mainURL),
               fileManager.fileExists(atPath: desktopURL.path) {
                out.append(makeSnapshot(at: desktopURL, tierLabel: "Desktop Backup", manifestDir: nil))
            }

            if let libraryRoot = try? appSupportBackupsDirectory() {
                let libraryURL = libraryBackupURL(for: mainURL, in: libraryRoot)
                if fileManager.fileExists(atPath: libraryURL.path) {
                    out.append(makeSnapshot(at: libraryURL, tierLabel: "Application Support", manifestDir: libraryRoot))
                }

                let legacyDir = libraryRoot.appendingPathComponent(stem, isDirectory: true)
                if fileManager.fileExists(atPath: legacyDir.path) {
                    out.append(contentsOf: listSnapshots(in: legacyDir, tierLabel: "Application Support (older)", manifestDir: legacyDir))
                }
            }

            // Legacy backups next to the document (no longer created).
            let parent = mainURL.deletingLastPathComponent()
            for sibling in siblingBackupURLs(for: mainURL) where fileManager.fileExists(atPath: sibling.path) {
                out.append(makeSnapshot(at: sibling, tierLabel: "Legacy — next to file", manifestDir: nil))
            }
            let historyDir = parent.appendingPathComponent("\(stem).\(siblingHistoryFolderSuffix)", isDirectory: true)
            if fileManager.fileExists(atPath: historyDir.path) {
                out.append(contentsOf: listSnapshots(in: historyDir, tierLabel: "Legacy — nearby history", manifestDir: nil))
            }
        }

        return out.sorted { $0.date > $1.date }
    }

    /// Convenience: snapshots for *any* document in Application Support
    /// (used when the user has no main file open and wants to find a
    /// backup of a file they remember saving).
    func discoverAllAppSupportSnapshots() -> [Snapshot] {
        var out: [Snapshot] = []
        guard let root = try? appSupportBackupsDirectory(),
              let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return out
        }

        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if isDirectory {
                let label = "App Support — \(entry.lastPathComponent)"
                out.append(contentsOf: listSnapshots(in: entry, tierLabel: label, manifestDir: entry))
            } else if isBackupSnapshotFile(entry) {
                out.append(makeSnapshot(at: entry, tierLabel: "Application Support", manifestDir: root))
            }
        }
        return out.sorted { $0.date > $1.date }
    }

    private func listSnapshots(in dir: URL, tierLabel: String, manifestDir: URL?) -> [Snapshot] {
        guard let urls = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        let manifest = manifestDir.map { loadManifest(in: $0) }
        return urls
            .filter(isBackupSnapshotFile)
            .map { url in
                makeSnapshot(at: url, tierLabel: tierLabel, manifest: manifest)
            }
    }

    private func makeSnapshot(at url: URL, tierLabel: String, manifestDir: URL?) -> Snapshot {
        let manifest = manifestDir.map { loadManifest(in: $0) }
        return makeSnapshot(at: url, tierLabel: tierLabel, manifest: manifest)
    }

    private func makeSnapshot(at url: URL, tierLabel: String, manifest: Manifest?) -> Snapshot {
        let attrs = (try? fileManager.attributesOfItem(atPath: url.path)) ?? [:]
        let date = (attrs[.modificationDate] as? Date) ?? Date.distantPast
        let size: Int64
        if let n = attrs[.size] as? NSNumber { size = n.int64Value }
        else if let i = attrs[.size] as? Int64 { size = i }
        else if let i = attrs[.size] as? Int { size = Int64(i) }
        else { size = 0 }

        let data = (try? Data(contentsOf: url)) ?? Data()
        let isValid = (try? JSONDecoder().decode(SavedData.self, from: data)) != nil

        var manifestVerified: Bool? = nil
        if let manifest, let entry = manifest.entries.first(where: { $0.filename == url.lastPathComponent }) {
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            manifestVerified = (hex == entry.sha256 && Int64(data.count) == entry.byteCount)
        }

        return Snapshot(
            id: url,
            url: url,
            tierLabel: tierLabel,
            date: date,
            byteCount: size,
            isValid: isValid,
            manifestVerified: manifestVerified
        )
    }

    // MARK: - Reveal helpers

    /// Best directory to reveal in Finder for the current document.
    /// Order of preference: sibling history dir → app support dir → app support root.
    func revealableBackupURL(forMainFile mainFileURL: URL?) -> URL? {
        if let desktop = try? desktopBackupsDirectory(),
           fileManager.fileExists(atPath: desktop.path) {
            return desktop
        }
        if let mainURL = mainFileURL,
           let libraryRoot = try? appSupportBackupsDirectory() {
            let libraryURL = libraryBackupURL(for: mainURL, in: libraryRoot)
            if fileManager.fileExists(atPath: libraryURL.path) {
                return libraryURL
            }
            let stem = safeDocumentStem(for: mainURL)
            let legacyDir = libraryRoot.appendingPathComponent(stem, isDirectory: true)
            if fileManager.fileExists(atPath: legacyDir.path) {
                return legacyDir
            }
        }
        return try? appSupportBackupsDirectory()
    }

    // MARK: - Internals: write + verify

    private func writeAtomicCoordinated(_ data: Data, to url: URL) throws {
        var coordinatorError: NSError?
        var thrown: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { coordinatedURL in
            do {
                // If a read-only previous version is in the way, we have to
                // re-grant write before atomic rename can replace it.
                if fileManager.fileExists(atPath: coordinatedURL.path) {
                    applyReadWrite(to: coordinatedURL)
                }
                try data.write(to: coordinatedURL, options: [.atomic])
            } catch {
                thrown = error
            }
        }
        if let error = thrown {
            throw BackupError.writeFailed(tier: "*", underlying: error)
        }
        if let coordError = coordinatorError {
            throw BackupError.writeFailed(tier: "*", underlying: coordError)
        }
    }

    private func verifyDecodes(at url: URL) throws {
        do {
            let data = try Data(contentsOf: url)
            _ = try JSONDecoder().decode(SavedData.self, from: data)
        } catch {
            throw BackupError.verifyFailed(tier: "*", underlying: error)
        }
    }

    // MARK: - Internals: file mode

    private func applyReadWrite(to url: URL) {
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: UInt16(0o644))]
        try? fileManager.setAttributes(attrs, ofItemAtPath: url.path)
    }

    // MARK: - Internals: directories + paths

    private func safeDocumentStem(for mainFileURL: URL) -> String {
        let stem = mainFileURL.deletingPathExtension().lastPathComponent
        return stem.isEmpty ? "_Untitled" : stem
    }

    /// `~/Desktop/Cue to Cue Backups/`
    func desktopBackupsDirectory() throws -> URL {
        let desktop = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        let dir = desktop.appendingPathComponent(desktopBackupFolderName, isDirectory: true)
        try ensureDirectory(dir)
        return dir
    }

    func desktopBackupURL(for mainFileURL: URL) throws -> URL {
        let dir = try desktopBackupsDirectory()
        return libraryBackupURL(for: mainFileURL, in: dir)
    }

    func libraryBackupURL(for mainFileURL: URL, in dir: URL) -> URL {
        let stem = safeDocumentStem(for: mainFileURL)
        let ext = backupPayloadExtension(for: mainFileURL)
        return dir.appendingPathComponent("\(stem).backup.\(ext)")
    }

    /// Backup file extension mirrors the main document (.cuestack or .json).
    private func backupPayloadExtension(for mainFileURL: URL) -> String {
        let ext = mainFileURL.pathExtension.lowercased()
        return ext.isEmpty ? "json" : ext
    }

    /// Tier 2 sibling backup for the main file's format.
    private func siblingBackupURL(for mainFileURL: URL) -> URL {
        let parent = mainFileURL.deletingLastPathComponent()
        let stem = mainFileURL.deletingPathExtension().lastPathComponent
        let ext = backupPayloadExtension(for: mainFileURL)
        return parent.appendingPathComponent("\(stem).backup.\(ext)")
    }

    /// Sibling backup paths to check (includes legacy `.backup.json` when the
    /// main file is `.cuestack`).
    private func siblingBackupURLs(for mainFileURL: URL) -> [URL] {
        var urls = [siblingBackupURL(for: mainFileURL)]
        if backupPayloadExtension(for: mainFileURL) == "cuestack" {
            let parent = mainFileURL.deletingLastPathComponent()
            let stem = mainFileURL.deletingPathExtension().lastPathComponent
            let legacy = parent.appendingPathComponent("\(stem).backup.json")
            if legacy != urls[0] {
                urls.append(legacy)
            }
        }
        return urls
    }

    private func isBackupSnapshotFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "json" || ext == "cuestack" else { return false }
        return url.lastPathComponent != "Manifest.json"
    }

    /// `~/Library/Application Support/Cue to Cue/Backups/`
    func appSupportBackupsDirectory() throws -> URL {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw BackupError.appSupportUnavailable
        }
        let dir = base.appendingPathComponent("Cue to Cue", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        try ensureDirectory(dir)
        return dir
    }

    @discardableResult
    private func ensureDirectory(_ url: URL) throws -> URL {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private func nextNonCollidingURL(stem: String, extension ext: String, in dir: URL) -> URL {
        var candidate = dir.appendingPathComponent("\(stem).\(ext)")
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem) \(counter).\(ext)")
            counter += 1
            if counter > 1000 { break }
        }
        return candidate
    }
}

// MARK: - Restore UI helpers

extension BackupManager.Snapshot {
    var displayFileName: String { url.lastPathComponent }

    var shortenedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home + "/") {
            return "~/" + url.path.dropFirst(home.count + 1)
        }
        return url.path
    }

    var shortenedFolderPath: String {
        let folder = url.deletingLastPathComponent()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if folder.path.hasPrefix(home + "/") {
            return "~/" + folder.path.dropFirst(home.count + 1)
        }
        return folder.path
    }

    var locationTitle: String {
        switch tierLabel {
        case "Desktop Backup":
            return "Desktop backup folder"
        case "Application Support", "Application Support (older)":
            return "App backup library"
        case "Legacy — next to file":
            return "Legacy — next to file"
        case "Legacy — nearby history":
            return "Legacy — nearby history"
        default:
            if tierLabel.hasPrefix("App Support —") {
                return "App backup library (older)"
            }
            return tierLabel
        }
    }

    var locationExplanation: String {
        switch tierLabel {
        case "Desktop Backup":
            return "Latest copy in ~/Desktop/Cue to Cue Backups/. Replaced each time you save."
        case "Application Support":
            return "Latest copy in Cue to Cue's backup library under ~/Library/Application Support/. Kept even if you move the document."
        case "Application Support (older)":
            return "Older timestamped copy from a previous backup scheme. Kept for restore only."
        case "Legacy — next to file":
            return "Older backup saved next to your document. Cue to Cue no longer writes these."
        case "Legacy — nearby history":
            return "Older backups from a .backups folder next to your document. Cue to Cue no longer writes these."
        default:
            if tierLabel.hasPrefix("App Support —") {
                let documentName = tierLabel.replacingOccurrences(of: "App Support — ", with: "")
                return "Older backup library folder for «\(documentName)»."
            }
            return "Backup file saved on disk."
        }
    }
}
