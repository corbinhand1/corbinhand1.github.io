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
    @StateObject private var settingsManager = SettingsManager()
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
    @State private var selectedCueTime: Int?
    @State var showSavePanel = false
    @State var showOpenPanel = false
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

    private var displayFileName: String {
        currentFileName.hasSuffix(".json")
            ? String(currentFileName.dropLast(5))
            : currentFileName
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
                                showSettings: $showSettings,
                                showConnectionMonitor: $showConnectionMonitor,
                                showUserManagement: $showUserManagement,
                                currentFileName: $currentFileName,
                                updateWebClients: updateWebClients
                            )
                            .environmentObject(settingsManager)
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
                                    deleteSelectedCues: deleteSelectedCues
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
        .environmentObject(settingsManager)
        .sheet(isPresented: $showSettings) {
            SettingsView(settingsManager: settingsManager)
        }
        .sheet(isPresented: $showConnectionMonitor) {
            connectionMonitorSheet
        }
        .sheet(isPresented: $showUserManagement) {
            userManagementSheet
        }
        // Present the print settings sheet when requested.
        .sheet(isPresented: $showPrintSheet) {
            printSettingsSheet
        }
        .onChange(of: showSavePanel) { _, newValue in
            if newValue { saveFile() }
        }
        .onChange(of: showOpenPanel) { _, newValue in
            if newValue { openFile() }
        }
        .onChange(of: showImportCSVPanel) { _, newValue in
            if newValue { importCSV() }
        }
        .onChange(of: dataSyncManager.selectedCueStackIndex) { _, _ in
            clearCueSelection()
        }
        .onChange(of: dataSyncManager.selectedCueIndex) { _, _ in
            // Debounce web client updates to prevent interference with drag operations
            // Use a small delay to allow drag gestures to complete smoothly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                updateWebClients()
            }
        }
        // Autosave every 30 seconds.
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            autoSave()
        }
        // Listen for the "TriggerPrint" notification to launch printing.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TriggerPrint"))) { _ in
            printCueStacks()
        }
        .onAppear {
            setupAppDelegate()
            
            // Load last saved file on startup
            loadLastFile()
            
            // Set up auto-save notification listener
            NotificationCenter.default.addObserver(
                forName: .autoSaveRequested,
                object: nil,
                queue: .main
            ) { _ in
                self.autoSave()
            }
            
            // Initialize web server with current timer values after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                updateWebClients()
            }
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if self.handleKeyDown(with: event) {
                    return nil
                }
                return event
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            showSettings = false
        }
        .onDisappear {
            // Remove notification observer
            NotificationCenter.default.removeObserver(self, name: .autoSaveRequested, object: nil)
        }
    }
    
    // MARK: - Computed Properties
    
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
            webServer = WebServer(dataSyncManager: dataSyncManager)
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
        appDelegate.contentView = self
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
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                // If there's text selected in a text field, let the text field handle it
                if hasTextSelectionInFirstResponder() {
                    return false  // Don't intercept, let the text field handle Cmd+C
                }
                // Otherwise, copy the cue data as before
                copy(nil)
                return true
            case "v":
                // If there's a text field with focus, let it handle the paste
                if let firstResponder = NSApp.keyWindow?.firstResponder,
                   (firstResponder is NSTextView || firstResponder is NSTextField) {
                    return false  // Don't intercept, let the text field handle Cmd+V
                }
                // Otherwise, paste cue data as before
                paste(nil)
                return true
            case "a":
                selectAllCues()
                return true
            case "s":
                // Toggle strike-through for selected cue
                if let selectedIndex = getSelectedCueIndices()?.first {
                    let cueId = dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues[selectedIndex].id
                    Task {
                        await dataSyncManager.toggleStrikeThrough(cueId: cueId)
                    }
                }
                return true
            default:
                break
            }
        }
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
        saveState()
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
        // Add the cue first
        let newCue = Cue(values: Array(repeating: "", count: dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].columns.count))
        dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.append(newCue)
        
        // Then save the state with the new cue included
        saveState()
        
        // Update web clients
        self.appDelegate.updateWebClients()
        
        print("➕ Added cue #\(dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues.count) with ID: \(newCue.id)")
    }
    
    // MARK: - File Saving Methods
    
    func saveFile() {
        if let url = lastSavedURL {
            saveToURL(url)
        } else {
            saveFileAs()
        }
    }
    
    func saveToURL(_ url: URL) {
        do {
            let savedData = SavedData(
                cueStacks: self.dataSyncManager.cueStacks,
                highlightColors: self.settingsManager.settings.highlightColors,
                pdfNotes: self.pdfNotes
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(savedData)
            try data.write(to: url)
            self.currentFileName = url.lastPathComponent
            print("File saved successfully at \(url.path)")
            self.appDelegate.updateWebClients()
        } catch {
            print("Error saving file: \(error.localizedDescription)")
            showSaveError(error: error)
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
    
    func saveFileAs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.json]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save Cue Stack"
        savePanel.message = "Choose a location to save your cue stack"
        savePanel.nameFieldStringValue = "CueStack.json"
        guard let window = NSApp.windows.first else { return }
        savePanel.beginSheetModal(for: window) { response in
            if response == .OK, let url = savePanel.url {
                self.lastSavedURL = url
                self.saveDocument(to: url)
                UserDefaults.standard.set(url, forKey: "LastSavedURL")
            }
        }
    }
    
    func saveDocument(to url: URL) {
        let savedData = SavedData(
            cueStacks: dataSyncManager.cueStacks,
            highlightColors: settingsManager.settings.highlightColors,
            pdfNotes: self.pdfNotes
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(savedData)
            try data.write(to: url)
            print("File saved successfully at \(url)")
            currentFileName = url.lastPathComponent
            updateWebClients()
        } catch {
            print("Error saving file: \(error.localizedDescription)")
            showSaveError(error: error)
        }
    }
    
    // MARK: - Autosave Functionality
    func autoSave() {
        if let url = lastSavedURL {
            saveToURL(url)
            print("Autosaved to \(url.path)")
        } else {
            let tempDir = NSTemporaryDirectory()
            let tempURL = URL(fileURLWithPath: tempDir).appendingPathComponent("CueStack_Autosave.json")
            saveToURL(tempURL)
            print("Autosaved to temporary file \(tempURL.path)")
        }
    }
    
    func openFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    let savedData = try decoder.decode(SavedData.self, from: data)
                    self.dataSyncManager.cueStacks = savedData.cueStacks
                    self.settingsManager.settings.highlightColors = savedData.highlightColors
                    self.pdfNotes = savedData.pdfNotes
                    self.lastSavedURL = url
                    self.currentFileName = url.lastPathComponent
                    UserDefaults.standard.set(url, forKey: "LastSavedURL")
                    print("File opened successfully: \(url.path)")
                    self.updateWebClients()
                    
                    // Auto-sync to website if enabled
                    self.websiteSyncManager.autoSyncIfEnabled(
                        cueStacks: self.dataSyncManager.cueStacks,
                        selectedCueStackIndex: self.dataSyncManager.selectedCueStackIndex,
                        filename: self.currentFileName,
                        settingsManager: self.settingsManager
                    )
                } catch {
                    print("Error reading file: \(error.localizedDescription)")
                    self.showOpenError(error: error)
                }
            }
        }
    }
    
    func loadLastFile() {
        // Only load files on app startup, never during runtime
        // This prevents overwriting web changes
        
        print("🔍 loadLastFile() called")
        
        // Check if there's a last saved URL in UserDefaults
        if let lastURL = UserDefaults.standard.url(forKey: "LastSavedURL") {
            print("🔍 Found LastSavedURL: \(lastURL.path)")
            // Check if the file still exists
            if FileManager.default.fileExists(atPath: lastURL.path) {
                print("🔍 File exists, loading...")
                do {
                    let data = try Data(contentsOf: lastURL)
                    let decoder = JSONDecoder()
                    let savedData = try decoder.decode(SavedData.self, from: data)
                    
                    print("🔍 Loaded \(savedData.cueStacks.count) cue stacks")
                    if let firstStack = savedData.cueStacks.first {
                        print("🔍 First stack: \(firstStack.name) with \(firstStack.cues.count) cues")
                    }
                    
                    // Only load the file if it has valid data (non-empty cue stacks)
                    if !savedData.cueStacks.isEmpty {
                        print("✅ File has valid data, loading...")
                        dataSyncManager.cueStacks = savedData.cueStacks
                    } else {
                        print("⚠️ File is empty, keeping test data")
                    }
                    settingsManager.settings.highlightColors = savedData.highlightColors
                    pdfNotes = savedData.pdfNotes
                    lastSavedURL = lastURL
                    currentFileName = lastURL.lastPathComponent
                    print("✅ Loaded last file: \(lastURL.path)")
                    updateWebClients()
                    
                    // Auto-sync to website if enabled
                    websiteSyncManager.autoSyncIfEnabled(
                        cueStacks: dataSyncManager.cueStacks,
                        selectedCueStackIndex: dataSyncManager.selectedCueStackIndex,
                        filename: currentFileName,
                        settingsManager: settingsManager
                    )
                } catch {
                    print("❌ Error loading last file: \(error.localizedDescription)")
                    // If auto-load fails, continue with default state
                }
            } else {
                print("❌ Last saved file no longer exists: \(lastURL.path)")
                // Clear the stored URL if file doesn't exist
                UserDefaults.standard.removeObject(forKey: "LastSavedURL")
            }
        } else {
            print("⚠️ No last saved file found in UserDefaults, starting with default state")
        }
    }
    
    func showOpenError(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Error Opening File"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
                    saveState()
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
    
    func saveState() {
        guard dataSyncManager.cueStacks.indices.contains(dataSyncManager.selectedCueStackIndex) else { return }
        let currentStack = dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex]
        
        // Create a unique state with timestamp
        let currentState = (columns: currentStack.columns, cues: currentStack.cues, timestamp: Date().timeIntervalSince1970)
        
        if currentStateIndex < stateHistory.count - 1 {
            stateHistory = Array(stateHistory.prefix(upTo: currentStateIndex + 1))
        }
        stateHistory.append(currentState)
        currentStateIndex += 1
        print("💾 Saved state #\(currentStateIndex) with \(currentState.cues.count) cues")
    }
    
    func undo() {
        guard currentStateIndex > 0 else { return }
        currentStateIndex -= 1
        let previousState = stateHistory[currentStateIndex]
        dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].columns = previousState.columns
        dataSyncManager.cueStacks[dataSyncManager.selectedCueStackIndex].cues = previousState.cues
        print("↩️ Undo to state #\(currentStateIndex) with \(previousState.cues.count) cues")
        self.appDelegate.updateWebClients()
    }
    
    func redo() {
        guard currentStateIndex < stateHistory.count - 1 else { return }
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
                saveState()
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
                self.appDelegate.updateWebClients()
            } else if let transferCue = try? decoder.decode(TransferCue.self, from: data) {
                saveState()
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
                self.appDelegate.updateWebClients()
            } else if let decodedCue = try? decoder.decode(Cue.self, from: data) {
                saveState()
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
