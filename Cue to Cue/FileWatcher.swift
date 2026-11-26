//
//  FileWatcher.swift
//  Cue to Cue
//
//  Phase 2 of the file-safety audit.
//
//  Wraps DispatchSource.makeFileSystemObjectSource so that, while the app
//  holds an open document, we get notified when something *outside* the app
//  writes to / renames / deletes that file. The watcher:
//
//   * Filters out events that happened within DocumentStore.shared's
//     self-write settle window so our own saves don't fire conflict alerts.
//   * Debounces noisy event bursts (iCloud, editors that rename-on-save).
//   * Auto-stops on .delete or .rename — the parent should react by
//     re-resolving the bookmark and (optionally) restarting a new watcher
//     against the new path.
//

import Foundation

final class FileWatcher {

    /// Reasons the file watcher fires.
    enum Reason: CustomStringConvertible {
        case write
        case rename
        case delete
        case other

        var description: String {
            switch self {
            case .write: return "write"
            case .rename: return "rename"
            case .delete: return "delete"
            case .other: return "other"
            }
        }
    }

    /// URL currently being watched. nil while inactive.
    private(set) var url: URL?

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private let debounceInterval: TimeInterval
    private var pendingWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.cuetocue.filewatcher", qos: .utility)
    private let onChange: (Reason) -> Void
    /// True right after the app's own save, so those events are ignored.
    private let isRecentSelfWrite: () -> Bool

    /// - Parameters:
    ///   - debounceInterval: minimum interval between callbacks; events within
    ///     the interval are coalesced. Default 0.25s.
    ///   - onChange: called on the main thread when a *non-self* change is
    ///     detected. Self-writes (within `DocumentStore.shared.selfWriteSettleWindow`)
    ///     are filtered out and never produce a callback.
    init(debounceInterval: TimeInterval = 0.25,
         isRecentSelfWrite: @escaping () -> Bool = { DocumentStore.shared.wasRecentlySelfWritten() },
         onChange: @escaping (Reason) -> Void) {
        self.debounceInterval = debounceInterval
        self.isRecentSelfWrite = isRecentSelfWrite
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Start watching `url`. If currently watching another URL, stops the
    /// previous watcher first.
    func start(watching url: URL) {
        stop()
        let path = url.path
        let descriptor = open(path, O_EVTONLY)
        guard descriptor != -1 else {
            NSLog("FileWatcher: failed to open \(path) for watching: errno=\(errno)")
            return
        }
        let mask: DispatchSource.FileSystemEvent = [.write, .extend, .attrib, .rename, .delete, .revoke]
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: mask, queue: queue)

        src.setEventHandler { [weak self] in
            guard let self else { return }
            let event = src.data
            let reason: Reason
            if event.contains(.delete) || event.contains(.revoke) {
                reason = .delete
            } else if event.contains(.rename) {
                reason = .rename
            } else if event.contains(.write) || event.contains(.extend) || event.contains(.attrib) {
                reason = .write
            } else {
                reason = .other
            }
            self.handleEvent(reason: reason)
        }

        src.setCancelHandler { [fd = descriptor] in
            if fd != -1 { close(fd) }
        }

        self.url = url
        self.fd = descriptor
        self.source = src
        src.resume()
    }

    /// Stop watching. Safe to call when not watching.
    func stop() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        if let src = source {
            // Cancelling the source triggers the cancel handler which closes the fd.
            src.cancel()
        }
        source = nil
        fd = -1
        url = nil
    }

    // MARK: - Event handling

    private func handleEvent(reason: Reason) {
        // Filter our own writes. We re-check at fire-time too, in case the
        // self-write happens between dispatch and execution.
        if self.isRecentSelfWrite() {
            return
        }

        // Delete + rename: stop self and hand control to the parent. The
        // watched fd no longer corresponds to a useful inode (atomic
        // writes rename a sibling temp file onto the target, which fires
        // these events even though the file at that path is fine).
        //
        // We re-check `wasRecentlySelfWritten` on the main queue right
        // before reporting, because the kernel can deliver the rename
        // event while the writer is still inside `data.write(...)` and
        // hasn't yet bumped `lastSelfWriteAt` to its final value.
        if reason == .delete || reason == .rename {
            let fired = reason
            let watchedPath = self.url?.path
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // 1) Self-write check on main (now that any in-flight save
                //    on main has had a chance to update the timestamp).
                if self.isRecentSelfWrite() {
                    self.stop()
                    return
                }
                // 2) Path-exists check. Atomic writes leave the path with
                //    a perfectly valid file (a different inode). If the
                //    path resolves, this was almost certainly an atomic
                //    replacement, not a deletion — the parent should just
                //    reattach a fresh watcher, not show a "missing file"
                //    sheet.
                if let p = watchedPath, FileManager.default.fileExists(atPath: p) {
                    self.stop()
                    return
                }
                self.onChange(fired)
                self.stop()
            }
            return
        }

        // Debounced write/attrib/extend. Coalesce bursts (iCloud often fires
        // 3+ events for a single overwrite).
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Re-check at fire-time. If we self-wrote during the debounce
            // window, swallow.
            if self.isRecentSelfWrite() {
                return
            }
            DispatchQueue.main.async {
                self.onChange(reason)
            }
        }
        pendingWorkItem = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
