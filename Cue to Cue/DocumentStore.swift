//
//  DocumentStore.swift
//  Cue to Cue
//
//  Phase 1 of the file-safety audit:
//  - All writes are atomic (write-to-temp + rename onto target).
//  - All reads/writes go through NSFileCoordinator so iCloud Drive,
//    Dropbox/OneDrive, Spotlight and other readers see one coherent state.
//  - Before every overwrite we copy the prior on-disk version into
//    ~/Library/Application Support/Cue to Cue/Backups/<filename-stem>/<timestamp>.json
//    Retention: most recent 50 snapshots + the earliest snapshot of each of
//    the past 30 days.
//  - After every write we re-read and re-decode the file. If verification
//    fails we surface a typed error instead of silently declaring success.
//  - When there is no current file picked, callers can route to a Recovery
//    directory inside Application Support instead of NSTemporaryDirectory.
//

import Foundation

extension Notification.Name {
    /// Posted on the main queue after `DocumentStore.save(...)` finishes its
    /// asynchronous backup fan-out. The notification's `object` is a
    /// `BackupManager.Report`. Phase 3.
    static let documentStoreBackupsCompleted = Notification.Name("documentStoreBackupsCompleted")
}

final class DocumentStore {

    static let shared = DocumentStore()

    enum DocumentStoreError: LocalizedError {
        case appSupportUnavailable
        case backupFailed(underlying: Error)
        case verificationFailed(underlying: Error)
        case writeFailed(underlying: Error)
        case readFailed(underlying: Error)
        case decodeFailed(underlying: Error)
        case encodeFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .appSupportUnavailable:
                return "Application Support directory is unavailable."
            case .backupFailed(let e):
                return "Failed to back up the previous version of the file: \(e.localizedDescription)"
            case .verificationFailed(let e):
                return "The file was written but could not be re-decoded afterwards. The previous version is preserved in Application Support → Cue to Cue → Backups. (\(e.localizedDescription))"
            case .writeFailed(let e):
                return "Could not write the file: \(e.localizedDescription)"
            case .readFailed(let e):
                return "Could not read the file: \(e.localizedDescription)"
            case .decodeFailed(let e):
                return "The file could not be decoded as a Cue to Cue document: \(e.localizedDescription)"
            case .encodeFailed(let e):
                return "The current document could not be encoded for saving: \(e.localizedDescription)"
            }
        }
    }

    /// Result of a successful save.
    struct SaveResult {
        let savedAt: Date
        let url: URL
        let backedUpTo: URL?
        /// File modification date *after* our successful write. Use this to
        /// re-arm external-change detection without falsely flagging our own
        /// write as a conflict.
        let modificationDate: Date
        /// File size in bytes after our successful write.
        let fileSize: Int64
        /// Phase 3: outcome of the multi-tier backup fan-out. Nil only if
        /// the caller chose to skip backups (rare). When non-nil, callers
        /// can read `report.hasFailures` to decide whether to surface a
        /// degraded-backup warning to the UI.
        var backups: BackupManager.Report? = nil
    }

    /// Result of a successful load. The mtime/size let callers compare on
    /// later saves and detect external modifications.
    struct LoadResult {
        let savedData: SavedData
        let url: URL
        let modificationDate: Date
        let fileSize: Int64
    }

    /// On-disk identity of a document URL. Used to detect external changes.
    struct DiskState: Codable, Equatable {
        var modificationDate: Date
        var fileSize: Int64
    }

    /// Timestamp of the most recent write performed by this DocumentStore.
    /// FileWatcher filters out filesystem events that occur within a short
    /// window of this so it doesn't false-positive on our own saves.
    private(set) var lastSelfWriteAt: Date = .distantPast

    /// Window during which a filesystem event after our own write is treated
    /// as our own change (and therefore not a conflict). 2 s is generous
    /// enough to swallow iCloud follow-up events caused by our save.
    var selfWriteSettleWindow: TimeInterval = 2.0

    func wasRecentlySelfWritten(within window: TimeInterval? = nil) -> Bool {
        Date().timeIntervalSince(lastSelfWriteAt) < (window ?? selfWriteSettleWindow)
    }

    // MARK: - Dependencies

    private let fileManager = FileManager.default
    private let coordinator = NSFileCoordinator(filePresenter: nil)

    // MARK: - Formatters

    /// UTC, file-name-safe timestamp (e.g. "2026-06-04_17-46-32").
    private let backupTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private init() {}

    // MARK: - Public API: Save

    /// Atomically save `savedData` to `url`, backing up the previous on-disk
    /// version into Application Support first, then verifying the result.
    @discardableResult
    func save(_ savedData: SavedData, to url: URL) throws -> SaveResult {
        // Phase 3: hard refusal. Never write a save with empty cueStacks —
        // this is the trap that, combined with the autosave bug, caused the
        // original data loss. BackupManager has its own independent guard
        // for defense in depth.
        if savedData.cueStacks.isEmpty {
            throw DocumentStoreError.encodeFailed(underlying: NSError(
                domain: "DocumentStore",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Refusing to save: the document has no cue stacks. This protects you from accidentally overwriting a real file with seed/test data."]
            ))
        }

        // Pre-arm the self-write filter BEFORE the write begins. Atomic
        // writes work by writing to a sibling temp file then renaming it
        // onto the target, which causes the kernel to fire .rename/.delete
        // events on any file-descriptor-based watcher pointed at the old
        // inode. Those events can be delivered while we are still inside
        // `data.write(...)` and before we have a chance to record the
        // post-write mtime; arming the filter at this point ensures
        // FileWatcher recognises them as our own work.
        lastSelfWriteAt = Date()

        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(savedData)
        } catch {
            throw DocumentStoreError.encodeFailed(underlying: error)
        }

        var coordinatorError: NSError?
        var thrown: Error?
        var savedAt: Date = Date()
        var backupURL: URL?

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { coordinatedURL in
            do {
                // 1) Snapshot the existing on-disk file (if any) BEFORE we touch it.
                if fileManager.fileExists(atPath: coordinatedURL.path) {
                    do {
                        backupURL = try snapshotExistingFile(at: coordinatedURL)
                    } catch {
                        // Backup failure is logged but does not block the save.
                        // We do not want to be unable to save just because the
                        // backup directory is full or unwritable.
                        NSLog("DocumentStore: backup snapshot failed for \(coordinatedURL.path): \(error.localizedDescription)")
                    }
                }

                // 2) Atomic write. `.atomic` writes to a sibling temp file and renames.
                do {
                    try data.write(to: coordinatedURL, options: [.atomic])
                } catch {
                    throw DocumentStoreError.writeFailed(underlying: error)
                }

                // 3) Verify by re-reading + re-decoding. If this fails, the
                // previous version is still in Backups for recovery.
                do {
                    let verifyData = try Data(contentsOf: coordinatedURL)
                    _ = try JSONDecoder().decode(SavedData.self, from: verifyData)
                } catch {
                    throw DocumentStoreError.verificationFailed(underlying: error)
                }

                savedAt = Date()

                // 4) Rotate retention.
                rotateBackups(forFilename: coordinatedURL.lastPathComponent)
            } catch {
                thrown = error
            }
        }

        if let error = thrown {
            throw error
        }
        if let coordError = coordinatorError {
            throw DocumentStoreError.writeFailed(underlying: coordError)
        }

        // Record the post-write mtime/size so callers can re-arm external-change
        // detection. If we can't read attributes we fall back to `savedAt` and 0
        // size so the rest of the flow still proceeds.
        let postWriteState = (try? diskState(for: url)) ?? DiskState(modificationDate: savedAt, fileSize: 0)
        lastSelfWriteAt = postWriteState.modificationDate

        if url.pathExtension.lowercased() == "cuestack" {
            CueStackDocumentType.repairContentTypeIfNeeded(at: url)
        }

        // Phase 3: fan out the *exact verified bytes* to every backup tier.
        // Runs on a background queue inside BackupManager so the user's
        // Cmd-S round trip is not held up by sibling/history writes. The
        // report is delivered via NotificationCenter so any UI surface
        // (the title-bar status pill, the warning banner, etc.) can react.
        BackupManager.shared.fanOut(verifiedData: data, mainFileURL: url, savedData: savedData) { report in
            NotificationCenter.default.post(name: .documentStoreBackupsCompleted, object: report)
            if report.hasFailures {
                let failed = report.tiers.filter { !$0.succeeded }.map { $0.tier }.joined(separator: ", ")
                NSLog("DocumentStore: backup tiers degraded: \(failed)")
            }
        }

        return SaveResult(
            savedAt: savedAt,
            url: url,
            backedUpTo: backupURL,
            modificationDate: postWriteState.modificationDate,
            fileSize: postWriteState.fileSize,
            backups: nil
        )
    }

    /// Save into the Recovery directory (Application Support / Cue to Cue / Recovery).
    /// Used by autosave when no document URL is selected, so the user's work is
    /// never written into NSTemporaryDirectory.
    @discardableResult
    func saveRecovery(_ savedData: SavedData, suggestedStem: String? = nil) throws -> SaveResult {
        let dir = try recoveryDirectory()
        let stem = (suggestedStem?.isEmpty == false ? suggestedStem! : "Untitled")
        let stamp = backupTimestampFormatter.string(from: Date())
        let url = dir.appendingPathComponent("\(stem)-\(stamp).json")
        return try save(savedData, to: url)
    }

    // MARK: - Public API: Load

    /// Read and decode `SavedData` from `url`, coordinated. Returns the decoded
    /// data plus the on-disk mtime/size as observed inside the coordinated read,
    /// so callers can compare against future state to detect external changes.
    func loadResult(from url: URL) throws -> LoadResult {
        var coordinatorError: NSError?
        var thrown: Error?
        var result: LoadResult?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            do {
                let data = try Data(contentsOf: coordinatedURL)
                do {
                    let saved = try JSONDecoder().decode(SavedData.self, from: data)
                    let state = (try? diskState(for: coordinatedURL)) ?? DiskState(modificationDate: Date(), fileSize: Int64(data.count))
                    result = LoadResult(
                        savedData: saved,
                        url: coordinatedURL,
                        modificationDate: state.modificationDate,
                        fileSize: state.fileSize
                    )
                } catch {
                    thrown = DocumentStoreError.decodeFailed(underlying: error)
                }
            } catch let error as DocumentStoreError {
                thrown = error
            } catch {
                thrown = DocumentStoreError.readFailed(underlying: error)
            }
        }

        if let error = thrown {
            throw error
        }
        if let coordError = coordinatorError {
            throw DocumentStoreError.readFailed(underlying: coordError)
        }
        guard let r = result else {
            throw DocumentStoreError.readFailed(underlying: NSError(domain: "DocumentStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty result from coordinated read."]))
        }
        return r
    }

    /// Convenience for callers that only need the decoded `SavedData`.
    func load(from url: URL) throws -> SavedData {
        try loadResult(from: url).savedData
    }

    // MARK: - Disk state

    /// Returns the modification date + file size for `url`, suitable for
    /// external-change detection. Throws if the file does not exist or the
    /// attributes can't be read.
    func diskState(for url: URL) throws -> DiskState {
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let date = (attrs[.modificationDate] as? Date) ?? Date()
        let size: Int64
        if let n = attrs[.size] as? NSNumber {
            size = n.int64Value
        } else if let i = attrs[.size] as? Int64 {
            size = i
        } else if let i = attrs[.size] as? Int {
            size = Int64(i)
        } else {
            size = 0
        }
        return DiskState(modificationDate: date, fileSize: size)
    }

    /// Returns true if the on-disk state of `url` differs from `last`. Treats
    /// "file missing" as a change. A change in *only* mtime with identical
    /// size is treated as a change (size+mtime together are the cheap signal;
    /// callers can cross-check with content if they want).
    func diskStateChanged(at url: URL, since last: DiskState?) -> Bool {
        guard let last else { return false }
        do {
            let now = try diskState(for: url)
            if now.fileSize != last.fileSize { return true }
            // Compare mtime to nearest second; APFS stores nanosecond resolution
            // but iCloud sometimes round-trips dates with sub-second jitter.
            let lhs = floor(now.modificationDate.timeIntervalSince1970)
            let rhs = floor(last.modificationDate.timeIntervalSince1970)
            return lhs != rhs
        } catch {
            return true
        }
    }

    // MARK: - Bookmarks

    /// Save a bookmark for `url` under `key` in `UserDefaults`. The app is
    /// currently unsandboxed, so we use a non-security-scoped bookmark; if the
    /// app is sandboxed later, switch the options to `[.withSecurityScope]`.
    func saveBookmark(for url: URL, key: String = "LastDocumentBookmark") throws {
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Resolve a previously-saved bookmark. Returns `nil` if no bookmark is
    /// stored. Throws if the bookmark exists but cannot be resolved.
    /// `isStale == true` means the OS resolved the URL but recommends we save a
    /// fresh bookmark on next access; we do that automatically.
    func resolveBookmark(key: String = "LastDocumentBookmark") throws -> (url: URL, isStale: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        if isStale {
            // Best-effort refresh; ignore errors — caller still gets a valid URL.
            try? saveBookmark(for: url, key: key)
        }
        return (url, isStale)
    }

    func clearBookmark(key: String = "LastDocumentBookmark") {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Migrate a legacy `UserDefaults["LastSavedURL"]` value (plain URL, no
    /// rename tracking) into a bookmark. Safe to call on every launch.
    func migrateLegacyLastSavedURLIfNeeded() {
        let legacyKey = "LastSavedURL"
        // If we already have a bookmark, do nothing.
        if UserDefaults.standard.data(forKey: "LastDocumentBookmark") != nil {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return
        }
        if let url = UserDefaults.standard.url(forKey: legacyKey) {
            // Only migrate if the file still exists; otherwise let the
            // missing-file flow handle it.
            if fileManager.fileExists(atPath: url.path) {
                try? saveBookmark(for: url)
            }
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }

    // MARK: - Disk-state persistence

    private let diskStateDefaultsKey = "LastDocumentDiskState"

    /// Persist the last-observed on-disk state for the current document so we
    /// can detect external modifications across launches.
    func recordDiskState(_ state: DiskState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: diskStateDefaultsKey)
    }

    /// Load the last-observed disk state, or `nil` if we have none.
    func loadRecordedDiskState() -> DiskState? {
        guard let data = UserDefaults.standard.data(forKey: diskStateDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(DiskState.self, from: data)
    }

    func clearRecordedDiskState() {
        UserDefaults.standard.removeObject(forKey: diskStateDefaultsKey)
    }

    // MARK: - Directories

    /// `~/Library/Application Support/Cue to Cue/`
    func appSupportRoot() throws -> URL {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DocumentStoreError.appSupportUnavailable
        }
        let dir = base.appendingPathComponent("Cue to Cue", isDirectory: true)
        try ensureDirectory(dir)
        return dir
    }

    /// `<appSupport>/Backups/`
    func backupRoot() throws -> URL {
        try ensureDirectory(appSupportRoot().appendingPathComponent("Backups", isDirectory: true))
    }

    /// `<appSupport>/Recovery/`
    func recoveryDirectory() throws -> URL {
        try ensureDirectory(appSupportRoot().appendingPathComponent("Recovery", isDirectory: true))
    }

    /// `<appSupport>/Backups/<stem>/`
    func backupDirectory(forFilename filename: String) -> URL {
        let stem = (filename as NSString).deletingPathExtension
        let safeStem = stem.isEmpty ? "_Untitled" : stem
        let base = (try? backupRoot()) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent(safeStem, isDirectory: true)
        _ = try? ensureDirectory(dir)
        return dir
    }

    /// Returns the contents of the backup directory for `filename`, sorted
    /// newest first. Useful for a future "Browse backups…" UI.
    func listBackups(forFilename filename: String) -> [(url: URL, date: Date)] {
        let dir = backupDirectory(forFilename: filename)
        guard let urls = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        let withDates: [(url: URL, date: Date)] = urls.compactMap { u in
            let values = try? u.resourceValues(forKeys: [.contentModificationDateKey])
            guard let date = values?.contentModificationDate else { return nil }
            return (u, date)
        }
        return withDates.sorted { $0.date > $1.date }
    }

    // MARK: - Private helpers

    @discardableResult
    private func ensureDirectory(_ url: URL) throws -> URL {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// Copy the file currently at `url` into Backups/<stem>/<timestamp>.<ext>
    /// and return the destination URL.
    @discardableResult
    private func snapshotExistingFile(at url: URL) throws -> URL {
        let dir = backupDirectory(forFilename: url.lastPathComponent)
        try ensureDirectory(dir)
        let stamp = backupTimestampFormatter.string(from: Date())
        let ext = url.pathExtension.isEmpty ? "json" : url.pathExtension
        var dst = dir.appendingPathComponent("\(stamp).\(ext)")

        // In the unlikely case of a same-second collision, append a counter.
        var counter = 1
        while fileManager.fileExists(atPath: dst.path) {
            dst = dir.appendingPathComponent("\(stamp)-\(counter).\(ext)")
            counter += 1
            if counter > 50 { break }
        }
        do {
            try fileManager.copyItem(at: url, to: dst)
            return dst
        } catch {
            throw DocumentStoreError.backupFailed(underlying: error)
        }
    }

    /// Retention policy: keep the most recent 50 snapshots, plus the earliest
    /// snapshot of each calendar day for the last 30 days.
    private func rotateBackups(forFilename filename: String) {
        let dir = backupDirectory(forFilename: filename)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        guard let urls = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return
        }

        let withDates: [(url: URL, date: Date)] = urls.compactMap { u in
            let values = try? u.resourceValues(forKeys: [.contentModificationDateKey])
            guard let date = values?.contentModificationDate else { return nil }
            return (u, date)
        }
        let sortedNewestFirst = withDates.sorted { $0.date > $1.date }

        // Keep the 50 most recent.
        let recent = Set(sortedNewestFirst.prefix(50).map { $0.url })

        // Keep the earliest snapshot of each of the last 30 calendar days.
        let calendar = Calendar(identifier: .gregorian)
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
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

        let keep = recent.union(dailyKept)
        for entry in sortedNewestFirst where !keep.contains(entry.url) {
            try? fileManager.removeItem(at: entry.url)
        }
    }
}
