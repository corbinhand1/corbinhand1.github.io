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
    @State private var currentTime = Date()
    @State private var countdownTime = 300
    @State private var countUpTime = 0
    @State private var countdownRunning = true
    @State private var countUpRunning = false
    @State private var cueStacks = [
        CueStack(
            name: "Cue Stack 1",
            cues: [Cue(values: ["Example Cue"])],
            columns: [Column(name: "Column 1", width: 100)]
        )
    ]
    @State private var selectedCueStackIndex: Int = 0
    @State private var showSettings = false
    @State private var selectedCueIndex: Int?
    @State private var selectedCueTime: Int?
    @State var showSavePanel = false
    @State var showOpenPanel = false
    @State var showImportCSVPanel = false
    @EnvironmentObject var appDelegate: AppDelegate
    @Binding var currentFileName: String

    @State private var scrollViewProxy: ScrollViewProxy?
    @State private var stateHistory: [(columns: [Column], cues: [Cue])] = []
    @State private var currentStateIndex = -1
    @State private var isReorderingCues = false
    @State private var editingCueIndex: Int?
    @State private var cueStackListWidth: CGFloat = 150 // Default width
    @State private var lastSavedURL: URL?
    @State private var keynotePreviewWindow: NSWindow?
    @State private var lastUpdateTime = Date()
    @State var pdfNotes: [String: [Int: String]] = [:]
    @State private var webServer: WebServer?

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
                guard cueStacks.indices.contains(selectedCueStackIndex) else {
                    return CueStack(name: "Invalid", cues: [], columns: [])
                }
                return cueStacks[selectedCueStackIndex]
            },
            set: { newValue in
                guard cueStacks.indices.contains(selectedCueStackIndex) else { return }
                cueStacks[selectedCueStackIndex] = newValue
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
                                currentTime: $currentTime,
                                countdownTime: $countdownTime,
                                countdownRunning: $countdownRunning,
                                showSettings: $showSettings,
                                updateWebClients: updateWebClients
                            )
                            .environmentObject(settingsManager)
                            
                            HStack(alignment: .top, spacing: 0) {
                                VStack(alignment: .leading, spacing: 0) {
                                    CueStackListView(
                                        cueStacks: $cueStacks,
                                        selectedCueStackIndex: $selectedCueStackIndex,
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
                                    selectedCueIndex: $selectedCueIndex,
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
        // Present the print settings sheet when requested.
        .sheet(isPresented: $showPrintSheet) {
            PrintSettingsView(selectedIndices: $printSelectedCueStackIndices, fontSize: $printFontSize, cueStacks: cueStacks, onPrint: {
                self.performPrintAction()
            })
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
        .onChange(of: selectedCueStackIndex) { _, _ in
            clearCueSelection()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            updateWebClients()
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
    }
    
    // MARK: - Helper Methods
    
    func updateWebClients() {
        updateWebServer()
    }
    
    private func updateWebServer() {
        // Web server update implementation
        if webServer == nil {
            webServer = WebServer()
            webServer?.start(port: 8080)
        }
        webServer?.updateCues(cueStacks: cueStacks, selectedCueStackIndex: selectedCueStackIndex, activeCueIndex: selectedCueIndex ?? -1, selectedCueIndex: selectedCueIndex ?? -1)
        webServer?.updateClockState(currentTime: currentTime, countdownTime: countdownTime, countUpTime: countUpTime, countdownRunning: countdownRunning, countUpRunning: countUpRunning)
    }
    
    func getWebUpdateInfo() -> (cueStacks: [CueStack], selectedIndex: Int, activeIndex: Int) {
        return (cueStacks, selectedCueStackIndex, selectedCueIndex ?? -1)
    }
    
    private func setupAppDelegate() {
        appDelegate.contentView = self
    }
    
    private func handleKeyDown(with event: NSEvent) -> Bool {
        guard editingCueIndex == nil else { return false }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                copy(nil)
                return true
            case "v":
                paste(nil)
                return true
            case "a":
                selectAllCues()
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
        guard cueStacks.indices.contains(selectedCueStackIndex),
              index >= 0 && index < cueStacks[selectedCueStackIndex].cues.count else {
            return
        }
        if withCommandKey {
            isMultiSelectMode = true
            if selectedCueIndices.contains(index) {
                selectedCueIndices.remove(index)
                if selectedCueIndices.isEmpty {
                    isMultiSelectMode = false
                    selectedCueIndex = nil
                }
            } else {
                selectedCueIndices.insert(index)
                selectedCueIndex = index
            }
        } else if withShiftKey && lastSelectedIndex != nil {
            isMultiSelectMode = true
            let start = min(lastSelectedIndex!, index)
            let end = max(lastSelectedIndex!, index)
            for i in start...end {
                if i >= 0 && i < cueStacks[selectedCueStackIndex].cues.count {
                    selectedCueIndices.insert(i)
                }
            }
            selectedCueIndex = index
        } else {
            if isMultiSelectMode {
                selectedCueIndices.removeAll()
                isMultiSelectMode = false
            }
            selectedCueIndex = index
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
        } else if let selectedIndex = selectedCueIndex {
            return [selectedIndex]
        }
        return nil
    }
    
    func clearCueSelection() {
        selectedCueIndices.removeAll()
        isMultiSelectMode = false
        lastSelectedIndex = nil
    }
    
    func selectAllCues() {
        guard cueStacks.indices.contains(selectedCueStackIndex) else { return }
        let cueCount = cueStacks[selectedCueStackIndex].cues.count
        if cueCount > 0 {
            isMultiSelectMode = true
            selectedCueIndices = Set(0..<cueCount)
            if let selectedIndex = selectedCueIndex {
                lastSelectedIndex = selectedIndex
            } else {
                selectedCueIndex = 0
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
            if index < cueStacks[selectedCueStackIndex].cues.count {
                cueStacks[selectedCueStackIndex].cues.remove(at: index)
            }
        }
        if let selectedCueIndex = selectedCueIndex {
            let lowestDeletedIndex = sortedIndices.last ?? 0
            if sortedIndices.contains(selectedCueIndex) {
                self.selectedCueIndex = max(0, lowestDeletedIndex - 1)
            } else if lowestDeletedIndex < selectedCueIndex {
                let deletedCount = sortedIndices.filter { $0 < selectedCueIndex }.count
                self.selectedCueIndex = selectedCueIndex - deletedCount
            }
        }
        clearCueSelection()
        updateWebClients()
    }
    
    private func advanceCue() {
        guard let selectedIndex = selectedCueIndex else { return }
        if selectedIndex < cueStacks[selectedCueStackIndex].cues.count - 1 {
            selectCue(at: selectedIndex + 1)
            self.appDelegate.updateWebClients()
        }
    }
    
    private func previousCue() {
        guard let selectedIndex = selectedCueIndex else { return }
        if selectedIndex > 0 {
            selectCue(at: selectedIndex - 1)
            self.appDelegate.updateWebClients()
        }
    }
    
    private func selectCue(at index: Int) {
        selectedCueIndex = index
        highlightCue(at: index)
        self.appDelegate.updateWebClients()
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
        let cue = cueStacks[selectedCueStackIndex].cues[index]
        if let timerValue = parseCountdownTime(cue.timerValue) {
            selectedCueTime = timerValue
            // Post a notification to reset the countdown in TopSectionView
            NotificationCenter.default.post(name: Notification.Name("ResetCountdown"), object: timerValue)
        }
    }
    
    func addCue() {
        saveState()
        let newCue = Cue(values: Array(repeating: "", count: cueStacks[selectedCueStackIndex].columns.count))
        cueStacks[selectedCueStackIndex].cues.append(newCue)
        self.appDelegate.updateWebClients()
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
                cueStacks: self.cueStacks,
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
            cueStacks: cueStacks,
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
                    self.cueStacks = savedData.cueStacks
                    self.settingsManager.settings.highlightColors = savedData.highlightColors
                    self.pdfNotes = savedData.pdfNotes
                    self.lastSavedURL = url
                    self.currentFileName = url.lastPathComponent
                    print("File opened successfully: \(url.path)")
                    self.updateWebClients()
                } catch {
                    print("Error reading file: \(error.localizedDescription)")
                    self.showOpenError(error: error)
                }
            }
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
                    let selectedStack = cueStacks[selectedCueStackIndex]
                    let maxImportedColumns = importedCues.map { $0.values.count }.max() ?? 0
                    let currentColumnCount = selectedStack.columns.count
                    let newMaxColumns = max(maxImportedColumns, currentColumnCount)
                    while cueStacks[selectedCueStackIndex].columns.count < newMaxColumns {
                        let newColumnIndex = cueStacks[selectedCueStackIndex].columns.count
                        cueStacks[selectedCueStackIndex].columns.append(Column(name: "Column \(newColumnIndex + 1)", width: 100))
                    }
                    let preparedImportedCues = importedCues.map { cue -> Cue in
                        var values = cue.values
                        while values.count < newMaxColumns {
                            values.append("")
                        }
                        return Cue(values: values)
                    }
                    cueStacks[selectedCueStackIndex].cues.insert(contentsOf: preparedImportedCues, at: 0)
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
        guard cueStacks.indices.contains(selectedCueStackIndex) else { return }
        let currentStack = cueStacks[selectedCueStackIndex]
        let currentState = (columns: currentStack.columns, cues: currentStack.cues)
        if currentStateIndex < stateHistory.count - 1 {
            stateHistory = Array(stateHistory.prefix(upTo: currentStateIndex + 1))
        }
        stateHistory.append(currentState)
        currentStateIndex += 1
    }
    
    func undo() {
        guard currentStateIndex > 0 else { return }
        currentStateIndex -= 1
        let previousState = stateHistory[currentStateIndex]
        cueStacks[selectedCueStackIndex].columns = previousState.columns
        cueStacks[selectedCueStackIndex].cues = previousState.cues
        self.appDelegate.updateWebClients()
    }
    
    func redo() {
        guard currentStateIndex < stateHistory.count - 1 else { return }
        currentStateIndex += 1
        let nextState = stateHistory[currentStateIndex]
        cueStacks[selectedCueStackIndex].columns = nextState.columns
        cueStacks[selectedCueStackIndex].cues = nextState.cues
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
        guard !indices.isEmpty, cueStacks.indices.contains(selectedCueStackIndex) else { return }
        let cuesToCopy = indices.compactMap { index -> Cue? in
            guard index >= 0 && index < cueStacks[selectedCueStackIndex].cues.count else {
                return nil
            }
            return cueStacks[selectedCueStackIndex].cues[index]
        }
        if !cuesToCopy.isEmpty {
            let transferCues = MultiCueTransfer(
                cues: cuesToCopy,
                columnCount: cueStacks[selectedCueStackIndex].columns.count
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
        if let selectedIndex = selectedCueIndex {
            pasteCues(after: selectedIndex)
        }
    }
    
    func pasteCues(after index: Int) {
        guard cueStacks.indices.contains(selectedCueStackIndex) else {
            print("Selected cue stack index is out of range")
            return
        }
        guard index >= 0 && index < cueStacks[selectedCueStackIndex].cues.count else {
            print("Selected cue index is out of range")
            return
        }
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .string) {
            let decoder = JSONDecoder()
            if let transferCues = try? decoder.decode(MultiCueTransfer.self, from: data) {
                saveState()
                let targetColumnCount = cueStacks[selectedCueStackIndex].columns.count
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
                cueStacks[selectedCueStackIndex].cues.insert(contentsOf: adjustedCues, at: index + 1)
                selectedCueIndex = index + adjustedCues.count
                self.appDelegate.updateWebClients()
            } else if let transferCue = try? decoder.decode(TransferCue.self, from: data) {
                saveState()
                let targetColumnCount = cueStacks[selectedCueStackIndex].columns.count
                var newCue = transferCue.cue
                if newCue.values.count < targetColumnCount {
                    while newCue.values.count < targetColumnCount {
                        newCue.values.append("")
                    }
                } else if newCue.values.count > targetColumnCount {
                    newCue.values = Array(newCue.values.prefix(targetColumnCount))
                }
                cueStacks[selectedCueStackIndex].cues.insert(newCue, at: index + 1)
                selectedCueIndex = index + 1
                self.appDelegate.updateWebClients()
            } else if let decodedCue = try? decoder.decode(Cue.self, from: data) {
                saveState()
                var newCue = decodedCue
                let targetColumnCount = cueStacks[selectedCueStackIndex].columns.count
                if newCue.values.count < targetColumnCount {
                    while newCue.values.count < targetColumnCount {
                        newCue.values.append("")
                    }
                } else if newCue.values.count > targetColumnCount {
                    newCue.values = Array(newCue.values.prefix(targetColumnCount))
                }
                cueStacks[selectedCueStackIndex].cues.insert(newCue, at: index + 1)
                selectedCueIndex = index + 1
                self.appDelegate.updateWebClients()
            }
        }
    }
    
    func pasteCue(at index: Int) {
        pasteCues(after: index)
    }
    
    // MARK: - Printing Functionality
    
    /// Call this function (for example, from your File > Print menu) to show the print options.
    func printCueStacks() {
        // Preselect all cue stacks by default.
        printSelectedCueStackIndices = Set(cueStacks.indices)
        showPrintSheet = true
    }
    
    /// Called by the print settings sheet to perform printing.
    func performPrintAction() {
        // Gather the selected cue stacks.
        let stacksToPrint = printSelectedCueStackIndices.sorted().map { cueStacks[$0] }
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
