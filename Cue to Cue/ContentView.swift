//
//  ContentView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/12/24.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var dataSyncManager = DataSyncManager()
    @StateObject private var websiteSyncManager = WebsiteSyncManager()
    @StateObject private var timerServer = AuthoritativeTimerServer()
    @State private var currentTime = Date()
    @State private var countdownTime = 300
    @State private var countUpTime = 0
    @State private var countdownRunning = true
    @State private var countUpRunning = false
    @State private var showSettings = false
    @State private var showConnectionMonitor = false
    @State private var showUserManagement = false
    @State private var showPlaylistEditor = false
    @State private var selectedCueTime: Int?
    @State var showSavePanel = false
    @State var showOpenPanel = false
    @State private var isOpeningFile = false
    @State var showImportCSVPanel = false
    @EnvironmentObject var appDelegate: AppDelegate
    @Binding var currentFileName: String

    @State private var scrollViewProxy: ScrollViewProxy?
    @State private var stateHistory: [(columns: [Column], cues: [Cue], timestamp: TimeInterval)] = []
    @State private var currentStateIndex = -1
    @State private var isReorderingCues = false
    @State private var editingCueIndex: Int?
    @State private var cueStackListWidth: CGFloat = 150 // Default width
    @State private var lastSavedURL: URL?
    @State private var keynotePreviewWindow: NSWindow?
    @State private var lastUpdateTime = Date()
    @State var pdfNotes: [String: [Int: String]] = [:]
    @State private var webServer: WebServer?
    @State private var authManager: AuthenticationManager?
    @State private var hasExplicitlyOpenedFile = false // Track if a file was explicitly opened (not from last file)

    // MARK: - Save state (Phase 1: file-safety audit)
    /// True when in-memory state has changed since the last successful save.
    /// Cleared after a successful write through DocumentStore.
    @State private var isDirty: Bool = false
    /// Timestamp of the most recent successful save through DocumentStore.
    @State private var lastSaveDate: Date?
    /// True while we are loading data from disk into the in-memory model.
    /// Used to suppress dirty-marking during loads, since assignments to
    /// dataSyncManager.cueStacks etc. would otherwise look like edits.
    @State private var isLoadingFromDisk: Bool = false
    /// If the most recent autosave had nowhere to go (no file picked) we
    /// route it to ~/Library/Application Support/Cue to Cue/Recovery and
    /// remember the destination so the UI can surface a "recover" prompt.
    @State private var lastRecoveryURL: URL?

    // MARK: - Save state (Phase 2: external-change detection)
    /// Set when the file watcher detects a change made *outside* of our own
    /// writes, OR when an open-time mtime/size comparison shows the file
    /// changed since we last touched it. Surfaced through the conflict alert
    /// and gates writes (we do not silently overwrite a divergent on-disk
    /// version).
    @State private var documentChangedExternally: Bool = false
    /// Drives the "the file changed outside the app" conflict alert.
    @State private var showConflictSheet: Bool = false
    /// Drives the "couldn't find your file" alert when the bookmark resolves
    /// to a path that no longer exists or the watcher reports delete/rename.
    @State private var showMissingFileSheet: Bool = false
    /// URL associated with the missing-file or open-time conflict alert.
    @State private var pendingConflictURL: URL?
    /// Live filesystem watcher for the current document, when one is open.
    /// Held in `@State` so it persists across re-renders of the view struct.
    @State private var fileWatcher: FileWatcher?

    // MARK: - Save state (Phase 3: backup fan-out + Restore sheet)
    /// Latest backup-fan-out report from BackupManager, posted by
    /// DocumentStore after every save. Drives the title-bar status pill and
    /// any "backups degraded" warning.
    @State private var latestBackupReport: BackupManager.Report?
    /// Drives the Restore-from-Backup… sheet.
    @State private var showRestoreSheet: Bool = false
    /// Drives a non-blocking "some backup tiers failed" alert.
    @State private var showBackupWarning: Bool = false
    @State private var backupWarningDetail: String = ""

    // Multi-selection properties
    @State private var selectedCueIndices: Set<Int> = []
    @State private var lastSelectedIndex: Int? = nil
    @State private var isMultiSelectMode: Bool = false

    // MARK: - Print Settings State
    @State private var showPrintSheet = false
    @State private var printSelectedCueStackIndices: Set<Int> = []  // indices of cueStacks to print
    @State private var printFontSize: CGFloat = 12

    public init(currentFileName: Binding<String>) {
        self._currentFileName = currentFileName
    }

    private var currentFileStem: String {
        let name = currentFileName
        if name.hasSuffix(".cuestack") {
            return String(name.dropLast(9))
        }
        if name.hasSuffix(".json") {
            return String(name.dropLast(5))
        }
        return name
    }

    private var displayFileName: String {
        currentFileStem
    }

    // Computed binding to the currently selected cue stack
    private var selectedCueStackBinding: Binding<CueStack> {
        Binding(
            get: {
                let stacks = dataSyncManager.cueStacks
                let index = dataSyncManager.selectedCueStackIndex
                guard stacks.indices.contains(index) else {
                    return CueStack(name: "Invalid", cues: [], columns: [])
                }
                return stacks[index]
            },
            set: { newValue in
                let stacks = dataSyncManager.cueStacks
                let index = dataSyncManager.selectedCueStackIndex
                guard stacks.indices.contains(index) else { return }
                dataSyncManager.cueStacks[index] = newValue
            }
        )
    }
    
    // Computed property to convert selectedCueIndex from Int to Int?
    private var selectedCueIndexBinding: Binding<Int?> {
        Binding(
            get: { dataSyncManager.selectedCueIndex >= 0 ? dataSyncManager.selectedCueIndex : nil },
            set: { newValue in
                dataSyncManager.selectedCueIndex = newValue ?? -1
            }
        )
    }

    var body: some View {
        mainContentView
            .sheet(isPresented: $showSettings) {
                SettingsView(settingsManager: settingsManager)
            }
            .sheet(isPresented: $showConnectionMonitor) {
                connectionMonitorSheet
            }
            .sheet(isPresented: $showUserManagement) {
                userManagementSheet
            }
            .sheet(isPresented: $showPrintSheet) {
                printSettingsSheet
            }
            .sheet(isPresented: $showPlaylistEditor) {
                PlaylistEditorView(isPresented: $showPlaylistEditor)
                    .environmentObject(dataSyncManager)
                    .environmentObject(timerServer)
            }
            .modifier(ContentViewLifecycleModifiers(
                showSavePanel: $showSavePanel,
                showOpenPanel: $showOpenPanel,
                showImportCSVPanel: $showImportCSVPanel,
                isOpeningFile: $isOpeningFile,
                dataSyncManager: dataSyncManager,
                timerServer: timerServer,
                saveFile: saveFile,
                openFile: openFile,
                importCSV: importCSV,
                clearCueSelection: clearCueSelection,
                updateWebClients: updateWebClients,
                autoSave: autoSave,
                printCueStacks: printCueStacks,
                setupAppDelegate: setupAppDelegate,
                setupAppDelegateNotifications: setupAppDelegateNotifications,
                loadLastFile: loadLastFile,
                openDocumentAtURL: { url in beginOpeningDocument(at: url) },
                handleKeyDown: handleKeyDown,
                hasExplicitlyOpenedFile: $hasExplicitlyOpenedFile,
                appDelegate: appDelegate,
                showSettings: $showSettings,
                isDirty: isDirty,
                isLoadingFromDisk: $isLoadingFromDisk,
                markDirty: { isDirty = true },
                updateWindowChrome: updateWindowChrome
            ))
            .onChange(of: pdfNotes) { _, _ in
                if !isLoadingFromDisk { isDirty = true }
            }
            .onChange(of: settingsManager.settings.highlightColors) { _, _ in
                if !isLoadingFromDisk { isDirty = true }
            }
            // MARK: - Phase 2 — file-safety wiring on the body
            .onChange(of: lastSavedURL) { _, newURL in
                if let url = newURL {
                    startFileWatcher(at: url)
                } else {
                    fileWatcher?.stop()
                    fileWatcher = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .appDelegateDidBecomeActive)) { _ in
                recheckExternalChangesNow()
            }
            .alert("This file changed outside of Cue to Cue", isPresented: $showConflictSheet) {
                Button("Reload from Disk", role: .destructive) {
                    reloadFromDiskAfterConflict()
                }
                Button("Keep My Version") {
                    forceOverwriteAfterConflict()
                }
                Button("Show in Finder") {
                    if let url = pendingConflictURL ?? lastSavedURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    // Re-arm so the alert can show again on next save.
                    DispatchQueue.main.async { showConflictSheet = true }
                }
                Button("Cancel", role: .cancel) {
                    // Keep documentChangedExternally so the toolbar / next
                    // save still warns.
                }
            } message: {
                let name = (pendingConflictURL ?? lastSavedURL)?.lastPathComponent ?? displayFileName
                Text("\(name) was modified by another program since you last saved. Reloading replaces your unsaved edits with the on-disk version. Keeping your version overwrites the on-disk version (a backup is kept in Application Support).")
            }
            .alert("Couldn't find your file", isPresented: $showMissingFileSheet) {
                Button("Locate File…") {
                    locateMissingFile()
                }
                Button("Save As…") {
                    saveFileAs()
                }
                Button("Continue Without a File", role: .cancel) {
                    abandonMissingFile()
                }
            } message: {
                let path = pendingConflictURL?.path ?? "(unknown)"
                Text("\(pendingConflictURL?.lastPathComponent ?? displayFileName) couldn't be located at \(path). It may have been moved, renamed, or deleted in Finder or another app.")
            }
            // MARK: - Phase 3 — Restore-from-Backup + backup status
            .sheet(isPresented: $showRestoreSheet) {
                RestoreFromBackupView(
                    mainFileURL: lastSavedURL,
                    onRestore: { url in
                        showRestoreSheet = false
                        restoreFromBackup(at: url)
                    },
                    onCancel: {
                        showRestoreSheet = false
                    }
                )
            }
            .alert("Some backup destinations were unavailable", isPresented: $showBackupWarning) {
                Button("OK") {}
                Button("Show in Finder") {
                    if let url = BackupManager.shared.revealableBackupURL(forMainFile: lastSavedURL) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            } message: {
                Text("Your file saved successfully, but one or more backup tiers reported an error:\n\n\(backupWarningDetail)\n\nYour data is still protected by the remaining tiers.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .documentStoreBackupsCompleted)) { note in
                handleBackupReport(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .appDelegateRestoreFromBackup)) { _ in
                showRestoreSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .appDelegateRevealBackups)) { _ in
                if let url = BackupManager.shared.revealableBackupURL(forMainFile: lastSavedURL) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
    }
    
    // MARK: - Computed Properties
    
    private var mainContentView: some View {
        Group {
            GeometryReader { geometry in
                ZStack {
                    settingsManager.settings.backgroundColor.edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 0) {
                        ZStack {
                            HStack {
                                Spacer()
                                Text(displayFileName)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .offset(x: 0, y: -16)
                                Spacer()
                            }
                            .frame(alignment: .top)
                            .padding(.bottom, 20)
                        }
                        .frame(height: 8, alignment: .top)
                        .background(Color.gray.opacity(0.2))
                        
                        VStack(spacing: 20) {
                            TopSectionView(
                                currentTime: $timerServer.currentTime,
                                countdownTime: $timerServer.countdownTime,
                                countdownRunning: $timerServer.countdownRunning,
                                countUpTime: $timerServer.countUpTime,
                                countUpRunning: $timerServer.countUpRunning,
                                timerServer: timerServer,
                                showPlaylistEditor: $showPlaylistEditor,
                                showSettings: $showSettings,
                                showConnectionMonitor: $showConnectionMonitor,
                                showUserManagement: $showUserManagement,
                                currentFileName: $currentFileName,
                                updateWebClients: updateWebClients
                            )
                            .environmentObject(dataSyncManager)
                            .environmentObject(websiteSyncManager)
                            
                            HStack(alignment: .top, spacing: 0) {
                                VStack(alignment: .leading, spacing: 0) {
                                    CueStackListView(
                                        cueStacks: $dataSyncManager.cueStacks,
                                        selectedCueStackIndex: $dataSyncManager.selectedCueStackIndex,
                                        cueStackListWidth: $cueStackListWidth
                                    )
                                    Spacer(minLength: 20)
                                }
                                .frame(width: cueStackListWidth)
                                
                                ResizableDivider(width: $cueStackListWidth, minWidth: 100, maxWidth: geometry.size.width / 2)
                                
                                CueStackDetailView(
                                    cueStack: selectedCueStackBinding,
                                    isReorderingCues: $isReorderingCues,
                                    editingCueIndex: $editingCueIndex,
                                    scrollViewProxy: $scrollViewProxy,
                                    geometry: geometry,
                                    selectedCueIndex: selectedCueIndexBinding,
                                    selectedCueIndices: $selectedCueIndices,
                                    selectedCueTime: $selectedCueTime,
                                    countdownTime: $countdownTime,
                                    countdownRunning: $countdownRunning,
                                    countUpRunning: $countUpRunning,
                                    settingsManager: settingsManager,
                                    appDelegate: appDelegate,
                                    updateWebClients: updateWebClients,
                                    saveState: saveState,
                                    addCue: addCue,
                                    advanceCue: advanceCue,
                                    previousCue: previousCue,
                                    highlightCue: highlightCue,
                                    parseCountdownTime: parseCountdownTime,
                                    getHighlightColor: getHighlightColor,
                                    handleCueSelection: handleCueSelection,
                                    deleteSelectedCues: deleteSelectedCues,
                                    copyCue: copyCue,
                                    pasteCue: pasteCue
                                )
                                .padding(.horizontal)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(16)
                            }
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(16)
                        }
                        .padding()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var connectionMonitorSheet: some View {
        if let webServer = webServer {
            ConnectionMonitorView(
                isPresented: $showConnectionMonitor,
                webServer: webServer
            )
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var userManagementSheet: some View {
        if let authManager = authManager {
            UserManagementView(
                authManager: authManager,
                isPresented: $showUserManagement,
                cueStacks: dataSyncManager.cueStacks
            )
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var printSettingsSheet: some View {
        PrintSettingsView(
            selectedIndices: $printSelectedCueStackIndices,
            fontSize: $printFontSize,
            cueStacks: dataSyncManager.cueStacks,
            onPrint: {
                self.performPrintAction()
            }
        )
    }
    
    // MARK: - Helper Methods
    
    func updateWebClients() {
        updateWebServer()
    }
    
    private func updateWebServer() {
        // Web server update implementation
        if webServer == nil {
            webServer = WebServer(dataSyncManager: dataSyncManager, timerServer: timerServer)
            webServer?.start(port: 8080)
            // Get the auth manager from the web server
            authManager = webServer?.authManager
        }
        
        // Synchronize highlight colors from SettingsManager to DataSyncManager
        dataSyncManager.updateHighlightColors(settingsManager.settings.highlightColors)
        
        // No need to manually update cues - WebServer now uses the same DataSyncManager
        // The data is automatically synchronized through the shared instance
    }
    
    func getWebUpdateInfo() -> (cueStacks: [CueStack], selectedIndex: Int, activeIndex: Int) {
        return (dataSyncManager.cueStacks, dataSyncManager.selectedCueStackIndex, dataSyncManager.selectedCueIndex)
    }
    
    // MARK: - App Termination Support
    var currentFileURL: URL? {
        return lastSavedURL
    }
    
    private func setupAppDelegate() {
        // Note: ContentView is a struct, so we can't store a direct reference
        // Communication is handled through NotificationCenter instead
    }
    
    private func setupAppDelegateNotifications() {
        // SwiftUI can call onAppear more than once (sheet dismiss, window
        // focus, view rebuild). Each call used to register duplicate
        // NotificationCenter observers, so Cmd-Z fired undo() twice.
        guard !ContentViewLifecycleSetup.appDelegateNotificationsRegistered else { return }
        ContentViewLifecycleSetup.appDelegateNotificationsRegistered = true

        // File operations
        NotificationCenter.default.addObserver(
            forName: .appDelegateNewFile,
            object: nil,
            queue: .main
        ) { _ in
            self.newFile()
        }
        
        NotificationCenter.default.addObserver(
            forName: .appDelegateOpenFile,
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.object as? URL {
                self.hasExplicitlyOpenedFile = true
                self.appDelegate.pendingFileToOpen = nil
                self.beginOpeningDocument(at: url)
            } else {
                self.openFile()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .appDelegateSaveFile,
            object: nil,
            queue: .main
        ) { _ in
            // Call saveFile() directly. The previous implementation set
            // showSavePanel = true and relied on .onChange to fire, but
            // .onChange only fires on transitions, so the second Cmd-S in
            // a row was a silent no-op.
            self.saveFile()
        }

        NotificationCenter.default.addObserver(
            forName: .appDelegateSaveFileAs,
            object: nil,
            queue: .main
        ) { _ in
            self.saveFileAs()
        }

        NotificationCenter.default.addObserver(
            forName: .appDelegateDuplicateFile,
            object: nil,
            queue: .main
        ) { _ in
            self.duplicateFile()
        }

        NotificationCenter.default.addObserver(
            forName: .appDelegateImportCSV,
            object: nil,
            queue: .main
        ) { _ in
            // Same reasoning as save: call directly, do not rely on a Bool
            // binding edge as a trigger.
            self.importCSV()
        }
        
        NotificationCenter.default.addObserver(
            forName: .appDelegateExportCSV,
            object: nil,
            queue: .main
        ) { _ in
            self.exportCSV()
        }
        
        // Edit operations
        NotificationCenter.default.addObserver(
            forName: .appDelegateUndo,
            object: nil,
            queue: .main
        ) { _ in
            self.undo()
        }
        
        NotificationCenter.default.addObserver(
            forName: .appDelegateRedo,
            object: nil,
            queue: .main
        ) { _ in
            self.redo()
        }
        
        NotificationCenter.default.addObserver(
            forName: .appDelegateCut,
            object: nil,
            queue: .main
        ) { _ in
            // Cut cue functionality - ContentView handles this through copy/delete
            if let selectedIndices = self.getSelectedCueIndices() {
                self.copyCues(at: selectedIndices)
                self.deleteSelectedCues()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .appDelegateCopy,
            object: nil,
            queue: .main
        ) { _ in
            self.copy(nil)
        }
        
        NotificationCenter.default.addObserver(
            forName: .appDelegatePaste,
            object: nil,
            queue: .main
        ) { _ in
            self.paste(nil)
        }
        
        NotificationCenter.default.addObserver(
            forName: .appDelegateDelete,
            object: nil,
            queue: .main
        ) { _ in
            if !self.selectedCueIndices.isEmpty {
                self.deleteSelectedCues()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .appDelegateSelectAll,
            object: nil,
            queue: .main
        ) { _ in
            self.selectAllCues()
        }
        
        NotificationCenter.default.addObserver(
            forName: .appDelegateToggleStrikeThrough,
            object: nil,
            queue: .main
        ) { _ in
            self.toggleStrikeThrough()
        }
        
        // View operations
        NotificationCenter.default.addObserver(
            forName: .appDelegateShowPreferences,
            object: nil,
            queue: .main
        ) { _ in
            self.showSettings = true
        }
        
        // Web client operations
        NotificationCenter.default.addObserver(
            forName: .appDelegateUpdateWebClients,
            object: nil,
            queue: .main
        ) { _ in
            self.updateWebClients()
        }
    }
    
    private func beginOpeningDocument(at url: URL) {
        guard CueStackDocumentType.shouldOpen(at: url) else { return }

        saveCurrentDocumentIfNeeded(for: .openDocument) { saved in
            guard saved else { return }
            self.loadDocument(from: url)
        }
    }

    private func loadDocument(from url: URL) {
        hasExplicitlyOpenedFile = true

        do {
            let savedData = try DocumentStore.shared.load(from: url)
            applyLoadedData(savedData, from: url, persistAsLastSavedURL: true)
            CueStackDocumentType.repairContentTypeIfNeeded(at: url)
            print("✅ File opened successfully: \(url.path)")
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
    private func applyLoadedData(_ savedData: SavedData, from url: URL, persistAsLastSavedURL: Bool) {
        isLoadingFromDisk = true

        let hasContent = !savedData.cueStacks.isEmpty
        if hasContent {
            self.dataSyncManager.cueStacks = savedData.cueStacks
        } else {
            print("⚠️ File decoded to empty cueStacks — keeping current in-memory data and NOT pointing autosave at this file.")
        }
        self.settingsManager.settings.highlightColors = savedData.highlightColors
        self.pdfNotes = savedData.pdfNotes
        self.dataSyncManager.countdownPlaylist = savedData.countdownPlaylist
        self.timerServer.syncPlaylistState(savedData.countdownPlaylist)

        if persistAsLastSavedURL && hasContent {
            self.lastSavedURL = url
            self.currentFileName = url.lastPathComponent
            // Phase 2: bookmark survives renames/moves; the legacy URL key is
            // mirrored for backward compatibility but no longer authoritative.
            try? DocumentStore.shared.saveBookmark(for: url)
            UserDefaults.standard.set(url, forKey: "LastSavedURL")
            if let state = try? DocumentStore.shared.diskState(for: url) {
                DocumentStore.shared.recordDiskState(state)
                self.lastSaveDate = state.modificationDate
            } else {
                self.lastSaveDate = Date()
            }
        } else if persistAsLastSavedURL && !hasContent {
            // Decoded an empty document. Clear the autosave target so we
            // don't overwrite the file with seed/test data.
            self.lastSavedURL = nil
            self.currentFileName = url.lastPathComponent + " (empty — choose Save As to keep changes)"
            DocumentStore.shared.clearBookmark()
            DocumentStore.shared.clearRecordedDiskState()
            UserDefaults.standard.removeObject(forKey: "LastSavedURL")
        }

        // Loading is the new clean baseline.
        self.documentChangedExternally = false
        self.isDirty = false
        self.lastRecoveryURL = nil

        self.updateWebClients()

        // Auto-sync to website if enabled (don't let it touch the local file).
        self.websiteSyncManager.autoSyncIfEnabled(
            cueStacks: self.dataSyncManager.cueStacks,
            selectedCueStackIndex: self.dataSyncManager.selectedCueStackIndex,
            filename: self.currentFileName,
            settingsManager: self.settingsManager
        )

        // Window chrome (modified-dot, title, "Saved at" line).
        updateWindowChrome()

        if hasContent {
            resetUndoHistory()
        }

        // Drop the loading flag on the next runloop tick so all the .onChange
        // observers fire while it is still true.
        DispatchQueue.main.async {
            self.isLoadingFromDisk = false
        }
    }
    
    private func hasTextSelectionInFirstResponder() -> Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder else { return false }
        
        // Check if first responder is a text view (NSTextView)
        if let textView = firstResponder as? NSTextView {
            return textView.selectedRange.length > 0
        }
        
        // Check if first responder is a text field with an editor
        if let textField = firstResponder as? NSTextField,
           let editor = textField.currentEditor() as? NSTextView {
            return editor.selectedRange.length > 0
        }
        
        return false
    }
    
    private func handleKeyDown(with event: NSEvent) -> Bool {
        guard editingCueIndex == nil else { return false }
        
        // Check for customizable keyboard shortcuts first
        if let matchedShortcut = findMatchingShortcut(event: event, in: settingsManager.shortcutsManager) {
            // Menu shortcuts should be handled by the menu system, not intercepted here
            let menuShortcutIds = ["new", "open", "save", "saveAs", "importCSV", "exportCSV", "print", "undo", "redo", "cut", "copy", "paste", "delete", "selectAll", "toggleStrikeThrough", "toggleFullScreen", "preferences", "quit"]
            if menuShortcutIds.contains(matchedShortcut.id) {
                return false  // Let the menu system handle it
            }
            handleShortcutAction(matchedShortcut.id)
            return true
        }
        
        // Note: Menu shortcuts (Cmd+C, Cmd+V, Cmd+A, Cmd+S, etc.) are now handled
        // by the menu system via AppDelegate. The shortcuts system above will
        // return false for menu shortcuts to let them pass through to the menu.
        switch event.keyCode {
        case 126: // Up arrow
            previousCue()
            return true
        case 125: // Down arrow
            advanceCue()
            return true
        case 51: // Delete key
            if isMultiSelectMode && !selectedCueIndices.isEmpty {
                deleteSelectedCues()
                return true
            }
        default:
            break
        }
        return false
    }
    
    // MARK: - Selection Methods
    
    func handleCueSelection(at index: Int, withShiftKey: Bool, withCommandKey: Bool) {
        guard dataSyncManager.cueStacks.indices.contains(dataSyncManager.selectedCueStackIndex),
              index >= 0 && index < dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.count else {
            return
        }
        if withCommandKey {
            isMultiSelectMode = true
            if selectedCueIndices.contains(index) {
                selectedCueIndices.remove(index)
                if selectedCueIndices.isEmpty {
                    isMultiSelectMode = false
                    dataSyncManager.selectedCueIndex = -1
                }
            } else {
                selectedCueIndices.insert(index)
                dataSyncManager.selectedCueIndex = index
            }
        } else if withShiftKey && lastSelectedIndex != nil {
            isMultiSelectMode = true
            let start = min(lastSelectedIndex!, index)
            let end = max(lastSelectedIndex!, index)
            for i in start...end {
                if i >= 0 && i < dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.count {
                    selectedCueIndices.insert(i)
                }
            }
            dataSyncManager.selectedCueIndex = index
        } else {
            if isMultiSelectMode {
                selectedCueIndices.removeAll()
                isMultiSelectMode = false
            }
            dataSyncManager.selectedCueIndex = index
            lastSelectedIndex = index
            selectedCueIndices = [index]
            // Reset the countdown based on the cue’s timer.
            highlightCue(at: index)
        }
        lastSelectedIndex = index
        updateWebClients()
    }
    
    func getSelectedCueIndices() -> [Int]? {
        if isMultiSelectMode && !selectedCueIndices.isEmpty {
            return Array(selectedCueIndices).sorted()
        } else if dataSyncManager.selectedCueIndex >= 0 {
            return [dataSyncManager.selectedCueIndex]
        }
        return nil
    }
    
    func clearCueSelection() {
        selectedCueIndices.removeAll()
        isMultiSelectMode = false
        lastSelectedIndex = nil
    }
    
    func selectAllCues() {
        guard dataSyncManager.cueStacks.indices.contains(dataSyncManager.selectedCueStackIndex) else { return }
        let cueCount = dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.count
        if cueCount > 0 {
            isMultiSelectMode = true
            selectedCueIndices = Set(0..<cueCount)
            if dataSyncManager.selectedCueIndex >= 0 {
                lastSelectedIndex = dataSyncManager.selectedCueIndex
            } else {
                dataSyncManager.selectedCueIndex = 0
                lastSelectedIndex = 0
            }
            updateWebClients()
        }
    }
    
    func deleteSelectedCues() {
        guard isMultiSelectMode && !selectedCueIndices.isEmpty else { return }
        let sortedIndices = Array(selectedCueIndices).sorted(by: >)
        for index in sortedIndices {
            if index < dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.count {
                dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.remove(at: index)
            }
        }
        if dataSyncManager.selectedCueIndex >= 0 {
            let lowestDeletedIndex = sortedIndices.last ?? 0
            if sortedIndices.contains(dataSyncManager.selectedCueIndex) {
                dataSyncManager.selectedCueIndex = max(0, lowestDeletedIndex - 1)
            } else if lowestDeletedIndex < dataSyncManager.selectedCueIndex {
                let deletedCount = sortedIndices.filter { $0 < dataSyncManager.selectedCueIndex }.count
                dataSyncManager.selectedCueIndex = dataSyncManager.selectedCueIndex - deletedCount
            }
        }
        clearCueSelection()
        saveState()
        updateWebClients()
    }
    
    private func advanceCue() {
        guard dataSyncManager.selectedCueIndex >= 0 else { return }
        if dataSyncManager.selectedCueIndex < dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.count - 1 {
            selectCue(at: dataSyncManager.selectedCueIndex + 1)
            updateWebClients()
        }
    }
    
    private func previousCue() {
        guard dataSyncManager.selectedCueIndex >= 0 else { return }
        if dataSyncManager.selectedCueIndex > 0 {
            selectCue(at: dataSyncManager.selectedCueIndex - 1)
            updateWebClients()
        }
    }
    
    private func selectCue(at index: Int) {
        dataSyncManager.selectedCueIndex = index
        highlightCue(at: index)
        // updateWebClients() will be called automatically by onChange(of: selectedCueIndex)
    }
    
    // MARK: - Timer Control Methods (for keyboard shortcuts)
    
    private func startCountdownTimer() {
        let command = TimerCommand(action: "start", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(command)
    }
    
    private func pauseCountdownTimer() {
        let command = TimerCommand(action: "pause", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(command)
    }
    
    private func resetCountdownTimer() {
        let command = TimerCommand(action: "reset", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(command)
    }
    
    private func adjustCountdownTime(by seconds: Int) {
        let command = TimerCommand(action: "adjust", countdownTime: nil, countUpTime: nil, adjustment: seconds, targetTimeString: nil)
        timerServer.executeCommand(command)
    }
    
    private func startCountdownToTime() {
        let command = TimerCommand(action: "startCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(command)
    }
    
    private func pauseCountdownToTime() {
        let command = TimerCommand(action: "pauseCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(command)
    }
    
    private func nextPlaylistEntry() {
        let command = TimerCommand(action: "nextPlaylistEntry", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil)
        timerServer.executeCommand(command)
    }
    
    // MARK: - Keyboard Shortcut Actions
    
    private func handleShortcutAction(_ shortcutId: String) {
        switch shortcutId {
        // Timer Controls - Countdown
        case "countdownStart":
            startCountdownTimer()
        case "countdownPause":
            pauseCountdownTimer()
        case "countdownReset":
            resetCountdownTimer()
        case "countdownPlus1Min":
            adjustCountdownTime(by: 60)
        case "countdownMinus1Min":
            adjustCountdownTime(by: -60)
        
        // Timer Controls - Countdown to Time
        case "countdownToTimeStart":
            startCountdownToTime()
        case "countdownToTimePause":
            pauseCountdownToTime()
        case "countdownToTimeNext":
            nextPlaylistEntry()
        
        // Playlist
        case "countdownPlaylist":
            showPlaylistEditor = true
        
        // Cue Navigation
        case "addCue":
            addCue()
        case "nextCue":
            advanceCue()
        case "previousCue":
            previousCue()
        
        default:
            break
        }
    }
    
    // MARK: - Shortcut Matching Helpers
    
    private func findMatchingShortcut(event: NSEvent, in manager: KeyboardShortcutsManager) -> KeyboardShortcut? {
        // Extract key and modifiers from event
        let keyChar: String
        if let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty {
            let char = characters.first ?? Character("")
            // Use character if it's a letter, number, or common symbol
            if char.isLetter || char.isNumber || ".,;:'\"[]{}()<>?/\\|`~!@#$%^&*-_=+".contains(char) {
                keyChar = String(char)
            } else {
                // Fall back to key code mapping for special keys
                keyChar = keyCodeToCharacter(event.keyCode)
            }
        } else {
            // No character available, use key code mapping
            keyChar = keyCodeToCharacter(event.keyCode)
        }
        
        // If we still don't have a key, skip this event
        guard !keyChar.isEmpty else { return nil }
        
        var modifiers: [String] = []
        if event.modifierFlags.contains(.command) { modifiers.append("command") }
        if event.modifierFlags.contains(.shift) { modifiers.append("shift") }
        if event.modifierFlags.contains(.option) { modifiers.append("option") }
        if event.modifierFlags.contains(.control) { modifiers.append("control") }
        
        // Find matching shortcut
        return manager.shortcuts.first { shortcut in
            shortcut.key == keyChar && Set(shortcut.modifiers) == Set(modifiers)
        }
    }
    
    private func keyCodeToCharacter(_ keyCode: UInt16) -> String {
        // Map special key codes to characters (only for keys that don't have character representations)
        switch keyCode {
        case 30: return "["  // Left bracket
        case 33: return "]"  // Right bracket
        case 27: return "-"   // Minus
        case 24: return "="   // Equals
        case 126: return "↑"  // Up arrow
        case 125: return "↓"  // Down arrow
        case 123: return "←"  // Left arrow
        case 124: return "→"  // Right arrow
        default: return ""
        }
    }
    
    // When a new cue is selected, reset the countdown clock.
    func parseCountdownTime(_ timeString: String) -> Int? {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        if parts.isEmpty {
            return nil
        } else if parts.count == 1 {
            return parts[0]
        } else if parts.count == 2 {
            let (minutes, seconds) = (parts[0], parts[1])
            return minutes * 60 + seconds
        } else if parts.count == 3 {
            let (hours, minutes, seconds) = (parts[0], parts[1], parts[2])
            return hours * 3600 + minutes * 60 + seconds
        } else {
            return nil
        }
    }
    
    private func highlightCue(at index: Int) {
        let cue = dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues[index]
        if let timerValue = parseCountdownTime(cue.timerValue) {
            selectedCueTime = timerValue
            // Post a notification to reset the countdown in TopSectionView
            NotificationCenter.default.post(name: Notification.Name("ResetCountdown"), object: timerValue)
        }
    }
    
    func addCue() {
        let newCue = Cue(values: Array(repeating: "", count: dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].columns.count))
        dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.append(newCue)
        // Snapshot AFTER the mutation so each undo step reverses exactly one add.
        saveState()
        self.appDelegate.updateWebClients()
        print("➕ Added cue #\(dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.count) with ID: \(newCue.id)")
    }
    
    // MARK: - File Saving Methods (Phase 1 — atomic + coordinated + backed up)

    /// Build the in-memory document snapshot.
    private func currentSavedData() -> SavedData {
        SavedData(
            cueStacks: dataSyncManager.cueStacks,
            highlightColors: settingsManager.settings.highlightColors,
            pdfNotes: pdfNotes,
            countdownPlaylist: dataSyncManager.countdownPlaylist
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
    private enum DocumentSwitchAction {
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

    private func saveCurrentDocumentIfNeeded(
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
                showConflictSheet = true
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
    private func prepareOriginalBeforeDuplicate(completion: @escaping (Bool) -> Void) {
        guard isDirty, let url = lastSavedURL else {
            completion(true)
            return
        }

        if saveWouldConflict(at: url) {
            documentChangedExternally = true
            pendingConflictURL = url
            showConflictSheet = true
            showDocumentActionBlockedAlert(
                messageText: "Can't Duplicate Yet",
                informativeText: "Save your changes to the original file first. It was modified outside of Cue to Cue — resolve the conflict, then try again."
            )
            completion(false)
            return
        }

        completion(saveToURL(url))
    }

    private func presentDuplicateSavePanel() {
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

        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        panel.beginSheetModal(for: window) { response in
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
                self.resetUndoHistory()
            }
        }
    }

    private func suggestedDuplicateFilename() -> String {
        let stem = currentFileStem.trimmingCharacters(in: .whitespacesAndNewlines)
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
    private func performNewDocument() {
        let blank = SavedData.blankDocument(highlightColors: settingsManager.settings.highlightColors)
        isLoadingFromDisk = true

        dataSyncManager.cueStacks = blank.cueStacks
        dataSyncManager.selectedCueStackIndex = 0
        dataSyncManager.selectedCueIndex = 0
        dataSyncManager.countdownPlaylist = blank.countdownPlaylist
        pdfNotes = blank.pdfNotes

        selectedCueIndices.removeAll()
        lastSelectedIndex = nil
        isMultiSelectMode = false
        editingCueIndex = nil

        lastSavedURL = nil
        lastSaveDate = nil
        lastRecoveryURL = nil
        documentChangedExternally = false
        pendingConflictURL = nil
        latestBackupReport = nil
        currentFileName = "Untitled"
        hasExplicitlyOpenedFile = true

        DocumentStore.shared.clearBookmark()
        DocumentStore.shared.clearRecordedDiskState()
        UserDefaults.standard.removeObject(forKey: "LastSavedURL")

        fileWatcher?.stop()
        fileWatcher = nil

        isDirty = false

        timerServer.executeCommand(TimerCommand(action: "pause", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil))
        timerServer.executeCommand(TimerCommand(action: "reset", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil))
        timerServer.syncPlaylistState(blank.countdownPlaylist)
        timerServer.executeCommand(TimerCommand(action: "pauseCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil))

        resetUndoHistory()
        updateWebClients()
        updateWindowChrome()

        DispatchQueue.main.async {
            self.isLoadingFromDisk = false
        }
    }

    private func showDocumentActionBlockedAlert(messageText: String, informativeText: String) {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func saveWouldConflict(at url: URL) -> Bool {
        guard url == lastSavedURL,
              FileManager.default.fileExists(atPath: url.path),
              let recorded = DocumentStore.shared.loadRecordedDiskState() else {
            return false
        }
        return DocumentStore.shared.diskStateChanged(at: url, since: recorded)
            && !DocumentStore.shared.wasRecentlySelfWritten()
    }

    /// Save the current document to `url` through DocumentStore (atomic +
    /// coordinated + rotating backup + post-write verification).
    @discardableResult
    func saveToURL(_ url: URL) -> Bool {
        if saveWouldConflict(at: url) {
            documentChangedExternally = true
            pendingConflictURL = url
            showConflictSheet = true
            print("⚠️ Refusing to save — file was modified outside of Cue to Cue since the last known state. Showing conflict sheet.")
            return false
        }

        do {
            let result = try DocumentStore.shared.save(currentSavedData(), to: url)
            self.lastSaveDate = result.savedAt
            self.lastSavedURL = url
            self.currentFileName = url.lastPathComponent
            self.isDirty = false
            self.lastRecoveryURL = nil
            self.documentChangedExternally = false
            self.pendingConflictURL = nil
            try? DocumentStore.shared.saveBookmark(for: url)
            DocumentStore.shared.recordDiskState(DocumentStore.DiskState(modificationDate: result.modificationDate, fileSize: result.fileSize))
            UserDefaults.standard.set(url, forKey: "LastSavedURL")
            print("✅ Saved \(url.lastPathComponent) at \(result.savedAt). Previous version at: \(result.backedUpTo?.path ?? "(no prior file)")")
            self.appDelegate.updateWebClients()
            updateWindowChrome()
            startFileWatcher(at: url)
            return true
        } catch {
            print("❌ Error saving file: \(error.localizedDescription)")
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
        savePanel.nameFieldStringValue = CueStackDocumentType.defaultSaveFilename(stem: currentFileStem)
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else {
            completion?(false)
            return
        }
        savePanel.beginSheetModal(for: window) { response in
            if response == .OK, let url = savePanel.url {
                completion?(self.saveToURL(url))
            } else {
                completion?(false)
            }
        }
    }

    /// Compatibility shim — old call sites used `saveDocument(to:)`.
    func saveDocument(to url: URL) {
        saveToURL(url)
    }

    // MARK: - Autosave (Phase 1 — never silently writes to NSTemporaryDirectory)

    func autoSave() {
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
            let suggestedStem = currentFileStem.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try DocumentStore.shared.saveRecovery(currentSavedData(), suggestedStem: suggestedStem.isEmpty ? "Untitled" : suggestedStem)
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

    private func presentOpenPanel() {
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
            self.showOpenPanel = false
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
            print("🔍 Skipping loadLastFile() - file was explicitly opened")
            return
        }

        print("🔍 loadLastFile() called")

        // Phase 2: migrate any legacy plain-URL value into a bookmark, then
        // resolve. Bookmarks survive Finder rename/move which the plain URL
        // does not.
        DocumentStore.shared.migrateLegacyLastSavedURLIfNeeded()

        let resolvedURL: URL?
        do {
            resolvedURL = try DocumentStore.shared.resolveBookmark()?.url
        } catch {
            print("❌ Could not resolve last document bookmark: \(error.localizedDescription)")
            resolvedURL = nil
        }

        guard let lastURL = resolvedURL else {
            print("⚠️ No last document bookmark found, starting with default state")
            return
        }
        print("🔍 Resolved bookmark to: \(lastURL.path)")

        guard FileManager.default.fileExists(atPath: lastURL.path) else {
            print("❌ Last saved file no longer exists: \(lastURL.path)")
            // Phase 2: tell the user instead of silently dropping the file
            // reference. They can locate it, save as, or continue without.
            pendingConflictURL = lastURL
            showMissingFileSheet = true
            return
        }

        // Phase 2: open-time conflict check. If our recorded mtime/size is
        // older than the file we're about to load, something else updated
        // the file while we weren't running. Surface that *before* applying
        // it so the user knows what happened.
        if let recorded = DocumentStore.shared.loadRecordedDiskState(),
           DocumentStore.shared.diskStateChanged(at: lastURL, since: recorded) {
            print("⚠️ On-disk file is newer than our last recorded state. Showing open-time conflict sheet.")
            documentChangedExternally = true
            pendingConflictURL = lastURL
            showConflictSheet = true
            return
        }

        do {
            let result = try DocumentStore.shared.loadResult(from: lastURL)
            print("🔍 Loaded \(result.savedData.cueStacks.count) cue stacks from \(lastURL.lastPathComponent)")
            if let firstStack = result.savedData.cueStacks.first {
                print("🔍 First stack: \(firstStack.name) with \(firstStack.cues.count) cues")
            }
            // applyLoadedData will refuse to set lastSavedURL if the file is
            // empty (the previous trap that caused autosave to overwrite a
            // user file with seed test data).
            applyLoadedData(result.savedData, from: lastURL, persistAsLastSavedURL: true)
            DocumentStore.shared.recordDiskState(DocumentStore.DiskState(modificationDate: result.modificationDate, fileSize: result.fileSize))
        } catch {
            print("❌ Error loading last file: \(error.localizedDescription)")
            // Do NOT set lastSavedURL — we don't want autosave to overwrite a
            // file that we just failed to decode. Surface the issue to the
            // user so they can investigate the file or restore a backup.
            showOpenError(error: error)
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
            if let backupRoot = try? DocumentStore.shared.backupRoot() {
                NSWorkspace.shared.activateFileViewerSelecting([backupRoot])
            }
        }
    }

    // MARK: - Window chrome (modified-dot, "Saved at HH:mm:ss")

    private func updateWindowChrome() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.isDocumentEdited = isDirty

        // Title format examples:
        //   "Show — Edited - Cue to Cue 2.1"
        //   "Show — Saved 1:34:06 PM · 3 backups - Cue to Cue 2.1"
        //   "Show — Saved 1:34:06 PM · 2 of 3 backups - Cue to Cue 2.1"
        let stem = currentFileStem
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
        window.title = "\(stem)\(suffix) - Cue to Cue 2.1"
    }

    // MARK: - Phase 2 — file watcher + external-change handlers

    /// Start (or restart) the filesystem watcher pointed at `url`. Safe to
    /// call repeatedly; the watcher stops itself first if already active.
    private func startFileWatcher(at url: URL) {
        let watcher = FileWatcher { reason in
            self.handleExternalChange(reason: reason)
        }
        watcher.start(watching: url)
        self.fileWatcher = watcher
    }

    /// Called by the watcher (on the main queue) for filesystem events that
    /// were *not* produced by our own writes.
    private func handleExternalChange(reason: FileWatcher.Reason) {
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
            if DocumentStore.shared.wasRecentlySelfWritten(within: 5.0)
                || FileManager.default.fileExists(atPath: url.path) {
                startFileWatcher(at: url)
                return
            }
            pendingConflictURL = url
            showMissingFileSheet = true
        case .write, .other:
            guard let url = lastSavedURL else { return }
            // Cross-check disk state: if mtime+size still match what we
            // recorded after our last save, this was a noop event (Spotlight,
            // iCloud metadata refresh, etc.) and we ignore it.
            if let recorded = DocumentStore.shared.loadRecordedDiskState(),
               !DocumentStore.shared.diskStateChanged(at: url, since: recorded) {
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
    private func recheckExternalChangesNow() {
        guard let url = lastSavedURL else { return }
        // Suppress if our own write was within the settle window.
        if DocumentStore.shared.wasRecentlySelfWritten() { return }
        // If the file is missing, don't pop the missing-file sheet
        // synchronously — Finder, iCloud, and other tools sometimes briefly
        // unlink + relink during sync. Recheck after a short delay; if it
        // is still gone, *then* surface the sheet.
        if !FileManager.default.fileExists(atPath: url.path) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let stillURL = self.lastSavedURL, stillURL == url else { return }
                if !FileManager.default.fileExists(atPath: stillURL.path),
                   !DocumentStore.shared.wasRecentlySelfWritten(within: 5.0) {
                    self.pendingConflictURL = stillURL
                    self.showMissingFileSheet = true
                }
            }
            return
        }
        if let recorded = DocumentStore.shared.loadRecordedDiskState(),
           DocumentStore.shared.diskStateChanged(at: url, since: recorded) {
            documentChangedExternally = true
            pendingConflictURL = url
            showConflictSheet = true
        }
    }

    /// Conflict-sheet action: replace our in-memory state with the on-disk
    /// version.
    private func reloadFromDiskAfterConflict() {
        let url = pendingConflictURL ?? lastSavedURL
        guard let url else { return }
        do {
            let result = try DocumentStore.shared.loadResult(from: url)
            applyLoadedData(result.savedData, from: url, persistAsLastSavedURL: true)
            DocumentStore.shared.recordDiskState(DocumentStore.DiskState(modificationDate: result.modificationDate, fileSize: result.fileSize))
            documentChangedExternally = false
            pendingConflictURL = nil
        } catch {
            showOpenError(error: error)
        }
    }

    /// Conflict-sheet action: overwrite the on-disk file with our in-memory
    /// version. The disk version is preserved as a backup snapshot by
    /// DocumentStore before the write happens.
    private func forceOverwriteAfterConflict() {
        let url = pendingConflictURL ?? lastSavedURL
        guard let url else { return }
        do {
            let result = try DocumentStore.shared.save(currentSavedData(), to: url)
            self.lastSavedURL = url
            self.lastSaveDate = result.savedAt
            self.currentFileName = url.lastPathComponent
            self.isDirty = false
            self.lastRecoveryURL = nil
            self.documentChangedExternally = false
            self.pendingConflictURL = nil
            try? DocumentStore.shared.saveBookmark(for: url)
            DocumentStore.shared.recordDiskState(DocumentStore.DiskState(modificationDate: result.modificationDate, fileSize: result.fileSize))
            UserDefaults.standard.set(url, forKey: "LastSavedURL")
            self.appDelegate.updateWebClients()
            updateWindowChrome()
        } catch {
            showSaveError(error: error)
        }
    }

    /// Missing-file-sheet action: prompt the user to locate the file.
    private func locateMissingFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.cueStackReadableTypes
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if let parent = pendingConflictURL?.deletingLastPathComponent() {
            panel.directoryURL = parent
        }
        panel.begin { response in
            self.showMissingFileSheet = false
            if response == .OK, let url = panel.url {
                self.hasExplicitlyOpenedFile = true
                self.beginOpeningDocument(at: url)
            }
            self.pendingConflictURL = nil
        }
    }

    /// Missing-file-sheet action: drop the file reference and continue with
    /// the in-memory state. Future autosaves will go to Recovery.
    private func abandonMissingFile() {
        self.lastSavedURL = nil
        DocumentStore.shared.clearBookmark()
        DocumentStore.shared.clearRecordedDiskState()
        UserDefaults.standard.removeObject(forKey: "LastSavedURL")
        self.currentFileName = "Untitled"
        self.pendingConflictURL = nil
        // Mark dirty so the user is reminded to Save As before quitting.
        self.isDirty = true
        updateWindowChrome()
    }

    // MARK: - Phase 3 — Backup status + restore

    /// Receives the asynchronous backup-fan-out report from DocumentStore.
    /// Updates the in-memory status and surfaces a non-blocking warning if
    /// any tier failed.
    private func handleBackupReport(_ note: Notification) {
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
    private func restoreFromBackup(at backupURL: URL) {
        // 1) Snapshot current state to Recovery so this action can never
        //    lose work, even if the user picks the wrong backup.
        let suggestedStem = currentFileStem.trimmingCharacters(in: .whitespacesAndNewlines)
        let recoveryStem = "PreRestore-" + (suggestedStem.isEmpty ? "Untitled" : suggestedStem)
        // Only attempt the recovery snapshot if the in-memory document is
        // non-empty; DocumentStore refuses empty saves.
        if !dataSyncManager.cueStacks.isEmpty {
            do {
                let r = try DocumentStore.shared.saveRecovery(currentSavedData(), suggestedStem: recoveryStem)
                self.lastRecoveryURL = r.url
                print("📦 Pre-restore recovery saved at \(r.url.path)")
            } catch {
                NSLog("ContentView: pre-restore recovery save failed: \(error.localizedDescription). Continuing anyway.")
            }
        }

        // 2) Load the chosen backup.
        do {
            let result = try DocumentStore.shared.loadResult(from: backupURL)
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
                self.currentFileName = "Restored from " + backupURL.lastPathComponent
            }
            updateWindowChrome()
        } catch {
            showOpenError(error: error)
        }
    }

    func importCSV() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let importedCues = parseCSV(data: data)
                    let selectedStack = dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex]
                    let maxImportedColumns = importedCues.map { $0.values.count }.max() ?? 0
                    let currentColumnCount = selectedStack.columns.count
                    let newMaxColumns = max(maxImportedColumns, currentColumnCount)
                    while dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].columns.count < newMaxColumns {
                        let newColumnIndex = dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].columns.count
                        dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].columns.append(Column(name: "Column \(newColumnIndex + 1)", width: 100))
                    }
                    let preparedImportedCues = importedCues.map { cue -> Cue in
                        var values = cue.values
                        while values.count < newMaxColumns {
                            values.append("")
                        }
                        return Cue(values: values)
                    }
                    dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.insert(contentsOf: preparedImportedCues, at: 0)
                    saveState()
                    updateWebClients()
                } catch {
                    print("Error reading CSV file: \(error)")
                }
            }
        }
    }
    
    func parseCSV(data: Data) -> [Cue] {
        let content = String(data: data, encoding: .utf8) ?? ""
        let lines = content.components(separatedBy: .newlines)
        return lines.filter { !$0.isEmpty }.map { line in
            let values = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return Cue(values: values)
        }
    }

    // MARK: - CSV Export (redundancy export)

    /// Export every cue stack into a single CSV file. Designed as a
    /// human-readable redundancy artifact: open it in Excel/Numbers, archive
    /// it, attach it to email, drag a copy to a USB stick. Writes are
    /// atomic + coordinated so a CSV file on iCloud Drive can't be
    /// corrupted by a sync engine mid-export.
    ///
    /// Format (RFC 4180-compliant):
    ///   Cue Stack,<col1>,<col2>,…,<colN>,Timer,Strikethrough\r\n
    ///   "NYC Keynote","…","…",…,"08:00","FALSE"\r\n
    ///   …
    /// The column union across stacks is used so every value finds a home;
    /// columns missing in a particular stack are written as empty strings.
    /// Values containing commas, quotes, or newlines are quoted and escaped.
    func exportCSV() {
        let stacks = dataSyncManager.cueStacks
        guard !stacks.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Nothing to export"
            alert.informativeText = "There are no cue stacks in this document yet."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export CSV"
        panel.message = "Exports every cue stack to a single CSV file. Useful as a redundancy backup that you can open in Excel or Numbers."
        let trimmedStem = currentFileStem.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = (trimmedStem.isEmpty ? "Cue Stacks" : trimmedStem) + ".csv"

        let proceed: (URL) -> Void = { url in
            do {
                let csv = self.buildCSVForAllStacks()
                guard let data = csv.data(using: .utf8) else {
                    throw NSError(domain: "ExportCSV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode CSV as UTF-8"])
                }
                var coordError: NSError?
                var thrown: Error?
                NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { coordinatedURL in
                    do {
                        try data.write(to: coordinatedURL, options: [.atomic])
                    } catch {
                        thrown = error
                    }
                }
                if let e = thrown { throw e }
                if let e = coordError { throw e }
                print("✅ CSV exported to \(url.path) (\(data.count) bytes, \(stacks.count) stacks)")
            } catch {
                print("❌ CSV export failed: \(error.localizedDescription)")
                self.showSaveError(error: error)
            }
        }

        if let window = NSApp.windows.first {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url {
                    proceed(url)
                }
            }
        } else {
            // Fallback: no window yet, run modally.
            if panel.runModal() == .OK, let url = panel.url {
                proceed(url)
            }
        }
    }

    /// Build the full unified CSV string for every cue stack in the
    /// document. Visible for unit testing later.
    func buildCSVForAllStacks() -> String {
        let stacks = dataSyncManager.cueStacks

        // Union of column names, preserving first-seen order so the output
        // is deterministic.
        var allColumnNames: [String] = []
        for stack in stacks {
            for col in stack.columns where !allColumnNames.contains(col.name) {
                allColumnNames.append(col.name)
            }
        }

        let header: [String] = ["Cue Stack"] + allColumnNames + ["Timer", "Strikethrough"]
        var lines: [String] = [header.map(csvEscape).joined(separator: ",")]

        for stack in stacks {
            for cue in stack.cues {
                var row: [String] = [stack.name]
                for unionColName in allColumnNames {
                    if let stackIdx = stack.columns.firstIndex(where: { $0.name == unionColName }),
                       stackIdx < cue.values.count {
                        row.append(cue.values[stackIdx])
                    } else {
                        row.append("")
                    }
                }
                row.append(cue.timerValue)
                row.append(cue.isStruckThrough ? "TRUE" : "FALSE")
                lines.append(row.map(csvEscape).joined(separator: ","))
            }
        }

        // CRLF line endings + trailing CRLF for maximum compatibility with
        // Excel on Windows and Numbers on macOS.
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Escape one CSV field per RFC 4180. Wraps the value in double quotes
    /// if it contains a comma, double quote, or newline. Inner double
    /// quotes are doubled to `""`.
    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    func saveState() {
        guard dataSyncManager.cueStacks.indices.contains(dataSyncManager.selectedCueStackIndex) else { return }
        let currentStack = dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex]

        // Each snapshot must reflect the document AS THE USER SEES IT after a
        // completed edit. Call saveState() only AFTER applying a mutation.
        // Undo restores history[currentStateIndex - 1], stepping back one action.
        let currentState = (columns: currentStack.columns, cues: currentStack.cues, timestamp: Date().timeIntervalSince1970)

        if currentStateIndex >= 0, currentStateIndex < stateHistory.count {
            let snapshot = stateHistory[currentStateIndex]
            if snapshot.columns == currentState.columns && snapshot.cues == currentState.cues {
                return
            }
        }

        if currentStateIndex < stateHistory.count - 1 {
            stateHistory = Array(stateHistory.prefix(upTo: currentStateIndex + 1))
        }
        stateHistory.append(currentState)
        currentStateIndex += 1
        print("💾 Saved state #\(currentStateIndex) with \(currentState.cues.count) cues")
    }

    /// Establish a clean undo baseline after loading a file or resetting the
    /// document, so the first Cmd-Z only reverses edits made in this session.
    private func resetUndoHistory() {
        stateHistory.removeAll(keepingCapacity: true)
        currentStateIndex = -1
        saveState()
    }
    
    func undo() {
        guard !ContentViewLifecycleSetup.isPerformingUndoRedo else { return }
        guard currentStateIndex > 0 else { return }
        ContentViewLifecycleSetup.isPerformingUndoRedo = true
        defer { ContentViewLifecycleSetup.isPerformingUndoRedo = false }

        currentStateIndex -= 1
        let previousState = stateHistory[currentStateIndex]
        dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].columns = previousState.columns
        dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues = previousState.cues
        print("↩️ Undo to state #\(currentStateIndex) with \(previousState.cues.count) cues")
        self.appDelegate.updateWebClients()
    }
    
    func redo() {
        guard !ContentViewLifecycleSetup.isPerformingUndoRedo else { return }
        guard currentStateIndex < stateHistory.count - 1 else { return }
        ContentViewLifecycleSetup.isPerformingUndoRedo = true
        defer { ContentViewLifecycleSetup.isPerformingUndoRedo = false }

        currentStateIndex += 1
        let nextState = stateHistory[currentStateIndex]
        dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].columns = nextState.columns
        dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues = nextState.cues
        print("↪️ Redo to state #\(currentStateIndex) with \(nextState.cues.count) cues")
        self.appDelegate.updateWebClients()
    }
    
    func getHighlightColor(for cue: Cue) -> Color {
        for highlight in settingsManager.settings.highlightColors {
            if cue.values.contains(where: { $0.lowercased().contains(highlight.keyword.lowercased()) }) {
                return highlight.color
            }
        }
        return settingsManager.settings.fontColor
    }
    
    // MARK: - Copy and Paste Methods
    
    func copy(_ sender: Any?) {
        if let selectedIndices = getSelectedCueIndices() {
            copyCues(at: selectedIndices)
        }
    }
    
    func copyCues(at indices: [Int]) {
        guard !indices.isEmpty, dataSyncManager.cueStacks.indices.contains(dataSyncManager.selectedCueStackIndex) else { return }
        let cuesToCopy = indices.compactMap { index -> Cue? in
            guard index >= 0 && index < dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.count else {
                return nil
            }
            return dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues[index]
        }
        if !cuesToCopy.isEmpty {
            let transferCues = MultiCueTransfer(
                cues: cuesToCopy,
                columnCount: dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].columns.count
            )
            let encoder = JSONEncoder()
            if let encodedCues = try? encoder.encode(transferCues) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(encodedCues, forType: .string)
            }
        }
    }
    
    func copyCue(at index: Int) {
        copyCues(at: [index])
    }
    
    func paste(_ sender: Any?) {
        if dataSyncManager.selectedCueIndex >= 0 {
            pasteCues(after: dataSyncManager.selectedCueIndex)
        }
    }
    
    func pasteCues(after index: Int) {
        guard dataSyncManager.cueStacks.indices.contains(dataSyncManager.selectedCueStackIndex) else {
            print("Selected cue stack index is out of range")
            return
        }
        guard index >= 0 && index < dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.count else {
            print("Selected cue index is out of range")
            return
        }
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .string) {
            let decoder = JSONDecoder()
            if let transferCues = try? decoder.decode(MultiCueTransfer.self, from: data) {
                let targetColumnCount = dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].columns.count
                var adjustedCues: [Cue] = []
                for cue in transferCues.cues {
                    var newCue = cue
                    if newCue.values.count < targetColumnCount {
                        while newCue.values.count < targetColumnCount {
                            newCue.values.append("")
                        }
                    } else if newCue.values.count > targetColumnCount {
                        newCue.values = Array(newCue.values.prefix(targetColumnCount))
                    }
                    adjustedCues.append(newCue)
                }
                dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.insert(contentsOf: adjustedCues, at: index + 1)
                dataSyncManager.selectedCueIndex = index + adjustedCues.count
                saveState()
                self.appDelegate.updateWebClients()
            } else if let transferCue = try? decoder.decode(TransferCue.self, from: data) {
                let targetColumnCount = dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].columns.count
                var newCue = transferCue.cue
                if newCue.values.count < targetColumnCount {
                    while newCue.values.count < targetColumnCount {
                        newCue.values.append("")
                    }
                } else if newCue.values.count > targetColumnCount {
                    newCue.values = Array(newCue.values.prefix(targetColumnCount))
                }
                dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.insert(newCue, at: index + 1)
                dataSyncManager.selectedCueIndex = index + 1
                saveState()
                self.appDelegate.updateWebClients()
            } else if let decodedCue = try? decoder.decode(Cue.self, from: data) {
                var newCue = decodedCue
                let targetColumnCount = dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].columns.count
                if newCue.values.count < targetColumnCount {
                    while newCue.values.count < targetColumnCount {
                        newCue.values.append("")
                    }
                } else if newCue.values.count > targetColumnCount {
                    newCue.values = Array(newCue.values.prefix(targetColumnCount))
                }
                dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.insert(newCue, at: index + 1)
                dataSyncManager.selectedCueIndex = index + 1
                saveState()
                self.appDelegate.updateWebClients()
            }
        }
    }
    
    func pasteCue(at index: Int) {
        pasteCues(after: index)
    }
    
    // MARK: - Strike-Through Functionality
    
    func toggleStrikeThrough() {
        guard dataSyncManager.cueStacks.indices.contains(dataSyncManager.selectedCueStackIndex) else { return }
        
        let selectedStack = dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex]
        guard selectedStack.cues.indices.contains(dataSyncManager.selectedCueIndex) else { return }
        
        let cueId = selectedStack.cues[dataSyncManager.selectedCueIndex].id
        Task {
            await dataSyncManager.toggleStrikeThrough(cueId: cueId)
        }
    }
    
    // MARK: - Printing Functionality
    
    /// Call this function (for example, from your File > Print menu) to show the print options.
    func printCueStacks() {
        // Don't preselect any cue stacks - let user choose manually
        printSelectedCueStackIndices = Set<Int>()
        showPrintSheet = true
    }
    
    /// Called by the print settings sheet to perform printing.
    func performPrintAction() {
        // Gather the selected cue stacks.
        let stacksToPrint = printSelectedCueStackIndices.sorted().map { dataSyncManager.cueStacks[$0] }
        // Call the print function from PrintManager.swift.
        performPrint(cueStacks: stacksToPrint, fontSize: printFontSize)
    }
}

/// One-time lifecycle guards. ContentView is a struct; static state tracks
/// observers/monitors that must not be registered more than once.
enum ContentViewLifecycleSetup {
    static var appDelegateNotificationsRegistered = false
    static var autoSaveObserverRegistered = false
    static var keyEventMonitor: Any?
    static var isPerformingUndoRedo = false
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(currentFileName: .constant("Preview File"))
            .environmentObject(AppDelegate())
            .environmentObject(SettingsManager())
    }
}

// Helper structs for multi-cue copy/paste
struct TransferCue: Codable {
    let cue: Cue
    let columnCount: Int
}

struct MultiCueTransfer: Codable {
    let cues: [Cue]
    let columnCount: Int
}

// MARK: - View Modifier for ContentView Lifecycle

struct ContentViewLifecycleModifiers: ViewModifier {
    @Binding var showSavePanel: Bool
    @Binding var showOpenPanel: Bool
    @Binding var showImportCSVPanel: Bool
    @Binding var isOpeningFile: Bool
    let dataSyncManager: DataSyncManager
    let timerServer: AuthoritativeTimerServer
    let saveFile: () -> Void
    let openFile: () -> Void
    let importCSV: () -> Void
    let clearCueSelection: () -> Void
    let updateWebClients: () -> Void
    let autoSave: () -> Void
    let printCueStacks: () -> Void
    let setupAppDelegate: () -> Void
    let setupAppDelegateNotifications: () -> Void
    let loadLastFile: () -> Void
    let openDocumentAtURL: (URL) -> Void
    let handleKeyDown: (NSEvent) -> Bool
    @Binding var hasExplicitlyOpenedFile: Bool
    let appDelegate: AppDelegate
    @Binding var showSettings: Bool
    // Phase 1 — file-safety wiring
    let isDirty: Bool
    @Binding var isLoadingFromDisk: Bool
    let markDirty: () -> Void
    let updateWindowChrome: () -> Void
    
    func body(content: Content) -> some View {
        content
            // Defensive: if anyone flips these flags to true we still want
            // the action to happen, AND we always reset the flag back to
            // false on the next runloop tick so the next attempt fires.
            // Real triggering now happens directly in the notification
            // observers so menu/Cmd-S works on every press, not just the
            // first one.
            .onChange(of: showSavePanel) { _, newValue in
                if newValue {
                    saveFile()
                    DispatchQueue.main.async { showSavePanel = false }
                }
            }
            .onChange(of: showOpenPanel) { _, newValue in
                if newValue && !isOpeningFile {
                    openFile()
                    // openFile resets showOpenPanel itself when its NSOpenPanel
                    // completion runs, so no extra reset is needed here.
                }
            }
            .onChange(of: showImportCSVPanel) { _, newValue in
                if newValue {
                    importCSV()
                    DispatchQueue.main.async { showImportCSVPanel = false }
                }
            }
            .onChange(of: dataSyncManager.selectedCueStackIndex) { _, _ in
                clearCueSelection()
            }
            .onChange(of: dataSyncManager.selectedCueIndex) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    updateWebClients()
                }
            }
            .onChange(of: dataSyncManager.countdownPlaylist) { oldValue, newValue in
                timerServer.syncPlaylistState(newValue)
                // If playlist has current index, update timer target
                if let idx = newValue.currentIndex,
                   idx < newValue.entries.count {
                    let entry = newValue.entries[idx]
                    let command = TimerCommand(action: "setCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: entry.timeString)
                    timerServer.executeCommand(command)
                }
                // Mark document dirty unless this change came from a load.
                if !isLoadingFromDisk { markDirty() }
            }
            .onChange(of: dataSyncManager.cueStacks) { _, _ in
                if !isLoadingFromDisk { markDirty() }
            }
            .onChange(of: isDirty) { _, _ in
                updateWindowChrome()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PlaylistAdvanced"))) { notification in
                if let newIndex = notification.userInfo?["newIndex"] as? Int {
                    dataSyncManager.setCurrentPlaylistIndex(newIndex)
                    if newIndex < dataSyncManager.countdownPlaylist.entries.count {
                        let entry = dataSyncManager.countdownPlaylist.entries[newIndex]
                        let command = TimerCommand(action: "setCountdownToTime", countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: entry.timeString)
                        timerServer.executeCommand(command)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PlaylistIndexChanged"))) { notification in
                if let newIndex = notification.userInfo?["newIndex"] as? Int {
                    dataSyncManager.setCurrentPlaylistIndex(newIndex)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PlaylistCompleted"))) { _ in
                dataSyncManager.setPlaylistActive(false)
            }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
                autoSave()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TriggerPrint"))) { _ in
                printCueStacks()
            }
            .onAppear {
                setupAppDelegate()
                setupAppDelegateNotifications()

                if let url = appDelegate.pendingFileToOpen {
                    appDelegate.pendingFileToOpen = nil
                    hasExplicitlyOpenedFile = true
                    openDocumentAtURL(url)
                } else if !hasExplicitlyOpenedFile {
                    loadLastFile()
                }

                if !ContentViewLifecycleSetup.autoSaveObserverRegistered {
                    ContentViewLifecycleSetup.autoSaveObserverRegistered = true
                    NotificationCenter.default.addObserver(
                        forName: .autoSaveRequested,
                        object: nil,
                        queue: .main
                    ) { _ in
                        autoSave()
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    updateWebClients()
                    timerServer.syncPlaylistState(dataSyncManager.countdownPlaylist)
                }
                if ContentViewLifecycleSetup.keyEventMonitor == nil {
                    ContentViewLifecycleSetup.keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                        if handleKeyDown(event) {
                            return nil
                        }
                        return event
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                showSettings = false
            }
            .onDisappear {
                // Observer cleanup is handled automatically by NotificationCenter
                // when the view is deallocated
            }
    }
}
