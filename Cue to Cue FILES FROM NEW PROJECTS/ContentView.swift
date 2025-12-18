//
//  ContentView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 5/26/24.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var currentTime = Date()
    @State private var countdownTime = 300
    @State private var countUpTime = 0
    @State private var countdownRunning = false
    @State private var countUpRunning = false
    @State private var stopAtZero = true
    @State private var cueStacks = [CueStack(name: "Cue Stack 1", cues: [Cue(values: ["Example Cue"])], columns: [Column(name: "Column 1", width: 100)])]
    @State private var selectedCueStackIndex: Int = 0
    @State private var highlightColors = [
        HighlightColorSetting(keyword: "video", color: .blue),
        HighlightColorSetting(keyword: "demo", color: .red)
    ]
    @State private var draggedItem: Cue?
    @State private var draggedColumn: Column?
    @State private var isEditingCountdown = false
    @State private var editedCountdownTime: String = ""
    @State private var showSettings = false
    @State private var font: Font = .system(size: 14)
    @State private var fontSize: CGFloat = 14
    @State private var fontColor: Color = .white
    @State private var backgroundColor: Color = Color(.darkGray)
    @State private var countdownColor: Color = .red
    @State private var tableBackgroundColor: Color = Color(.darkGray)
    @State private var clockFontSize: CGFloat = 40
    @StateObject private var settingsManager = SettingsManager()
    @State private var selectedCueIndex: Int? {
        didSet {
            if let index = selectedCueIndex {
                highlightCue(at: index)
            }
        }
    }
    @State private var showDeleteConfirmation = false
    @State private var cueToDelete: Int?
    @State private var columnToDelete: Int?
    @State private var editingCueIndex: Int?
    @State var showSavePanel = false
    @State var showOpenPanel = false
    @State var showImportCSVPanel = false
    @EnvironmentObject var appDelegate: AppDelegate

    // Undo/Redo State
    @State private var stateHistory: [(columns: [Column], cues: [Cue])] = []
    @State private var currentStateIndex = -1

    // Timer for handling double click
    @State private var lastClickTime: Date?
    @State private var editCueStackIndex: Int?
    @State private var isEditingCueStackName = false
    @State private var editedCueStackName = ""

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Computed properties for current cue stack
    private var currentCueStack: CueStack {
        cueStacks[selectedCueStackIndex]
    }
    
    private var cues: [Cue] {
        currentCueStack.cues
    }
    
    private var columns: [Column] {
        currentCueStack.columns
    }

    var body: some View {
        ZStack {
            backgroundColor.edgesIgnoringSafeArea(.all)
            
            VStack {
        HStack {
            VStack {
                Text("Current Time")
                Text("\(currentTime, formatter: timeFormatter)")
                    .font(.system(size: clockFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                    .onReceive(timer) { input in
                        self.currentTime = input
                    }
            }
            Spacer()

            VStack {
                Text("Countdown")
                if isEditingCountdown {
                    TextField("Edit Countdown", text: $editedCountdownTime, onCommit: {
                        if let time = parseCountdownTime(editedCountdownTime) {
                            countdownTime = time
                            isEditingCountdown = false
                        }
                    })
                    .font(.system(size: clockFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(countdownColor)
                    .multilineTextAlignment(.center)
                } else {
                    Text("\(timeString(time: countdownTime))")
                        .font(.system(size: clockFontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(countdownColor)
                        .onTapGesture {
                            editedCountdownTime = timeString(time: countdownTime)
                            isEditingCountdown = true
                        }
                }
                HStack {
                    Button(action: { self.countdownRunning = true }) {
                        Text("Start Countdown")
                    }
                    Button(action: { self.countdownRunning = false }) {
                        Text("Pause Countdown")
                    }
                    Button(action: {
                        self.countdownRunning = false
                        self.countdownTime = 300
                    }) {
                        Text("Reset Countdown")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer()

            VStack {
                Text("Count Up")
                Text("\(timeString(time: countUpTime))")
                    .font(.system(size: clockFontSize, weight: .bold, design: .monospaced))
                    .foregroundColor(countdownColor)
                HStack {
                    Button(action: { self.countUpRunning = true }) {
                        Text("Start Count Up")
                    }
                    Button(action: { self.countUpRunning = false }) {
                        Text("Pause Count Up")
                    }
                    Button(action: {
                        self.countUpRunning = false
                        self.countUpTime = 0
                    }) {
                        Text("Reset Count Up")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer()

            Button(action: {
                showSettings.toggle()
            }) {
                Image(systemName: "gear")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.white)
            }
            .sheet(isPresented: $showSettings) {
                        SettingsView(settingsManager: settingsManager)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .top)

        VStack {
            // Column Titles and Add Column Button
            HStack(spacing: 0) {
                Spacer().frame(width: 10)
                ForEach(columns.indices, id: \.self) { index in
                    ResizableColumnHeader(
                                column: self.$cueStacks[selectedCueStackIndex].columns[index],
                                allColumns: self.$cueStacks[selectedCueStackIndex].columns,
                        font: $font, 
                        fontSize: $fontSize, 
                        fontColor: $fontColor,
                                cues: self.$cueStacks[selectedCueStackIndex].cues,
                        isReorderingCues: .constant(false),
                        addColumn: addColumn,
                                deleteColumn: { index in
                                    columnToDelete = index
                                }
                    )
                }
                Spacer()
                Button(action: addColumn) {
                    Text("Add Column")
                }
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))

            // Cue Sheet
            ScrollViewReader { proxy in
                List {
                    ForEach(cues.indices, id: \.self) { rowIndex in
                        HStack(spacing: 0) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 10, height: 10)
                                .opacity(selectedCueIndex == rowIndex ? 1 : 0)
                            ForEach(cues[rowIndex].values.indices, id: \.self) { columnIndex in
                                        TextField("", text: $cueStacks[selectedCueStackIndex].cues[rowIndex].values[columnIndex], onEditingChanged: { editing in
                                    editingCueIndex = editing ? rowIndex : nil
                                    if !editing {
                                        saveState()
                                    }
                                })
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: columns[columnIndex].width, alignment: .leading)
                                    .font(selectedCueIndex == rowIndex ? .system(size: fontSize, weight: .bold) : .system(size: fontSize))
                                            .foregroundColor(getHighlightColor(for: cues[rowIndex]))
                            }
                            Spacer()
                                    TextField("00:00:00", text: $cueStacks[selectedCueStackIndex].cues[rowIndex].timerValue, onEditingChanged: { editing in
                                if !editing {
                                    saveState()
                                }
                            })
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 100, alignment: .leading)
                            .font(.system(size: fontSize))
                            .padding(.trailing, 5)
                            
                            Button(action: {
                                cueToDelete = rowIndex
                                showDeleteConfirmation = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .padding(.trailing, 10)
                        }
                        .background(selectedCueIndex == rowIndex ? Color.green.opacity(0.2) : (selectedCueIndex != nil && selectedCueIndex! + 1 == rowIndex ? Color.yellow.opacity(0.2) : tableBackgroundColor))
                        .frame(height: fontSize * 2)
                        .onTapGesture {
                            selectedCueIndex = rowIndex
                            withAnimation {
                                proxy.scrollTo(rowIndex, anchor: .center)
                            }
                        }
                        .onDrag {
                            self.draggedItem = self.cues[rowIndex]
                            return NSItemProvider(object: String(self.cues[rowIndex].id.uuidString) as NSString)
                        }
                                .onDrop(of: [.text], delegate: CueDropDelegate(item: self.$draggedItem, listData: self.$cueStacks[selectedCueStackIndex].cues, currentItem: self.cues[rowIndex]))
                        .id(rowIndex)
                    }
                    .onDelete(perform: deleteCue)
                    .onMove(perform: moveCue)
                }
                .onAppear {
                            // ScrollViewReader proxy available
                }
            }

            // Add Cue Button at Bottom Left
            HStack {
                Button(action: addCue) {
                    Text("Add Cue")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                Spacer()
                HStack {
                    Button(action: previousCue) {
                        Text("Previous Cue")
                    }
                    Button(action: advanceCue) {
                        Text("Next Cue")
                    }
                }
            }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .background(tableBackgroundColor)
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
            if countdownRunning {
                if countdownTime > 0 {
                    countdownTime -= 1
                } else if stopAtZero {
                    countdownRunning = false
                }
            }
            if countUpRunning {
                countUpTime += 1
            }
        }
        .onAppear {
            // Delay the assignment to ensure environment is fully loaded
            DispatchQueue.main.async {
                appDelegate.contentView = self
            }
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                self.handleKeyDown(with: event)
                return event
            }
            // Initial web server update
            updateWebServer()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            showSettings = false
        }
        .fileExporter(isPresented: $showSavePanel, document: SavedData(cueStacks: cueStacks, highlightColors: highlightColors), contentType: .json) { result in
            switch result {
            case .success(let url):
                print("File saved to: \(url)")
            case .failure(let error):
                print("Error saving file: \(error)")
            }
        }
        .fileImporter(isPresented: $showOpenPanel, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                openFile()
            case .failure(let error):
                print("Error opening file: \(error)")
            }
        }
        .fileImporter(isPresented: $showImportCSVPanel, allowedContentTypes: [.commaSeparatedText]) { result in
            switch result {
            case .success(let url):
                importCSV()
            case .failure(let error):
                print("Error importing CSV: \(error)")
            }
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Cue"),
                message: Text("Are you certain you want to delete this cue?"),
                primaryButton: .destructive(Text("Delete Cue")) {
                    if let index = cueToDelete {
                        deleteCue(at: IndexSet(integer: index))
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: .constant(columnToDelete != nil)) {
            Alert(
                title: Text("Delete Column"),
                message: Text("Are you certain you want to delete this column?"),
                primaryButton: .destructive(Text("Delete Column")) {
                    if let columnIndex = columnToDelete {
                        deleteColumn(at: columnIndex)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Helper Functions
    
    private func timeString(time: Int) -> String {
        let hours = time / 3600
        let minutes = (time % 3600) / 60
        let seconds = time % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    private func parseCountdownTime(_ timeString: String) -> Int? {
        let components = timeString.components(separatedBy: ":")
        guard components.count == 3,
              let hours = Int(components[0]),
              let minutes = Int(components[1]),
              let seconds = Int(components[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
    
    private func getHighlightColor(for cue: Cue) -> Color {
        for highlightColor in highlightColors {
            for value in cue.values {
                if value.lowercased().contains(highlightColor.keyword.lowercased()) {
                    return highlightColor.color
                }
            }
        }
        return fontColor
    }
    
    private func highlightCue(at index: Int) {
        // Implementation for highlighting cues
    }

    // MARK: - Cue Management Functions
    
    private func addCue() {
        let newCue = Cue(values: Array(repeating: "", count: columns.count))
        cueStacks[selectedCueStackIndex].cues.append(newCue)
        saveState()
    }
    
    private func deleteCue(at offsets: IndexSet) {
        cueStacks[selectedCueStackIndex].cues.remove(atOffsets: offsets)
        saveState()
    }
    
    private func moveCue(from source: IndexSet, to destination: Int) {
        cueStacks[selectedCueStackIndex].cues.move(fromOffsets: source, toOffset: destination)
        saveState()
    }
    
    private func previousCue() {
        guard selectedCueIndex != nil else { return }
        if selectedCueIndex! > 0 {
            selectedCueIndex! -= 1
        }
    }
    
    private func advanceCue() {
        guard selectedCueIndex != nil else { return }
        if selectedCueIndex! < cues.count - 1 {
            selectedCueIndex! += 1
        }
    }
    
    private func addColumn() {
        let newColumn = Column(name: "New Column", width: 100)
        cueStacks[selectedCueStackIndex].columns.append(newColumn)
        
        // Add empty values to all existing cues
        for index in cueStacks[selectedCueStackIndex].cues.indices {
            cueStacks[selectedCueStackIndex].cues[index].values.append("")
        }
        
        saveState()
    }
    
    private func deleteColumn(at index: Int) {
        guard index < columns.count else { return }
        cueStacks[selectedCueStackIndex].columns.remove(at: index)
        
        // Remove corresponding values from all cues
        for cueIndex in cueStacks[selectedCueStackIndex].cues.indices {
            if index < cueStacks[selectedCueStackIndex].cues[cueIndex].values.count {
                cueStacks[selectedCueStackIndex].cues[cueIndex].values.remove(at: index)
            }
        }
        
        columnToDelete = nil
        saveState()
    }

    // MARK: - State Management
    
    private func saveState() {
        // Save current state for undo/redo
        let currentState = (columns: columns, cues: cues)
        
        // Remove any states after current index
        if currentStateIndex < stateHistory.count - 1 {
            stateHistory.removeSubrange((currentStateIndex + 1)...)
        }
        
        // Add new state
        stateHistory.append(currentState)
        currentStateIndex = stateHistory.count - 1
        
        // Limit history size
        if stateHistory.count > 50 {
            stateHistory.removeFirst()
            currentStateIndex -= 1
        }
        
        // Update web server
        updateWebServer()
    }
    
    func undo() {
        guard currentStateIndex > 0 else { return }
        currentStateIndex -= 1
        let state = stateHistory[currentStateIndex]
        cueStacks[selectedCueStackIndex].columns = state.columns
        cueStacks[selectedCueStackIndex].cues = state.cues
        updateWebServer()
    }
    
    func redo() {
        guard currentStateIndex < stateHistory.count - 1 else { return }
        currentStateIndex += 1
        let state = stateHistory[currentStateIndex]
        cueStacks[selectedCueStackIndex].columns = state.columns
        cueStacks[selectedCueStackIndex].cues = state.cues
        updateWebServer()
    }

    // MARK: - File Operations
    
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            guard let url = panel.url else { return }
            
            do {
                let data = try Data(contentsOf: url)
                let savedData = try JSONDecoder().decode(SavedData.self, from: data)
                cueStacks = savedData.cueStacks
                highlightColors = savedData.highlightColors
                selectedCueStackIndex = 0
                saveState()
            } catch {
                print("Error loading file: \(error)")
            }
        }
    }
    
    func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK {
            guard let url = panel.url else { return }
            
            do {
                let csvString = try String(contentsOf: url)
                let lines = csvString.components(separatedBy: .newlines)
                
                var newCues: [Cue] = []
                for line in lines {
                    if !line.isEmpty {
                        let values = line.components(separatedBy: ",")
                        let cue = Cue(values: values)
                        newCues.append(cue)
                    }
                }
                
                cueStacks[selectedCueStackIndex].cues.append(contentsOf: newCues)
                saveState()
            } catch {
                print("Error importing CSV: \(error)")
            }
        }
    }

    // MARK: - Web Server Integration
    
    private func updateWebServer() {
        // Web server update implementation
        if webServer == nil {
            webServer = WebServer()
        }
        webServer?.updateCues(cueStacks: cueStacks, selectedCueStackIndex: selectedCueStackIndex, activeCueIndex: selectedCueIndex ?? -1, selectedCueIndex: selectedCueIndex ?? -1)
        webServer?.updateHighlightColors(highlightColors)
        webServer?.updateClockState(currentTime: currentTime, countdownTime: countdownTime, countUpTime: countUpTime, countdownRunning: countdownRunning, countUpRunning: countUpRunning)
    }
    
    @State private var webServer: WebServer?

    // MARK: - Keyboard Handling
    
    private func handleKeyDown(with event: NSEvent) {
        guard editingCueIndex == nil else { return }

        switch event.keyCode {
        case 36: // Enter key
            if let selectedIndex = selectedCueIndex {
                editingCueIndex = selectedIndex
            }
        case 48: // Tab key
            if let selectedIndex = selectedCueIndex {
                if event.modifierFlags.contains(.shift) {
                    // Shift+Tab: move to previous cue
                    if selectedIndex > 0 {
                        selectedCueIndex = selectedIndex - 1
                    }
                } else {
                    // Tab: move to next cue
                    if selectedIndex < cues.count - 1 {
                        selectedCueIndex = selectedIndex + 1
                    }
                }
            }
        case 51: // Delete key
            if let selectedIndex = selectedCueIndex {
                cueToDelete = selectedIndex
                showDeleteConfirmation = true
            }
        case 45: // N key (for new cue)
            addCue()
        default:
            break
        }
    }

    // MARK: - Copy/Paste Functions
    
    func copyCues() {
        // Copy all cues from current stack
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        do {
            let data = try JSONEncoder().encode(cueStacks[selectedCueStackIndex].cues)
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType("public.json"))
        } catch {
            print("Failed to copy cues: \(error)")
        }
    }
    
    func pasteCues() {
        // Paste cues to current stack
        let pasteboard = NSPasteboard.general
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.json")) else { return }
        
        do {
            let cues = try JSONDecoder().decode([Cue].self, from: data)
            cueStacks[selectedCueStackIndex].cues.append(contentsOf: cues)
            saveState()
        } catch {
            print("Failed to paste cues: \(error)")
        }
    }
    
    func updateWebClients() {
        updateWebServer()
    }
    
    func copyCue(at index: Int) {
        guard index < cues.count else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        do {
            let data = try JSONEncoder().encode(cues[index])
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType("public.json"))
        } catch {
            print("Failed to copy cue: \(error)")
        }
    }
    
    func pasteCue(at index: Int) {
        let pasteboard = NSPasteboard.general
        guard let data = pasteboard.data(forType: NSPasteboard.PasteboardType("public.json")) else { return }
        
        do {
            let cue = try JSONDecoder().decode(Cue.self, from: data)
            cueStacks[selectedCueStackIndex].cues.insert(cue, at: index)
            saveState()
        } catch {
            print("Failed to paste cue: \(error)")
        }
    }
}

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    return formatter
}()