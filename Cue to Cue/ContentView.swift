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
    @EnvironmentObject var appDelegate: AppDelegate
    /// Window-title name owned by the App scene; mirrored from `document`.
    @Binding var currentFileName: String

    // MARK: - Model
    @StateObject private var dataSyncManager: DataSyncManager
    /// Undo, selection, navigation and cue editing (see CueEditorController).
    @StateObject private var editor: CueEditorController
    /// The open show file: save/open/autosave/conflicts (see DocumentController).
    @StateObject private var document: DocumentController
    @StateObject private var websiteSyncManager = WebsiteSyncManager()
    /// Held in a box that never publishes, so 10 Hz timer ticks don't redraw
    /// this whole view; TopSectionView observes the server directly.
    @StateObject private var timerBox = TimerServerBox()
    private var timerServer: AuthoritativeTimerServer { timerBox.server }

    // MARK: - Presentation
    @State private var showSettings = false
    @Environment(\.openSettings) private var openSettingsWindow
    @State private var showConnectionMonitor = false
    @State private var showUserManagement = false
    @State private var showPlaylistEditor = false
    @State private var showWebsitePanel = false
    @State private var showAIImport = false
    @State private var showRestoreSheet = false
    @State private var showPrintSheet = false
    @State private var showCSVImportSheet = false
    @State private var pendingCSVImport: (sourceName: String, result: CueCSVImportResult)?
    @State private var showCSVExportSheet = false
    @State private var csvExportSelectedIndices: Set<Int> = []
    @State private var pendingCSVExportIndices: Set<Int>?
    @State private var printSelectedCueStackIndices: Set<Int> = []  // indices of cueStacks to print
    @State private var printFontSize: CGFloat = 12

    // MARK: - Table UI
    @State private var scrollViewProxy: ScrollViewProxy?
    @State private var isReorderingCues = false
    @State private var editingCueIndex: Int?
    @State private var cueStackListWidth: CGFloat = 150

    // MARK: - LAN server
    @State private var webServer: WebServer?
    @State private var authManager: AuthenticationManager?

    public init(currentFileName: Binding<String>) {
        self._currentFileName = currentFileName
        // All three objects must share one DataSyncManager. StateObject only
        // uses these values the first time the view is created.
        let data = DataSyncManager()
        let editor = CueEditorController(data: data)
        self._dataSyncManager = StateObject(wrappedValue: data)
        self._editor = StateObject(wrappedValue: editor)
        self._document = StateObject(wrappedValue: DocumentController(data: data, editor: editor))
    }

    /// File name without extension, for sheets and export names.
    private var currentFileStem: String {
        document.fileStem
    }

    private var currentSelectedStackName: String {
        let stacks = dataSyncManager.cueStacks
        let index = dataSyncManager.selectedCueStackIndex
        guard stacks.indices.contains(index) else { return "None" }
        return stacks[index].name
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
            .background(MainWindowCloseInterceptor())
            .onChange(of: showSettings) { _, show in
                // The Settings button opens the real Settings window.
                guard show else { return }
                showSettings = false
                openSettings(.general)
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
            .sheet(isPresented: $showWebsitePanel) {
                WebsiteSyncSettingsView(
                    publishCurrentShow: publishToWebsite,
                    currentShowName: document.fileName,
                    onClose: { showWebsitePanel = false }
                )
                .environmentObject(websiteSyncManager)
                .frame(width: 640, height: 640)
            }
            .sheet(isPresented: $showAIImport) {
                AIImportView(currentStacks: dataSyncManager.cueStacks,
                             onAdd: addGeneratedStack,
                             onClose: { showAIImport = false })
            }
            .sheet(isPresented: $showCSVExportSheet) {
                csvExportSheet
            }
            .onChange(of: showCSVExportSheet) { _, isShowing in
                guard !isShowing, let indices = pendingCSVExportIndices else { return }
                pendingCSVExportIndices = nil
                DispatchQueue.main.async {
                    performCSVExport(selectedIndices: indices)
                }
            }
            .sheet(isPresented: $showCSVImportSheet) {
                csvImportSheet
            }
            .onReceive(menuCommands) { handleMenuCommand($0) }
            #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: .debugSelectCue)) { note in
                if let index = note.object as? Int {
                    editor.handleCueSelection(at: index, withShiftKey: false, withCommandKey: false)
                }
            }
            #endif
            .focusedSceneObject(editor)
            .modifier(ContentViewLifecycleModifiers(
                dataSyncManager: dataSyncManager,
                timerServer: timerServer,
                document: document,
                clearCueSelection: { editor.clearSelection() },
                updateWebClients: updateWebClients,
                printCueStacks: printCueStacks,
                setupAppDelegate: setupAppDelegate,
                setupAppDelegateNotifications: setupAppDelegateNotifications,
                handleKeyDown: handleKeyDown,
                appDelegate: appDelegate,
                showSettings: $showSettings
            ))
            .onChange(of: settingsManager.settings.highlightColors) { _, _ in
                document.markDirty()
            }
            .onChange(of: document.fileName, initial: true) { _, name in
                currentFileName = name
            }
            // MARK: File alerts (state lives in DocumentController)
            .alert("This file changed outside of Cue to Cue", isPresented: $document.showConflictAlert) {
                Button("Reload from Disk", role: .destructive) {
                    document.reloadFromDiskAfterConflict()
                }
                Button("Keep My Version") {
                    document.forceOverwriteAfterConflict()
                }
                Button("Show in Finder") {
                    if let url = document.pendingConflictURL ?? document.lastSavedURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    // Re-arm so the alert can show again.
                    DispatchQueue.main.async { document.showConflictAlert = true }
                }
                Button("Cancel", role: .cancel) {
                    // documentChangedExternally stays set, so the next save still warns.
                }
            } message: {
                let name = (document.pendingConflictURL ?? document.lastSavedURL)?.lastPathComponent ?? currentFileStem
                Text("\(name) was modified by another program since you last saved. Reloading replaces your unsaved edits with the on-disk version. Keeping your version overwrites the on-disk version (a backup is kept in Application Support).")
            }
            .alert("Couldn't find your file", isPresented: $document.showMissingFileAlert) {
                Button("Locate File…") {
                    document.locateMissingFile()
                }
                Button("Save As…") {
                    document.saveFileAs()
                }
                Button("Continue Without a File", role: .cancel) {
                    document.abandonMissingFile()
                }
            } message: {
                let path = document.pendingConflictURL?.path ?? "(unknown)"
                Text("\(document.pendingConflictURL?.lastPathComponent ?? currentFileStem) couldn't be located at \(path). It may have been moved, renamed, or deleted in Finder or another app.")
            }
            .sheet(isPresented: $showRestoreSheet) {
                RestoreFromBackupView(
                    mainFileURL: document.lastSavedURL,
                    onRestore: { url in
                        showRestoreSheet = false
                        document.restoreFromBackup(at: url)
                    },
                    onCancel: {
                        showRestoreSheet = false
                    }
                )
            }
            .alert("Some backup destinations were unavailable", isPresented: $document.showBackupWarning) {
                Button("OK") {}
                Button("Show in Finder") {
                    document.revealBackupsInFinder()
                }
            } message: {
                Text("Your file saved successfully, but one or both backup copies reported an error:\n\n\(document.backupWarningDetail)\n\nYour data is still protected by the remaining backup.")
            }
            .onReceive(NotificationCenter.default.publisher(for: .appDelegateRestoreFromBackup)) { _ in
                showRestoreSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .appDelegateRevealBackups)) { _ in
                document.revealBackupsInFinder()
            }
    }
    
    // MARK: - Computed Properties
    
    private var mainContentView: some View {
        Group {
            GeometryReader { geometry in
                ZStack {
                    settingsManager.settings.backgroundColor.edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 0) {
                        VStack(spacing: 20) {
                            TopSectionView(
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
                                    selectedCueIndices: $editor.selectedCueIndices,
                                    selectedCueTime: $editor.selectedCueTime,
                                    settingsManager: settingsManager,
                                    appDelegate: appDelegate,
                                    updateWebClients: updateWebClients,
                                    onCueValueCommitted: notifyMacCueValueCommitted,
                                    saveState: { editor.recordEdit() },
                                    addCue: { editor.addCue() },
                                    advanceCue: { editor.advanceCue() },
                                    previousCue: { editor.previousCue() },
                                    highlightCue: { editor.highlightCue(at: $0) },
                                    parseCountdownTime: CueEditorController.parseCountdownTime,
                                    getHighlightColor: getHighlightColor,
                                    handleCueSelection: { editor.handleCueSelection(at: $0, withShiftKey: $1, withCommandKey: $2) },
                                    deleteSelectedCues: { editor.deleteSelectedCues() },
                                    copyCue: { editor.copyCues(at: [$0]) },
                                    pasteCue: { editor.pasteCues(after: $0) }
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
            documentName: currentFileStem,
            highlightColors: settingsManager.settings.highlightColors,
            onPrint: { configuration in
                self.runPrint(with: configuration)
            },
            onCancel: {
                showPrintSheet = false
            }
        )
    }

    @ViewBuilder
    private var csvExportSheet: some View {
        CSVExportSheetInline(
            selectedIndices: $csvExportSelectedIndices,
            cueStacks: dataSyncManager.cueStacks,
            sourceDocumentName: currentFileStem.isEmpty ? "Untitled Document" : currentFileStem,
            onExport: {
                pendingCSVExportIndices = csvExportSelectedIndices
                showCSVExportSheet = false
            },
            onCancel: {
                showCSVExportSheet = false
            }
        )
    }

    @ViewBuilder
    private var csvImportSheet: some View {
        if let pending = pendingCSVImport {
            CSVImportSheet(
                sourceName: pending.sourceName,
                importResult: pending.result,
                targetStackName: currentSelectedStackName,
                canMergeIntoSelected: dataSyncManager.cueStacks.indices.contains(dataSyncManager.selectedCueStackIndex),
                onImport: { action in
                    showCSVImportSheet = false
                    pendingCSVImport = nil
                    applyCSVImport(action: action, result: pending.result)
                },
                onCancel: {
                    showCSVImportSheet = false
                    pendingCSVImport = nil
                }
            )
        }
    }
    
    // MARK: - Helper Methods
    
    func updateWebClients() {
        // Ensures LAN server is running and highlight colors are synced.
        // Cue data pushes to browsers via WebSocket (Phase 4 observers + cue_patch).
        updateWebServer()
    }

    func notifyMacCueValueCommitted(cueId: UUID, columnIndex: Int, newValue: String) {
        dataSyncManager.recordMacCueValueChange(cueId: cueId, columnIndex: columnIndex, newValue: newValue)
    }
    
    /// File › Publish to Website: publish the open show and add it to the
    /// website's show library. Opens the Website panel if publishing isn't set up.
    private func publishToWebsite() {
        guard websiteSyncManager.hasToken, websiteSyncManager.hasViewerPassword else {
            showWebsitePanel = true
            return
        }
        // Commit any in-progress cell edit first.
        NSApp.keyWindow?.makeFirstResponder(nil)
        websiteSyncManager.syncCueData(
            cueStacks: dataSyncManager.cueStacks,
            selectedCueStackIndex: dataSyncManager.selectedCueStackIndex,
            filename: document.fileName,
            settingsManager: settingsManager
        ) { success, error in
            if !success, let error {
                let alert = NSAlert()
                alert.messageText = "Couldn't Publish to the Website"
                alert.informativeText = error
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Website Settings…")
                if alert.runModal() == .alertSecondButtonReturn {
                    showWebsitePanel = true
                }
            }
        }
    }

    private func updateWebServer() {
        let colors = settingsManager.settings.highlightColors
        if colors != dataSyncManager.highlightColors {
            dataSyncManager.updateHighlightColors(colors)
        }

        if let shared = ContentViewLifecycleSetup.sharedWebServer {
            if webServer == nil {
                webServer = shared
                authManager = shared.authManager
            }
            return
        }

        guard !ContentViewLifecycleSetup.webServerStarted else { return }
        ContentViewLifecycleSetup.webServerStarted = true

        let server = WebServer(dataSyncManager: dataSyncManager, timerServer: timerServer)
        ContentViewLifecycleSetup.sharedWebServer = server
        webServer = server
        authManager = server.authManager
        server.start(port: 8080)
    }
    
    func getWebUpdateInfo() -> (cueStacks: [CueStack], selectedIndex: Int, activeIndex: Int) {
        return (dataSyncManager.cueStacks, dataSyncManager.selectedCueStackIndex, dataSyncManager.selectedCueIndex)
    }
    
    private func setupAppDelegate() {
        // Most communication goes through NotificationCenter; quitting needs a
        // reply, so it uses a callback.
        appDelegate.prepareForTermination = { completion in
            self.document.prepareForQuit(completion)
        }
        editor.notifyWebClients = { self.updateWebClients() }
        document.settingsManager = settingsManager
        document.notifyWebClients = { self.updateWebClients() }
        document.onDocumentLoaded = {
            self.websiteSyncManager.autoSyncIfEnabled(
                cueStacks: self.dataSyncManager.cueStacks,
                selectedCueStackIndex: self.dataSyncManager.selectedCueStackIndex,
                filename: self.document.fileName,
                settingsManager: self.settingsManager
            )
        }
        document.onNewDocument = {
            self.editingCueIndex = nil
            for action in ["pause", "reset", "pauseCountdownToTime"] {
                self.timerServer.executeCommand(TimerCommand(action: action, countdownTime: nil, countUpTime: nil, adjustment: nil, targetTimeString: nil))
            }
        }
    }

    
    /// Menu commands arrive from AppDelegate as notifications. They are
    /// received with `onReceive` (see `body`), so they run on the main actor,
    /// are tied to this view's lifetime, and can never be registered twice.
    private func setupAppDelegateNotifications() {
        // AppDelegate only posts Finder "open file" requests once this is set;
        // before that it queues them in `pendingFileToOpen`.
        ContentViewLifecycleSetup.appDelegateNotificationsRegistered = true
    }

    private static let menuCommandNames: [Notification.Name] = [
        .appDelegateNewFile, .appDelegateOpenFile, .appDelegateSaveFile,
        .appDelegateSaveFileAs, .appDelegateDuplicateFile,
        .appDelegateImportCSV, .appDelegateExportCSV,
        .appDelegatePublishWebsite, .appDelegateShowWebsite, .appDelegateShowAIImport,
        .appDelegateUndo, .appDelegateRedo,
        .appDelegateCut, .appDelegateCopy, .appDelegatePaste, .appDelegateDelete,
        .appDelegateSelectAll, .appDelegateToggleStrikeThrough,
        .appDelegateShowPreferences, .appDelegateUpdateWebClients,
        .appDelegateShowCommand, .appDelegateShowViewers, .appDelegateShowUsers,
        .appDelegateShowShortcuts,
    ]

    private var menuCommands: AnyPublisher<Notification, Never> {
        Publishers.MergeMany(Self.menuCommandNames.map { NotificationCenter.default.publisher(for: $0) })
            .eraseToAnyPublisher()
    }

    private func openSettings(_ tab: SettingsView.Tab) {
        UserDefaults.standard.set(tab.rawValue, forKey: SettingsView.selectedTabKey)
        openSettingsWindow()
    }

    private func handleMenuCommand(_ note: Notification) {
        switch note.name {
        // File
        case .appDelegateNewFile: document.newFile()
        case .appDelegateOpenFile:
            if let url = note.object as? URL {
                document.hasExplicitlyOpenedFile = true
                appDelegate.pendingFileToOpen = nil
                document.beginOpeningDocument(at: url)
            } else {
                document.openFile()
            }
        case .appDelegateSaveFile: document.saveFile()
        case .appDelegateSaveFileAs: document.saveFileAs()
        case .appDelegateDuplicateFile: document.duplicateFile()
        case .appDelegateImportCSV: importCSV()
        case .appDelegateExportCSV: exportCSV()
        case .appDelegatePublishWebsite: publishToWebsite()
        case .appDelegateShowWebsite: showWebsitePanel = true
        case .appDelegateShowAIImport: showAIImport = true
        // Edit
        case .appDelegateUndo: editor.undo()
        case .appDelegateRedo: editor.redo()
        case .appDelegateCut: editor.cutSelection()
        case .appDelegateCopy: editor.copySelection()
        case .appDelegatePaste: editor.paste()
        case .appDelegateDelete: editor.deleteSelectedCues()
        case .appDelegateSelectAll: editor.selectAll()
        case .appDelegateToggleStrikeThrough: editor.toggleStrikeThrough()
        // Other
        case .appDelegateShowPreferences: openSettings(.general)
        case .appDelegateShowShortcuts: openSettings(.shortcuts)
        case .appDelegateShowViewers: showConnectionMonitor = true
        case .appDelegateShowUsers: showUserManagement = true
        case .appDelegateShowCommand:
            if let id = note.object as? String { handleShortcutAction(id) }
        case .appDelegateUpdateWebClients: updateWebClients()
        default: break
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
        // Safety net: if a cell editor closed without telling us, don't leave
        // arrow-key cue navigation disabled.
        if editingCueIndex != nil, !(NSApp.keyWindow?.firstResponder is NSTextView) {
            editingCueIndex = nil
        }
        guard editingCueIndex == nil else { return false }
        
        // Check for customizable keyboard shortcuts first
        if let matchedShortcut = findMatchingShortcut(event: event, in: settingsManager.shortcutsManager) {
            // Menu shortcuts should be handled by the menu system, not intercepted here
            // Everything with a menu item is handled by the menu bar, which
            // shows the shortcut; only arrow-key navigation stays here.
            let menuShortcutIds = ["new", "open", "save", "saveAs", "duplicate", "importCSV", "exportCSV", "publishWebsite", "print", "undo", "redo", "cut", "copy", "paste", "delete", "selectAll", "toggleStrikeThrough", "toggleFullScreen", "preferences", "quit",
                                   "nextCue", "previousCue", "addCue",
                                   "countdownStart", "countdownPause", "countdownReset", "countdownPlus1Min", "countdownMinus1Min",
                                   "countdownToTimeStart", "countdownToTimePause", "countdownToTimeNext", "countdownPlaylist"]
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
            editor.previousCue()
            return true
        case 125: // Down arrow
            editor.advanceCue()
            return true
        default:
            break
        }
        return false
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
            editor.addCue()
        case "nextCue":
            editor.advanceCue()
        case "previousCue":
            editor.previousCue()
        
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
                    self.applyCSVImport(from: data, sourceName: url.lastPathComponent)
                } catch {
                    self.showCSVImportError(
                        messageText: "Could not read CSV file",
                        informativeText: error.localizedDescription
                    )
                }
            }
        }
    }

    private func applyCSVImport(from data: Data, sourceName: String) {
        let result: CueCSVImportResult
        do {
            result = try CueCSVCodec.decode(data: data)
        } catch {
            showCSVImportError(
                messageText: "Could not import CSV",
                informativeText: error.localizedDescription
            )
            return
        }

        guard !result.stacks.isEmpty else {
            showCSVImportError(
                messageText: "Nothing to import",
                informativeText: "The CSV file does not contain any cue rows."
            )
            return
        }

        pendingCSVImport = (sourceName: sourceName, result: result)
        showCSVImportSheet = true
    }

    /// Adds a stack Claude wrote (after the user reviewed it), selects it,
    /// and records it so Undo removes it again.
    private func addGeneratedStack(_ stack: CueStack) {
        let toAdd = CueCSVCodec.stacksForAdd(imported: [stack], existingNames: dataSyncManager.cueStacks.map(\.name))
        guard !toAdd.isEmpty else { return }
        dataSyncManager.cueStacks.append(contentsOf: toAdd)
        dataSyncManager.selectedCueStackIndex = dataSyncManager.cueStacks.count - 1
        dataSyncManager.selectedCueIndex = -1
        editor.clearSelection()
        editingCueIndex = nil
        editor.recordEdit()
    }

    private func applyCSVImport(action: CSVImportAction, result: CueCSVImportResult) {
        switch action.kind {
        case .importOneStack(let stackName):
            guard let stack = result.stacks.first(where: { $0.name == stackName }) else {
                showCSVImportError(
                    messageText: "Could not import CSV",
                    informativeText: "The selected stack could not be found in the imported file."
                )
                return
            }

            let stacksToAdd = CueCSVCodec.stacksForAdd(
                imported: [stack],
                existingNames: dataSyncManager.cueStacks.map(\.name)
            )
            dataSyncManager.cueStacks.append(contentsOf: stacksToAdd)
            editor.recordEdit()

        case .addStacks:
            let stacksToAdd = CueCSVCodec.stacksForAdd(
                imported: result.stacks,
                existingNames: dataSyncManager.cueStacks.map(\.name)
            )
            dataSyncManager.cueStacks.append(contentsOf: stacksToAdd)
            editor.recordEdit()

        case .replaceAll:
            guard !result.stacks.isEmpty else {
                showCSVImportError(
                    messageText: "Could not import CSV",
                    informativeText: "The file contains no cue stacks, so nothing was replaced."
                )
                return
            }
            dataSyncManager.cueStacks = result.stacks
            dataSyncManager.selectedCueStackIndex = 0
            dataSyncManager.selectedCueIndex = -1
            editor.clearSelection()
            editingCueIndex = nil
            // Undoable: Replace All wipes every stack, so keep it in history.
            editor.recordEdit()

        case .mergeIntoSelected(let sourceStackName):
            guard dataSyncManager.cueStacks.indices.contains(dataSyncManager.selectedCueStackIndex),
                  let importedStack = result.stacks.first(where: { $0.name == sourceStackName }) else {
                showCSVImportError(
                    messageText: "Could not merge CSV",
                    informativeText: "The selected stack or imported stack could not be found."
                )
                return
            }

            let index = dataSyncManager.selectedCueStackIndex
            dataSyncManager.cueStacks[index] = CueCSVCodec.mergedStack(
                existing: dataSyncManager.cueStacks[index],
                imported: importedStack
            )
            editor.recordEdit()
        }

        document.markDirty()
        updateWebClients()
    }

    private func showCSVImportError(messageText: String, informativeText: String) {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - CSV Export (redundancy export)

    /// Export selected cue stacks into a single CSV file. Designed as a
    /// human-readable redundancy artifact: open it in Excel/Numbers, archive
    /// it, attach it to email, drag a copy to a USB stick. Writes are
    /// atomic + coordinated so a CSV file on iCloud Drive can't be
    /// corrupted by a sync engine mid-export.
    func exportCSV() {
        guard !dataSyncManager.cueStacks.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "Nothing to export"
            alert.informativeText = "There are no cue stacks in this document yet."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        csvExportSelectedIndices = Set(dataSyncManager.cueStacks.indices)
        showCSVExportSheet = true
    }

    private func performCSVExport(selectedIndices: Set<Int>) {
        let stacks = selectedIndices.sorted().compactMap { index -> CueStack? in
            guard dataSyncManager.cueStacks.indices.contains(index) else { return nil }
            return dataSyncManager.cueStacks[index]
        }
        guard !stacks.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export CSV"
        panel.message = stacks.count == 1
            ? "Export \"\(stacks[0].name)\" to a CSV file."
            : "Export \(stacks.count) cue stacks to a single CSV file."
        panel.nameFieldStringValue = suggestedCSVExportFilename(for: stacks)

        let proceed: (URL) -> Void = { url in
            do {
                let data = CueCSVCodec.encode(stacks: stacks)
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
                print("✅ CSV exported to \(url.path) (\(data.count) bytes, \(stacks.count) stack\(stacks.count == 1 ? "" : "s"))")
            } catch {
                print("❌ CSV export failed: \(error.localizedDescription)")
                self.document.showSaveError(error: error)
            }
        }

        panel.begin { response in
            if response == .OK, let url = panel.url {
                proceed(url)
            }
        }
    }

    private func suggestedCSVExportFilename(for stacks: [CueStack]) -> String {
        if stacks.count == 1 {
            let stackName = stacks[0].name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stackName.isEmpty {
                return sanitizedCSVFilename(stackName) + ".csv"
            }
        }

        let trimmedStem = currentFileStem.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitizedCSVFilename(trimmedStem.isEmpty ? "Cue Stacks" : trimmedStem) + ".csv"
    }

    private func sanitizedCSVFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Cue Stacks" : cleaned
    }

    func getHighlightColor(for cue: Cue) -> Color {
        for highlight in settingsManager.settings.highlightColors {
            if cue.values.contains(where: { $0.lowercased().contains(highlight.keyword.lowercased()) }) {
                return highlight.color
            }
        }
        return settingsManager.settings.fontColor
    }
    
    // MARK: - Printing Functionality
    
    /// Call this function (for example, from your File > Print menu) to show the print options.
    func printCueStacks() {
        if dataSyncManager.cueStacks.isEmpty {
            printSelectedCueStackIndices = []
        } else {
            printSelectedCueStackIndices = [0]
        }
        showPrintSheet = true
    }
    
    /// Called by the print settings sheet to perform printing.
    func runPrint(with configuration: PrintConfiguration) {
        PrintLayoutBuilder.performPrint(
            configuration: configuration,
            allCueStacks: dataSyncManager.cueStacks
        )
    }
}

/// One-time lifecycle guards. ContentView is a struct; static state tracks
/// observers/monitors that must not be registered more than once.
enum ContentViewLifecycleSetup {
    static var appDelegateNotificationsRegistered = false
    static var keyEventMonitor: Any?
    static var didCompleteLaunchSetup = false
    static var webServerStarted = false
    static weak var sharedWebServer: WebServer?
}

/// Process-wide LAN log deduplication so duplicate ContentView instances
/// or listener callbacks cannot spam the console.
enum LANLogState {
    static var hasLoggedServerReady = false
    static var lastLoggedViewerCount = -1
}

/// File ▸ Export CSV…: choose which cue stacks go into the CSV file.
private struct CSVExportSheetInline: View {
    @Binding var selectedIndices: Set<Int>
    let cueStacks: [CueStack]
    let sourceDocumentName: String
    let onExport: () -> Void
    let onCancel: () -> Void

    private var selectedCueCount: Int {
        selectedIndices.reduce(0) { total, index in
            cueStacks.indices.contains(index) ? total + cueStacks[index].cues.count : total
        }
    }

    private var exportTitle: String {
        switch selectedIndices.count {
        case 0: return "Export"
        case 1: return "Export 1 Stack"
        case cueStacks.count: return "Export All \(cueStacks.count) Stacks"
        default: return "Export \(selectedIndices.count) Stacks"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(systemImage: "tablecells",
                        title: "Export CSV",
                        subtitle: "Save cue stacks from \u{201C}\(sourceDocumentName)\u{201D} as a spreadsheet file for Numbers, Excel or Google Sheets.",
                        tint: .green)
            Form {
                Section {
                    ForEach(cueStacks.indices, id: \.self) { index in
                        Toggle(isOn: binding(for: index)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cueStacks[index].name).fontWeight(.medium)
                                Text("\(cueStacks[index].cues.count) cues · \(cueStacks[index].columns.map(\.name).joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                } header: {
                    HStack {
                        Text("Stacks")
                        Spacer()
                        Button("Select All") { selectedIndices = Set(cueStacks.indices) }
                            .controlSize(.small)
                            .disabled(selectedIndices.count == cueStacks.count)
                        Button("Select None") { selectedIndices = [] }
                            .controlSize(.small)
                            .disabled(selectedIndices.isEmpty)
                    }
                } footer: {
                    Text(selectedIndices.count == 1
                         ? "One stack makes a simple CSV you can import into another show."
                         : "Several stacks go into one file, one after another, and import back as separate stacks.")
                }
            }
            .formStyle(.grouped)
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Text(selectedIndices.isEmpty ? "Choose at least one stack." : "\(selectedIndices.count) of \(cueStacks.count) stacks · \(selectedCueCount) cues")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button(exportTitle + "\u{2026}", action: onExport)
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedIndices.isEmpty)
                }
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(.bar)
        }
        .frame(width: 560, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func binding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { selectedIndices.contains(index) },
            set: { isOn in
                if isOn { selectedIndices.insert(index) } else { selectedIndices.remove(index) }
            }
        )
    }
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

/// Owns the timer server without forwarding its changes (see ContentView).
final class TimerServerBox: ObservableObject {
    let server = AuthoritativeTimerServer()
}

// MARK: - View Modifier for ContentView Lifecycle

struct ContentViewLifecycleModifiers: ViewModifier {
    let dataSyncManager: DataSyncManager
    let timerServer: AuthoritativeTimerServer
    let document: DocumentController
    let clearCueSelection: () -> Void
    let updateWebClients: () -> Void
    let printCueStacks: () -> Void
    let setupAppDelegate: () -> Void
    let setupAppDelegateNotifications: () -> Void
    let handleKeyDown: (NSEvent) -> Bool
    let appDelegate: AppDelegate
    @Binding var showSettings: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: dataSyncManager.selectedCueStackIndex) { _, _ in
                dataSyncManager.syncWebClientWithMacOSApp()
                clearCueSelection()
                updateWebClients()
            }
            .onChange(of: dataSyncManager.selectedCueIndex) { _, _ in
                dataSyncManager.syncWebClientWithMacOSApp()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    updateWebClients()
                }
            }
            .onChange(of: dataSyncManager.countdownPlaylist) { oldValue, newValue in
                guard oldValue != newValue else { return }
                timerServer.syncPlaylistState(newValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PlaylistAdvanced"))) { notification in
                if let newIndex = notification.userInfo?["newIndex"] as? Int {
                    dataSyncManager.setCurrentPlaylistIndex(newIndex)
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
                document.autoSave()
            }
            .onReceive(NotificationCenter.default.publisher(for: .autoSaveRequested)) { _ in
                document.autoSave()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TriggerPrint"))) { _ in
                printCueStacks()
            }
            .onAppear {
                setupAppDelegate()
                setupAppDelegateNotifications()

                if ContentViewLifecycleSetup.keyEventMonitor == nil {
                    ContentViewLifecycleSetup.keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                        if handleKeyDown(event) {
                            return nil
                        }
                        return event
                    }
                }

                guard !ContentViewLifecycleSetup.didCompleteLaunchSetup else { return }
                ContentViewLifecycleSetup.didCompleteLaunchSetup = true

                if let url = appDelegate.pendingFileToOpen {
                    // Opened from Finder: open that file instead of the last one.
                    appDelegate.pendingFileToOpen = nil
                    document.hasExplicitlyOpenedFile = true
                    document.beginOpeningDocument(at: url)
                    document.ensureDocumentHasAStack()
                } else if !document.hasExplicitlyOpenedFile {
                    document.loadLastFile()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    updateWebClients()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
                showSettings = false
            }
    }
}
