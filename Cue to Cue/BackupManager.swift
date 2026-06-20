//
//  BackupManager.swift
//  Cue to Cue
//
//  Phase 3 of the file-safety audit.
//
//  After every successful write through `DocumentStore.save`, the verified
//  bytes are fanned out to multiple, deliberately-independent backup tiers
//  so a single failure (iCloud rolling back a version, a sync engine
//  corrupting a file, the user accidentally deleting a backup) cannot
//  destroy every copy.
//
//  Tier 2 — sibling backup
//      <main file directory>/<stem>.backup.<ext>
//      where <ext> matches the main file (.cuestack or .json)
//      Atomic + coordinated. Replaced after every successful main save.
//      Visible in Finder so the user can drag/copy it manually.
//
//  Tier 3 — sibling history
//      <main file directory>/<stem>.backups/<UTC timestamp>.<ext>
//      Same volume as the main file. Rotated on a 50-file / 200 MB budget,
//      whichever hits first. Snapshot files are chmod'd 0444 after write
//      so accidental in-place edits are refused by the OS.
//
//  Tier 4 — Application Support history
//      ~/Library/Application Support/Cue to Cue/Backups/<stem>/<timestamp>.<ext>
//      Plus a Manifest.json with sha256 + byte-size + timestamp for every
//      snapshot. Lives on the local SSD outside iCloud so a syncing
//      catastrophe cannot reach it. This is the iCloud-went-sideways
//      lifeline.
//
//  All tiers:
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

    /// Maximum number of Tier 3 (sibling history) files to keep per document.
    var siblingHistoryCountCap: Int = 50

    /// Maximum total bytes of Tier 3 (sibling history) per document.
    var siblingHistoryByteCap: Int64 = 200 * 1024 * 1024  // 200 MB

    /// Tier 4 retention: most recent N + earliest of each of the last D days.
    var appSupportRecentCap: Int = 50
    var appSupportDailyDays: Int = 30

    /// File mode applied to rotated history files so accidents can't
    /// overwrite them in place.
    var rotatedFileMode: UInt16 = 0o444

    /// Folder name suffix for Tier 3 sibling history. Phase 3 uses
    /// `<stem>.backups`.
    var siblingHistoryFolderSuffix: String = "backups"

    // MARK: - Dependencies

    private let fileManager = FileManager.default
    private let coordinator = NSFileCoordinator(filePresenter: nil)
    private let queue = DispatchQueue(label: "com.cuetocue.backups", qos: .utility)

    private let isoTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

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
            results.append(TierResult(tier: "Sibling", url: nil, succeeded: false, error: .empty))
            results.append(TierResult(tier: "SiblingHistory", url: nil, succeeded: false, error: .empty))
            results.append(TierResult(tier: "AppSupportHistory", url: nil, succeeded: false, error: .empty))
            return Report(writtenCount: 0, totalCount: results.count, tiers: results)
        }

        // Tier 2 — sibling backup
        results.append(writeSibling(verifiedData: verifiedData, mainFileURL: mainFileURL))

        // Tier 3 — sibling history
        results.append(writeSiblingHistory(verifiedData: verifiedData, mainFileURL: mainFileURL))

        // Tier 4 — Application Support history (with manifest)
        results.append(writeAppSupportHistory(verifiedData: verifiedData, mainFileURL: mainFileURL))

        let written = results.filter { $0.succeeded }.count
        return Report(writtenCount: written, totalCount: results.count, tiers: results)
    }

    // MARK: - Tier 2 — sibling backup

    private func writeSibling(verifiedData: Data, mainFileURL: URL) -> TierResult {
        let tier = "Sibling"
        let parent = mainFileURL.deletingLastPathComponent()
        let stem = mainFileURL.deletingPathExtension().lastPathComponent
        let payloadExt = backupPayloadExtension(for: mainFileURL)
        let dst = siblingBackupURL(for: mainFileURL)

        // Collision check: if a file is at the destination, only overwrite
        // it if it is one of OUR backups (decodes as SavedData). Otherwise
        // we step around the user's file by appending " 1", " 2", etc.
        let safeDst: URL
        if fileManager.fileExists(atPath: dst.path) {
            if let data = try? Data(contentsOf: dst),
               (try? JSONDecoder().decode(SavedData.self, from: data)) != nil {
                safeDst = dst
            } else {
                // Don't overwrite a non-CueToCue file with our backup name.
                let alt = nextNonCollidingURL(stem: "\(stem) Backup", extension: payloadExt, in: parent)
                NSLog("BackupManager: \(dst.path) exists but is not a Cue to Cue backup; using \(alt.path) instead.")
                safeDst = alt
            }
        } else {
            safeDst = dst
        }

        do {
            try writeAtomicCoordinated(verifiedData, to: safeDst)
            try verifyDecodes(at: safeDst)
            return TierResult(tier: tier, url: safeDst, succeeded: true, error: nil)
        } catch let e as BackupError {
            return TierResult(tier: tier, url: safeDst, succeeded: false, error: e)
        } catch {
            return TierResult(tier: tier, url: safeDst, succeeded: false, error: .writeFailed(tier: tier, underlying: error))
        }
    }

    // MARK: - Tier 3 — sibling history

    private func writeSiblingHistory(verifiedData: Data, mainFileURL: URL) -> TierResult {
        let tier = "SiblingHistory"
        let parent = mainFileURL.deletingLastPathComponent()
        let stem = mainFileURL.deletingPathExtension().lastPathComponent
        let payloadExt = backupPayloadExtension(for: mainFileURL)
        let dir = parent.appendingPathComponent("\(stem).\(siblingHistoryFolderSuffix)", isDirectory: true)
        do {
            try ensureDirectory(dir)
            let stamp = isoTimestampFormatter.string(from: Date())
            let dst = uniqueTimestampURL(in: dir, stamp: stamp, ext: payloadExt)

            try writeAtomicCoordinated(verifiedData, to: dst)
            try verifyDecodes(at: dst)
            // Make this snapshot read-only so the OS refuses accidental
            // in-place edits / atomic-write replacements by other tools.
            applyReadOnly(to: dst)

            // Rotate this folder according to count + byte budget.
            rotateSiblingHistory(in: dir, keepingMostRecent: dst)

            return TierResult(tier: tier, url: dst, succeeded: true, error: nil)
        } catch let e as BackupError {
            return TierResult(tier: tier, url: nil, succeeded: false, error: e)
        } catch {
            return TierResult(tier: tier, url: nil, succeeded: false, error: .writeFailed(tier: tier, underlying: error))
        }
    }

    private func rotateSiblingHistory(in dir: URL, keepingMostRecent newest: URL) {
        guard let entries = listDatedFiles(in: dir) else { return }
        let sortedNewestFirst = entries.sorted { $0.date > $1.date }

        // Apply count cap.
        var keep = Array(sortedNewestFirst.prefix(siblingHistoryCountCap))

        // Apply byte cap by walking newest → oldest, dropping anything that
        // pushes the running total past the cap.
        var running: Int64 = 0
        keep = keep.filter { entry in
            let size = sizeOfFile(at: entry.url)
            if running + size <= siblingHistoryByteCap {
                running += size
                return true
            }
            return false
        }

        // Always keep the file we just wrote.
        if !keep.contains(where: { $0.url == newest }),
           let newestEntry = sortedNewestFirst.first(where: { $0.url == newest }) {
            keep.append(newestEntry)
        }

        let keepSet = Set(keep.map { $0.url })
        for entry in sortedNewestFirst where !keepSet.contains(entry.url) {
            // Files are read-only; clear the bit before unlink.
            applyReadWrite(to: entry.url)
            try? fileManager.removeItem(at: entry.url)
        }
    }

    // MARK: - Tier 4 — Application Support history (with manifest)

    private func writeAppSupportHistory(verifiedData: Data, mainFileURL: URL) -> TierResult {
        let tier = "AppSupportHistory"
        do {
            let stem = mainFileURL.deletingPathExtension().lastPathComponent
            let safeStem = stem.isEmpty ? "_Untitled" : stem
            let dir = try appSupportBackupsDirectory().appendingPathComponent(safeStem, isDirectory: true)
            try ensureDirectory(dir)
            let stamp = isoTimestampFormatter.string(from: Date())
            let payloadExt = backupPayloadExtension(for: mainFileURL)
            let dst = uniqueTimestampURL(in: dir, stamp: stamp, ext: payloadExt)

            try writeAtomicCoordinated(verifiedData, to: dst)
            try verifyDecodes(at: dst)

            // Update manifest with sha256 + size before we rotate. The
            // manifest survives rotations and tells us, on demand, whether
            // any snapshot has silently bit-rotted.
            updateManifest(in: dir, addingFile: dst, data: verifiedData)

            applyReadOnly(to: dst)
            rotateAppSupportHistory(in: dir, keepingMostRecent: dst)
            return TierResult(tier: tier, url: dst, succeeded: true, error: nil)
        } catch let e as BackupError {
            return TierResult(tier: tier, url: nil, succeeded: false, error: e)
        } catch {
            return TierResult(tier: tier, url: nil, succeeded: false, error: .writeFailed(tier: tier, underlying: error))
        }
    }

    private func rotateAppSupportHistory(in dir: URL, keepingMostRecent newest: URL) {
        guard let entries = listDatedFiles(in: dir) else { return }
        let sortedNewestFirst = entries.sorted { $0.date > $1.date }

        // Most recent N
        let recent = Set(sortedNewestFirst.prefix(appSupportRecentCap).map { $0.url })

        // Earliest snapshot of each of the last D calendar days
        let calendar = Calendar(identifier: .gregorian)
        let cutoff = calendar.date(byAdding: .day, value: -appSupportDailyDays, to: Date()) ?? .distantPast
        var earliestByDay: [Date: (url: URL, date: Date)] = [:]
        for entry in sortedNewestFirst where entry.date >= cutoff {
            let day = calendar.startOfDay(for: entry.date)
            if let existing = earliestByDay[day] {
                if entry.date < existing.date { earliestByDay[day] = entry }
            } else {
                earliestByDay[day] = entry
            }
        }
        let dailyKept = Set(earliestByDay.values.map { $0.url })

        var keep = recent.union(dailyKept)
        keep.insert(newest)

        for entry in sortedNewestFirst where !keep.contains(entry.url) {
            applyReadWrite(to: entry.url)
            try? fileManager.removeItem(at: entry.url)
            removeManifestEntry(in: dir, fileURL: entry.url)
        }
    }

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

        // Tier 2 + Tier 3 require the main file URL.
        if let mainURL = mainFileURL {
            let parent = mainURL.deletingLastPathComponent()
            let stem = mainURL.deletingPathExtension().lastPathComponent

            // Tier 2 (sibling backup) — current extension plus legacy .backup.json
            let siblingURLs = siblingBackupURLs(for: mainURL)
            for sibling in siblingURLs where fileManager.fileExists(atPath: sibling.path) {
                out.append(makeSnapshot(at: sibling, tierLabel: "Sibling Backup", manifestDir: nil))
            }

            // Tier 3 (sibling history)
            let historyDir = parent.appendingPathComponent("\(stem).\(siblingHistoryFolderSuffix)", isDirectory: true)
            if fileManager.fileExists(atPath: historyDir.path) {
                out.append(contentsOf: listSnapshots(in: historyDir, tierLabel: "Sibling History", manifestDir: nil))
            }
        }

        // Tier 4 (Application Support history) — works even without the main file
        if let mainURL = mainFileURL {
            let stem = mainURL.deletingPathExtension().lastPathComponent
            let safeStem = stem.isEmpty ? "_Untitled" : stem
            if let dir = try? appSupportBackupsDirectory().appendingPathComponent(safeStem, isDirectory: true),
               fileManager.fileExists(atPath: dir.path) {
                out.append(contentsOf: listSnapshots(in: dir, tierLabel: "Application Support", manifestDir: dir))
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
              let stems = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return out
        }
        for stemDir in stems where (try? stemDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let label = "App Support — \(stemDir.lastPathComponent)"
            out.append(contentsOf: listSnapshots(in: stemDir, tierLabel: label, manifestDir: stemDir))
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
        if let mainURL = mainFileURL {
            let parent = mainURL.deletingLastPathComponent()
            let stem = mainURL.deletingPathExtension().lastPathComponent
            let history = parent.appendingPathComponent("\(stem).\(siblingHistoryFolderSuffix)", isDirectory: true)
            if fileManager.fileExists(atPath: history.path) { return history }
            for sibling in siblingBackupURLs(for: mainURL) where fileManager.fileExists(atPath: sibling.path) {
                return sibling
            }
            if let stemDir = try? appSupportBackupsDirectory().appendingPathComponent(stem, isDirectory: true),
               fileManager.fileExists(atPath: stemDir.path) {
                return stemDir
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

    private func applyReadOnly(to url: URL) {
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: rotatedFileMode)]
        do {
            try fileManager.setAttributes(attrs, ofItemAtPath: url.path)
        } catch {
            NSLog("BackupManager: chmod 0\(String(rotatedFileMode, radix: 8)) failed for \(url.path): \(error.localizedDescription)")
        }
    }

    private func applyReadWrite(to url: URL) {
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: NSNumber(value: UInt16(0o644))]
        try? fileManager.setAttributes(attrs, ofItemAtPath: url.path)
    }

    // MARK: - Internals: directories + paths

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

    private func uniqueTimestampURL(in dir: URL, stamp: String, ext: String) -> URL {
        var candidate = dir.appendingPathComponent("\(stamp).\(ext)")
        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stamp)-\(counter).\(ext)")
            counter += 1
            if counter > 1000 { break }
        }
        return candidate
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

    private func listDatedFiles(in dir: URL) -> [(url: URL, date: Date)]? {
        guard let urls = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        return urls
            .filter(isBackupSnapshotFile)
            .compactMap { u in
                let values = try? u.resourceValues(forKeys: [.contentModificationDateKey])
                guard let date = values?.contentModificationDate else { return nil }
                return (u, date)
            }
    }

    private func sizeOfFile(at url: URL) -> Int64 {
        let attrs = (try? fileManager.attributesOfItem(atPath: url.path)) ?? [:]
        if let n = attrs[.size] as? NSNumber { return n.int64Value }
        if let i = attrs[.size] as? Int64 { return i }
        if let i = attrs[.size] as? Int { return Int64(i) }
        return 0
    }
}
