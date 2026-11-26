//
//  DocumentController.swift
//  Cue to Cue
//
//  Owns the open show file: new/open/save/save as/duplicate, autosave and
//  recovery, launch-time restore, external-change and missing-file
//  handling, backup restore, the window title, and the quit check.
//
//  This used to be ~750 lines of @State and methods inside ContentView.
//  ContentView now presents the alerts/sheets and forwards menu commands.
//

import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers
import os

/// Save/open diagnostics, readable with:
///   log show --last 10m --predicate 'subsystem == "Cue to Cue" AND category == "Document"'
private let documentLog = Logger(subsystem: "Cue to Cue", category: "Document")

@MainActor
final class DocumentController: ObservableObject {

    // MARK: - Collaborators

    let data: DataSyncManager
    let editor: CueEditorController
    /// File I/O, bookmarks and backups (an isolated store in tests).
    let store: DocumentStore
    /// Set by ContentView (it is an environment object, so not available at init).
    weak var settingsManager: SettingsManager?

    // MARK: - Hooks (set by ContentView)

    /// Called after any change the LAN viewers should see.
    var notifyWebClients: () -> Void = {}
    /// Called after a document has been loaded from disk (website auto-sync).
    var onDocumentLoaded: () -> Void = {}
    /// Called after File > New resets the model (timers, editing UI).
    var onNewDocument: () -> Void = {}

    // MARK: - Document state

    /// Display name, e.g. "Show.cuestack" or "Untitled".
    @Published var fileName: String = "Untitled"
    /// The file Cmd-S and autosave write to. nil for an untitled document.
    @Published var lastSavedURL: URL? {
        didSet {
            guard oldValue != lastSavedURL else { return }
            if let url = lastSavedURL {
                startFileWatcher(at: url)
            } else {
                fileWatcher?.stop()
                fileWatcher = nil
            }
        }
    }
    @Published var pdfNotes: [String: [Int: String]] = [:] {
        didSet { if pdfNotes != oldValue { markDirty() } }
    }
    /// True once a file was opened explicitly (Finder, Open…, New), so the
    /// launch-time "reopen last file" step is skipped.
    @Published var hasExplicitlyOpenedFile = false

    /// True when in-memory state has changed since the last successful save.
    @Published var isDirty = false {
        didSet { if isDirty != oldValue { updateWindowChrome() } }
    }
    @Published var lastSaveDate: Date?
    /// True while loading from disk, so model assignments don't mark dirty.
    @Published var isLoadingFromDisk = false
    /// Where the last autosave of an untitled document went.
    @Published var lastRecoveryURL: URL?

    // MARK: - External changes / alerts

    /// The file changed outside the app since our last save.
    @Published var documentChangedExternally = false
    @Published var showConflictAlert = false
    @Published var showMissingFileAlert = false
    /// URL associated with the conflict / missing-file alert.
    @Published var pendingConflictURL: URL?
    private var fileWatcher: FileWatcher?

    // MARK: - Backups

    @Published var latestBackupReport: BackupManager.Report?
    @Published var showBackupWarning = false
    @Published var backupWarningDetail = ""

    var isOpeningFile = false
    private var cancellables = Set<AnyCancellable>()

    init(data: DataSyncManager, editor: CueEditorController, store: DocumentStore = .shared) {
        self.data = data
        self.editor = editor
        self.store = store

        // Dirty tracking for model changes (cue edits from the Mac or LAN,
        // playlist edits). Loads set isLoadingFromDisk first.
        data.$cueStacks
            .dropFirst()
            .sink { [weak self] _ in self?.markDirty() }
            .store(in: &cancellables)
        data.$countdownPlaylist
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.markDirty() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .documentStoreBackupsCompleted)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in self?.handleBackupReport(note) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .appDelegateDidBecomeActive)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recheckExternalChangesNow() }
            .store(in: &cancellables)
    }

    // MARK: - Naming

    /// File name without the .cuestack / .json extension.
    var fileStem: String {
        // "Show.cuestack (empty — choose Save As…)" after opening an empty file.
        if let range = fileName.range(of: " (empty") {
            return Self.stem(of: String(fileName[..<range.lowerBound]))
        }
        return Self.stem(of: fileName)
    }

    private static func stem(of fileName: String) -> String {
        if fileName.hasSuffix(".cuestack") { return String(fileName.dropLast(9)) }
        if fileName.hasSuffix(".json") { return String(fileName.dropLast(5)) }
        return fileName
    }

    /// Mark the document edited, unless a load is in progress.
    func markDirty() {
        guard !isLoadingFromDisk else { return }
        isDirty = true
    }

    func revealBackupsInFinder() {
        if let url = BackupManager.shared.revealableBackupURL(forMainFile: lastSavedURL) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    /// Cmd-Q / close window: save to the current file, or ask about an
    /// untitled document. `completion(true)` lets the app quit.
    func prepareForQuit(_ completion: @escaping (Bool) -> Void) {
        guard isDirty else {
            completion(true)
            return
        }
        if let url = lastSavedURL {
            // A failed save (or an external-change conflict) shows its own
            // alert; cancel the quit so the user can resolve it.
            completion(saveToURL(url))
            return
        }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to \u{201C}\(fileStem)\u{201D}?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveFileAs(completion: completion)
        case .alertSecondButtonReturn:
            completion(false)
        default:
            completion(true)
        }
    }

    func beginOpeningDocument(at url: URL) {
        guard CueStackDocumentType.shouldOpen(at: url) else { return }

        saveCurrentDocumentIfNeeded(for: .openDocument) { saved in
            guard saved else { return }
            self.loadDocument(from: url)
        }
    }

    func loadDocument(from url: URL) {
        hasExplicitlyOpenedFile = true

        do {
            let savedData = try store.load(from: url)
            applyLoadedData(savedData, from: url, persistAsLastSavedURL: true)
            CueStackDocumentType.repairContentTypeIfNeeded(at: url)
        } catch {
            print("❌ Error reading file: \(error.localizedDescription)")
            self.showOpenError(error: error)
        }
    }

    /// Apply a loaded `SavedData` to the in-memory model without triggering
    /// dirty-marking. If `persistAsLastSavedURL` is true the URL becomes the
    /// autosave/Cmd-S target.
    ///
    /// IMPORTANT: we deliberately do **not** set `lastSavedURL` when the file
    /// decoded to an empty `cueStacks`. That was the trap that caused the
    /// app to point autosave at a user file while keeping seed test data in
    /// memory.
    func applyLoadedData(_ savedData: SavedData, from url: URL, persistAsLastSavedURL: Bool) {
        isLoadingFromDisk = true

        let hasContent = !savedData.cueStacks.isEmpty
        // A different show starts at its first stack with nothing live;
        // reloading the same file (changed on disk) keeps your place.
        let isDifferentFile = lastSavedURL?.standardizedFileURL != url.standardizedFileURL
        if hasContent && isDifferentFile {
            self.data.selectedCueStackIndex = 0
            self.data.selectedCueIndex = -1
            self.data.activeCueIndex = -1
            editor.clearSelection()
        }
        if hasContent {
            // Older builds copied IDs when duplicating/pasting; give every
            // stack, column and cue a unique ID so LAN sync can't hit the
            // wrong row.
            self.data.cueStacks = CueEditing.repairingDuplicateIDs(savedData.cueStacks)
            self.data.selectedCueStackIndex = CueEditing.clampedStackIndex(self.data.selectedCueStackIndex, count: savedData.cueStacks.count)
            let loadedStack = self.data.selectedCueStackIndex
            if self.data.selectedCueIndex >= savedData.cueStacks[loadedStack].cues.count {
                self.data.selectedCueIndex = -1
            }
            print("📂 Loaded \(savedData.cueStacks.count) cue stack(s) from \(url.lastPathComponent)")
        } else {
            print("⚠️ File decoded to empty cueStacks — keeping current in-memory data and NOT pointing autosave at this file.")
        }
        self.settingsManager?.settings.highlightColors = savedData.highlightColors
        self.pdfNotes = savedData.pdfNotes
        self.data.countdownPlaylist = savedData.countdownPlaylist

        if persistAsLastSavedURL && hasContent {
            self.lastSavedURL = url
            self.fileName = url.lastPathComponent
            // Phase 2: bookmark survives renames/moves; the legacy URL key is
            // mirrored for backward compatibility but no longer authoritative.
            try? store.saveBookmark(for: url)
            if let state = try? store.diskState(for: url) {
                store.recordDiskState(state)
                self.lastSaveDate = state.modificationDate
            } else {
                self.lastSaveDate = Date()
            }
        } else if persistAsLastSavedURL && !hasContent {
            // Decoded an empty document. Clear the autosave target so we
            // don't overwrite the file with seed/test data.
            self.lastSavedURL = nil
            self.fileName = url.lastPathComponent + " (empty — choose Save As to keep changes)"
            store.clearBookmark()
            store.clearRecordedDiskState()
        }

        // Loading is the new clean baseline.
        self.documentChangedExternally = false
        self.isDirty = false
        self.lastRecoveryURL = nil

        self.data.syncWebClientWithMacOSApp()
        notifyWebClients()

        // Auto-sync to website etc.
        onDocumentLoaded()

        // Window chrome (modified-dot, title, "Saved at" line).
        updateWindowChrome()

        if hasContent {
            editor.resetHistory()
        }

        // Drop the loading flag on the next runloop tick so all the .onChange
        // observers fire while it is still true.
        DispatchQueue.main.async {
            self.isLoadingFromDisk = false
        }
    }

    // MARK: - File Saving Methods (Phase 1 — atomic + coordinated + backed up)

    /// Build the in-memory document snapshot.
    func currentSavedData() -> SavedData {
        SavedData(
            cueStacks: data.cueStacks,
            highlightColors: (settingsManager?.settings.highlightColors ?? []),
            pdfNotes: pdfNotes,
            countdownPlaylist: data.countdownPlaylist
        )
    }

    /// Cmd-S: save to the current file, or prompt for a location if none.
    func saveFile() {
        if let url = lastSavedURL {
            _ = saveToURL(url)
        } else {
            saveFileAs()
        }
    }

    /// Save any unsaved edits before switching documents (New, Open, etc.).
    /// Calls `completion(true)` when it is safe to proceed, `completion(false)` if
    /// the user cancelled or the save failed.
    enum DocumentSwitchAction {
        case newDocument
        case openDocument

        var blockedTitle: String {
            switch self {
            case .newDocument: return "Can't Create a New Document Yet"
            case .openDocument: return "Can't Open Another File Yet"
            }
        }

        var blockedMessage: String {
            switch self {
            case .newDocument:
                return "Save your changes first. This file was modified outside of Cue to Cue — resolve the conflict, then try again."
            case .openDocument:
                return "Save your changes before opening another file. This file was modified outside of Cue to Cue — resolve the conflict, then try again."
            }
        }
    }

    func saveCurrentDocumentIfNeeded(
        for action: DocumentSwitchAction,
        completion: @escaping (Bool) -> Void
    ) {
        guard isDirty else {
            completion(true)
            return
        }

        if let url = lastSavedURL {
            if saveWouldConflict(at: url) {
                documentChangedExternally = true
                pendingConflictURL = url
                showConflictAlert = true
                showDocumentActionBlockedAlert(
                    messageText: action.blockedTitle,
                    informativeText: action.blockedMessage
                )
                completion(false)
                return
            }
            completion(saveToURL(url))
        } else {
            let context: SaveAsContext = action == .newDocument ? .beforeNewDocument : .beforeOpenDocument
            saveFileAs(completion: completion, context: context)
        }
    }

    /// File → New: save the current document, then reset to a blank document.
    func newFile() {
        saveCurrentDocumentIfNeeded(for: .newDocument) { saved in
            guard saved else { return }
            self.performNewDocument()
        }
    }

    /// File → Duplicate: save the original if needed, copy to a new file, and
    /// continue editing the copy (typical workflow for starting a new event
    /// from last show's cue stack).
    func duplicateFile() {
        prepareOriginalBeforeDuplicate { ready in
            guard ready else { return }
            self.presentDuplicateSavePanel()
        }
    }

    /// If the current document has a file on disk and unsaved edits, save the
    /// original before duplicating so the archived show stays up to date.
    func prepareOriginalBeforeDuplicate(completion: @escaping (Bool) -> Void) {
        guard isDirty, let url = lastSavedURL else {
            completion(true)
            return
        }

        if saveWouldConflict(at: url) {
            documentChangedExternally = true
            pendingConflictURL = url
            showConflictAlert = true
            showDocumentActionBlockedAlert(
                messageText: "Can't Duplicate Yet",
                informativeText: "Save your changes to the original file first. It was modified outside of Cue to Cue — resolve the conflict, then try again."
            )
            completion(false)
            return
        }

        completion(saveToURL(url))
    }

    func presentDuplicateSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = UTType.cueStackReadableTypes
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Duplicate Cue Stack"
        panel.message = "Save a copy under a new name for your next event. The original file stays unchanged."
        panel.nameFieldStringValue = suggestedDuplicateFilename()
        if let url = lastSavedURL {
            panel.directoryURL = url.deletingLastPathComponent()
        }

        guard let window = Self.documentWindow else { return }
        panel.beginSheetModal(for: window) { response in
            documentLog.log("Duplicate panel closed: \(response == .OK ? "Save" : "Cancel", privacy: .public) \(panel.url?.lastPathComponent ?? "-", privacy: .public)")
            guard response == .OK, let url = panel.url else { return }

            if let existing = self.lastSavedURL,
               url.standardizedFileURL == existing.standardizedFileURL {
                self.showDocumentActionBlockedAlert(
                    messageText: "Choose a Different Name",
                    informativeText: "Duplicating requires a new file name so your original show file is preserved."
                )
                return
            }

            if self.saveToURL(url) {
                self.hasExplicitlyOpenedFile = true
                self.editor.resetHistory()
            }
        }
    }

    func suggestedDuplicateFilename() -> String {
        let stem = fileStem.trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.isEmpty || stem == "Untitled" {
            return "Untitled copy.cuestack"
        }
        let lower = stem.lowercased()
        if lower.hasSuffix(" copy") {
            return CueStackDocumentType.defaultSaveFilename(stem: stem)
        }
        return CueStackDocumentType.defaultSaveFilename(stem: "Copy of \(stem)")
    }

    /// Replace in-memory state with a fresh blank document.
    func performNewDocument() {
        let blank = SavedData.blankDocument(highlightColors: (settingsManager?.settings.highlightColors ?? []))
        isLoadingFromDisk = true

        data.cueStacks = blank.cueStacks
        data.selectedCueStackIndex = 0
        data.selectedCueIndex = 0
        data.countdownPlaylist = blank.countdownPlaylist
        pdfNotes = blank.pdfNotes

        editor.clearSelection()

        lastSavedURL = nil
        lastSaveDate = nil
        lastRecoveryURL = nil
        documentChangedExternally = false
        pendingConflictURL = nil
        latestBackupReport = nil
        fileName = "Untitled"
        hasExplicitlyOpenedFile = true

        store.clearBookmark()
        store.clearRecordedDiskState()

        fileWatcher?.stop()
        fileWatcher = nil

        isDirty = false

        onNewDocument()

        editor.resetHistory()
        data.syncWebClientWithMacOSApp()
        notifyWebClients()
        updateWindowChrome()

        DispatchQueue.main.async {
            self.isLoadingFromDisk = false
        }
    }

    func showDocumentActionBlockedAlert(messageText: String, informativeText: String) {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func saveWouldConflict(at url: URL) -> Bool {
        guard url == lastSavedURL,
              FileManager.default.fileExists(atPath: url.path),
              let recorded = store.loadRecordedDiskState() else {
            return false
        }
        return store.diskStateChanged(at: url, since: recorded)
            && !store.wasRecentlySelfWritten()
    }

    /// Save the current document to `url` through DocumentStore (atomic +
    /// coordinated + rotating backup + post-write verification).
    @discardableResult
    func saveToURL(_ url: URL) -> Bool {
        #if DEBUG
        // Snapshot runs open the user's real show; never write it.
        if WindowSnapshotter.isActive { return true }
        #endif
        documentLog.log("Saving \(url.lastPathComponent, privacy: .public) (same file: \(url.standardizedFileURL == self.lastSavedURL?.standardizedFileURL, privacy: .public))")
        if saveWouldConflict(at: url) {
            documentLog.error("Save refused: \(url.lastPathComponent, privacy: .public) changed on disk; showing conflict alert")
            documentChangedExternally = true
            pendingConflictURL = url
            showConflictAlert = true
            print("⚠️ Refusing to save — file was modified outside of Cue to Cue since the last known state. Showing conflict sheet.")
            return false
        }

        do {
            let result = try store.save(currentSavedData(), to: url)
            self.lastSaveDate = result.savedAt
            self.lastSavedURL = url
            self.fileName = url.lastPathComponent
            self.isDirty = false
            self.lastRecoveryURL = nil
            self.documentChangedExternally = false
            self.pendingConflictURL = nil
            try? store.saveBookmark(for: url)
            store.recordDiskState(DocumentStore.DiskState(modificationDate: result.modificationDate, fileSize: result.fileSize))
            print("✅ Saved \(url.lastPathComponent) at \(result.savedAt). Previous version at: \(result.backedUpTo?.path ?? "(no prior file)")")
            documentLog.log("Saved \(url.lastPathComponent, privacy: .public)")
            notifyWebClients()
            updateWindowChrome()
            startFileWatcher(at: url)
            return true
        } catch {
            print("❌ Error saving file: \(error.localizedDescription)")
            documentLog.error("Save failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            showSaveError(error: error)
            return false
        }
    }

    func showSaveError(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Error Saving File"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    enum SaveAsContext {
        case normal
        case beforeNewDocument
        case beforeOpenDocument
    }

    func saveFileAs(completion: ((Bool) -> Void)? = nil, context: SaveAsContext = .normal) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = UTType.cueStackReadableTypes
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save Cue Stack"
        switch context {
        case .normal:
            savePanel.message = "Choose a location to save your cue stack."
        case .beforeNewDocument:
            savePanel.message = "Save your current cue stack before creating a new document."
        case .beforeOpenDocument:
            savePanel.message = "Save your current cue stack before opening another file."
        }
        // Save As is for starting a new version, so suggest a new name next
        // to the current file rather than the same name (which would just
        // ask to replace the file you have open).
        savePanel.nameFieldStringValue = lastSavedURL == nil
            ? CueStackDocumentType.defaultSaveFilename(stem: fileStem)
            : CueStackDocumentType.defaultSaveFilename(stem: "\(fileStem) copy")
        if let url = lastSavedURL {
            savePanel.directoryURL = url.deletingLastPathComponent()
        }
        guard let window = Self.documentWindow else {
            documentLog.error("Save As: no window to attach the panel to")
            completion?(false)
            return
        }
        documentLog.log("Save As panel opened")
        savePanel.beginSheetModal(for: window) { response in
            documentLog.log("Save As panel closed: \(response == .OK ? "Save" : "Cancel", privacy: .public) \(savePanel.url?.lastPathComponent ?? "-", privacy: .public)")
            self.finishSaveAs(chosenURL: response == .OK ? savePanel.url : nil, completion: completion)
        }
    }

    /// What happens after the Save As panel closes. The save must run even
    /// when nobody passed a completion: `completion?(saveToURL(url))` skips
    /// its argument when `completion` is nil, which is how File ▸ Save As…
    /// used to close the panel without saving anything.
    func finishSaveAs(chosenURL: URL?, completion: ((Bool) -> Void)? = nil) {
        guard let url = chosenURL else {
            completion?(false)
            return
        }
        let saved = saveToURL(url)
        completion?(saved)
    }

    /// Compatibility shim — old call sites used `saveDocument(to:)`.
    func saveDocument(to url: URL) {
        saveToURL(url)
    }

    // MARK: - Autosave (Phase 1 — never silently writes to NSTemporaryDirectory)

    func autoSave() {
        #if DEBUG
        if WindowSnapshotter.isActive { return }
        #endif
        // Don't churn disk if nothing has changed.
        guard isDirty else { return }

        if let url = lastSavedURL {
            saveToURL(url)
            print("💾 Autosaved to \(url.path)")
            return
        }

        // No document URL has been chosen. Write to the Recovery directory in
        // Application Support so the user's edits are durable AND visible,
        // never to NSTemporaryDirectory where they would be invisible.
        do {
            let suggestedStem = fileStem.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try store.saveRecovery(currentSavedData(), suggestedStem: suggestedStem.isEmpty ? "Untitled" : suggestedStem)
            self.lastRecoveryURL = result.url
            self.lastSaveDate = result.savedAt
            // Note: we do NOT clear isDirty here — the document still has no
            // permanent home, so we keep the dirty marker on so the user is
            // prompted to Save As before quit.
            print("💾 Autosaved unsaved changes to recovery file: \(result.url.path)")
            updateWindowChrome()
        } catch {
            print("❌ Recovery autosave failed: \(error.localizedDescription)")
        }
    }

    func openFile() {
        guard !isOpeningFile else { return }

        saveCurrentDocumentIfNeeded(for: .openDocument) { saved in
            guard saved else { return }
            self.presentOpenPanel()
        }
    }

    func presentOpenPanel() {
        guard !isOpeningFile else { return }
        isOpeningFile = true

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = UTType.cueStackReadableTypes
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        if let url = lastSavedURL {
            openPanel.directoryURL = url.deletingLastPathComponent()
        }
        openPanel.begin { response in
            self.isOpeningFile = false

            if response == .OK, let url = openPanel.url {
                self.loadDocument(from: url)
            }
        }
    }

    func loadLastFile() {
        // Only load files on app startup, never during runtime
        // This prevents overwriting web changes

        // Skip loading if a file was explicitly opened
        if hasExplicitlyOpenedFile {
            return
        }

        // Whatever happens below, never leave the app with zero cue stacks.
        defer { ensureDocumentHasAStack() }

        store.migrateLegacyLastSavedURLIfNeeded()

        let resolvedURL: URL?
        do {
            resolvedURL = try store.resolveBookmark()?.url
        } catch {
            print("❌ Could not resolve last document bookmark: \(error.localizedDescription)")
            resolvedURL = nil
        }

        guard let lastURL = resolvedURL else {
            return
        }

        guard FileManager.default.fileExists(atPath: lastURL.path) else {
            print("❌ Last saved file no longer exists: \(lastURL.lastPathComponent)")
            // Phase 2: tell the user instead of silently dropping the file
            // reference. They can locate it, save as, or continue without.
            pendingConflictURL = lastURL
            showMissingFileAlert = true
            return
        }

        // If the file changed while the app wasn't running (iCloud, Dropbox,
        // another Mac), the on-disk version is the only version: there are
        // no in-memory edits to conflict with. Just load it. (This used to
        // show the conflict alert, where "Keep My Version" would overwrite
        // the show file with an empty document.)
        if let recorded = store.loadRecordedDiskState(),
           store.diskStateChanged(at: lastURL, since: recorded) {
            print("ℹ️ \(lastURL.lastPathComponent) changed while the app was closed. Loading the newer version.")
        }

        do {
            print("📂 Restoring last document: \(lastURL.lastPathComponent)")
            let result = try store.loadResult(from: lastURL)
            applyLoadedData(result.savedData, from: lastURL, persistAsLastSavedURL: true)
            store.recordDiskState(DocumentStore.DiskState(modificationDate: result.modificationDate, fileSize: result.fileSize))
        } catch {
            print("❌ Error loading last file: \(error.localizedDescription)")
            // Do NOT set lastSavedURL — we don't want autosave to overwrite a
            // file that we just failed to decode. Surface the issue to the
            // user so they can investigate the file or restore a backup.
            showOpenError(error: error)
        }
    }

    /// First launch, a missing last file, or a failed load would otherwise
    /// leave the window with no cue stacks at all. Install a blank stack
    /// without touching the saved-file reference or marking the doc dirty.
    func ensureDocumentHasAStack() {
        guard data.cueStacks.isEmpty else { return }
        isLoadingFromDisk = true
        let blank = SavedData.blankDocument(highlightColors: (settingsManager?.settings.highlightColors ?? []))
        data.cueStacks = blank.cueStacks
        data.selectedCueStackIndex = 0
        data.selectedCueIndex = -1
        editor.resetHistory()
        data.syncWebClientWithMacOSApp()
        DispatchQueue.main.async {
            self.isLoadingFromDisk = false
        }
    }

    func showOpenError(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Error Opening File"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Reveal Backups in Finder")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let backupRoot = try? store.backupRoot() {
                NSWorkspace.shared.activateFileViewerSelecting([backupRoot])
            }
        }
    }

    // MARK: - Window chrome (modified-dot, "Saved at HH:mm:ss")

    /// The cue sheet window: save panels attach to it and its title shows
    /// the file name (not whichever panel or Settings window is in front).
    static var documentWindow: NSWindow? {
        MainWindowCloseInterceptor.mainWindow
            ?? NSApp.mainWindow
            ?? NSApp.keyWindow
            ?? NSApp.windows.first { $0.isVisible }
    }

    func updateWindowChrome() {
        guard let window = Self.documentWindow else { return }
        window.isDocumentEdited = isDirty

        // Title format examples:
        //   "Show — Edited - Cue to Cue 2.1" (version from AppInfo)
        //   "Show — Saved 1:34:06 PM · 3 backups - Cue to Cue 2.1"
        //   "Show — Saved 1:34:06 PM · 2 of 3 backups - Cue to Cue 2.1"
        let stem = fileStem
        var suffix: String
        if isDirty {
            suffix = " — Edited"
        } else if let saved = lastSaveDate {
            let f = DateFormatter()
            f.dateFormat = "h:mm:ss a"
            suffix = " — Saved \(f.string(from: saved))"
            if let report = latestBackupReport {
                if report.hasFailures {
                    suffix += " · \(report.writtenCount) of \(report.totalCount) backups"
                } else {
                    suffix += " · \(report.writtenCount) backups"
                }
            }
        } else {
            suffix = ""
        }
        window.title = "\(stem)\(suffix) - \(AppInfo.nameWithVersion)"
    }

    // MARK: - Phase 2 — file watcher + external-change handlers

    /// Start (or restart) the filesystem watcher pointed at `url`. Safe to
    /// call repeatedly; the watcher stops itself first if already active.
    func startFileWatcher(at url: URL) {
        let store = self.store
        let watcher = FileWatcher(isRecentSelfWrite: { store.wasRecentlySelfWritten() }) { [weak self] reason in
            self?.handleExternalChange(reason: reason)
        }
        watcher.start(watching: url)
        self.fileWatcher = watcher
    }

    /// Called by the watcher (on the main queue) for filesystem events that
    /// were *not* produced by our own writes.
    func handleExternalChange(reason: FileWatcher.Reason) {
        switch reason {
        case .delete, .rename:
            guard let url = lastSavedURL else { return }
            // Defense-in-depth: even though FileWatcher does this check too,
            // re-verify here. Atomic writes (NSFileCoordinator + .atomic)
            // replace the inode at the same path, so an apparent .delete
            // can simply mean "we just saved and the path now points to
            // the fresh file." If our own write window is still warm, OR
            // the path still resolves, treat it as a benign atomic
            // replacement and just reattach the watcher.
            if store.wasRecentlySelfWritten(within: 5.0)
                || FileManager.default.fileExists(atPath: url.path) {
                startFileWatcher(at: url)
                return
            }
            pendingConflictURL = url
            showMissingFileAlert = true
        case .write, .other:
            guard let url = lastSavedURL else { return }
            // Cross-check disk state: if mtime+size still match what we
            // recorded after our last save, this was a noop event (Spotlight,
            // iCloud metadata refresh, etc.) and we ignore it.
            if let recorded = store.loadRecordedDiskState(),
               !store.diskStateChanged(at: url, since: recorded) {
                return
            }
            documentChangedExternally = true
            pendingConflictURL = url
            // Don't auto-pop the alert mid-edit; flag is enough. The next
            // save attempt will pop it. AppDelegate.didBecomeActive will
            // also pop it if the user comes back to the app.
        }
    }

    /// Re-check the on-disk file when we become the active app. This catches
    /// cases where iCloud or another editor changed the file while we were
    /// in the background and the watcher was throttled.
    func recheckExternalChangesNow() {
        guard let url = lastSavedURL else { return }
        // Suppress if our own write was within the settle window.
        if store.wasRecentlySelfWritten() { return }
        // If the file is missing, don't pop the missing-file sheet
        // synchronously — Finder, iCloud, and other tools sometimes briefly
        // unlink + relink during sync. Recheck after a short delay; if it
        // is still gone, *then* surface the sheet.
        if !FileManager.default.fileExists(atPath: url.path) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let stillURL = self.lastSavedURL, stillURL == url else { return }
                if !FileManager.default.fileExists(atPath: stillURL.path),
                   !self.store.wasRecentlySelfWritten(within: 5.0) {
                    self.pendingConflictURL = stillURL
                    self.showMissingFileAlert = true
                }
            }
            return
        }
        if let recorded = store.loadRecordedDiskState(),
           store.diskStateChanged(at: url, since: recorded) {
            documentChangedExternally = true
            pendingConflictURL = url
            showConflictAlert = true
        }
    }

    /// Conflict-sheet action: replace our in-memory state with the on-disk
    /// version.
    func reloadFromDiskAfterConflict() {
        let url = pendingConflictURL ?? lastSavedURL
        guard let url else { return }
        do {
            let result = try store.loadResult(from: url)
            applyLoadedData(result.savedData, from: url, persistAsLastSavedURL: true)
            store.recordDiskState(DocumentStore.DiskState(modificationDate: result.modificationDate, fileSize: result.fileSize))
            documentChangedExternally = false
            pendingConflictURL = nil
        } catch {
            showOpenError(error: error)
        }
    }

    /// Conflict-sheet action: overwrite the on-disk file with our in-memory
    /// version. The disk version is preserved as a backup snapshot by
    /// DocumentStore before the write happens.
    func forceOverwriteAfterConflict() {
        let url = pendingConflictURL ?? lastSavedURL
        guard let url else { return }
        // Never overwrite a show file with an empty document.
        guard !data.cueStacks.isEmpty, url == lastSavedURL else {
            reloadFromDiskAfterConflict()
            return
        }
        do {
            let result = try store.save(currentSavedData(), to: url)
            self.lastSavedURL = url
            self.lastSaveDate = result.savedAt
            self.fileName = url.lastPathComponent
            self.isDirty = false
            self.lastRecoveryURL = nil
            self.documentChangedExternally = false
            self.pendingConflictURL = nil
            try? store.saveBookmark(for: url)
            store.recordDiskState(DocumentStore.DiskState(modificationDate: result.modificationDate, fileSize: result.fileSize))
            notifyWebClients()
            updateWindowChrome()
        } catch {
            showSaveError(error: error)
        }
    }

    /// Missing-file-sheet action: prompt the user to locate the file.
    func locateMissingFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.cueStackReadableTypes
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if let parent = pendingConflictURL?.deletingLastPathComponent() {
            panel.directoryURL = parent
        }
        panel.begin { response in
            self.showMissingFileAlert = false
            if response == .OK, let url = panel.url {
                self.hasExplicitlyOpenedFile = true
                self.beginOpeningDocument(at: url)
            }
            self.pendingConflictURL = nil
        }
    }

    /// Missing-file-sheet action: drop the file reference and continue with
    /// the in-memory state. Future autosaves will go to Recovery.
    func abandonMissingFile() {
        self.lastSavedURL = nil
        store.clearBookmark()
        store.clearRecordedDiskState()
        self.fileName = "Untitled"
        self.pendingConflictURL = nil
        // Mark dirty so the user is reminded to Save As before quitting.
        self.isDirty = true
        updateWindowChrome()
    }

    // MARK: - Phase 3 — Backup status + restore

    /// Receives the asynchronous backup-fan-out report from DocumentStore.
    /// Updates the in-memory status and surfaces a non-blocking warning if
    /// any tier failed.
    func handleBackupReport(_ note: Notification) {
        guard let report = note.object as? BackupManager.Report else { return }
        latestBackupReport = report
        if report.hasFailures {
            let lines = report.tiers
                .filter { !$0.succeeded }
                .map { "• \($0.tier): \($0.error?.localizedDescription ?? "unknown error")" }
            backupWarningDetail = lines.joined(separator: "\n")
            showBackupWarning = true
        }
        updateWindowChrome()
    }

    /// Restore the document from a chosen backup snapshot. To make this
    /// safe even if the user picked the wrong snapshot, the current
    /// in-memory state is first written to a Recovery file. Only after
    /// that succeeds do we load the snapshot.
    func restoreFromBackup(at backupURL: URL) {
        // 1) Snapshot current state to Recovery so this action can never
        //    lose work, even if the user picks the wrong backup.
        let suggestedStem = fileStem.trimmingCharacters(in: .whitespacesAndNewlines)
        let recoveryStem = "PreRestore-" + (suggestedStem.isEmpty ? "Untitled" : suggestedStem)
        // Only attempt the recovery snapshot if the in-memory document is
        // non-empty; DocumentStore refuses empty saves.
        if !data.cueStacks.isEmpty {
            do {
                let r = try store.saveRecovery(currentSavedData(), suggestedStem: recoveryStem)
                self.lastRecoveryURL = r.url
                print("📦 Pre-restore recovery saved at \(r.url.path)")
            } catch {
                NSLog("ContentView: pre-restore recovery save failed: \(error.localizedDescription). Continuing anyway.")
            }
        }

        // 2) Load the chosen backup.
        do {
            let result = try store.loadResult(from: backupURL)
            // Empty-payload guard: refuse to "restore" a backup that has no
            // cue stacks. This prevents the user from clobbering a real
            // document with an empty backup, the same trap that triggered
            // the original data loss.
            if result.savedData.cueStacks.isEmpty {
                let alert = NSAlert()
                alert.messageText = "That backup is empty"
                alert.informativeText = "\(backupURL.lastPathComponent) decoded successfully but contains no cue stacks. Nothing was restored."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
                return
            }
            // 3) If we have a current main file URL, apply the restored
            //    payload in memory and then write it back to the main file
            //    so disk and memory both reflect the restored version.
            //    Otherwise just load it in-memory and let the user Save As.
            if let mainURL = lastSavedURL {
                applyLoadedData(result.savedData, from: mainURL, persistAsLastSavedURL: true)
                // Persist the restored bytes back to the main URL. This
                // also fans out backups, so the restored version becomes
                // the new "latest known good" across all tiers.
                saveToURL(mainURL)
            } else {
                applyLoadedData(result.savedData, from: backupURL, persistAsLastSavedURL: false)
                // Mark dirty so the user is prompted to Save As.
                self.isDirty = true
                self.fileName = "Restored from " + backupURL.lastPathComponent
            }
            updateWindowChrome()
        } catch {
            showOpenError(error: error)
        }
    }
}
