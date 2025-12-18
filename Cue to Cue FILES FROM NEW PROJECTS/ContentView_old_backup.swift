//
//  ContentView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 5/26/24.
//




import SwiftUI
import Combine
import UniformTypeIdentifiers

struct Cue: Identifiable, Equatable, Codable {
    var id = UUID()
    var values: [String]
    var timerValue: String // Add a timerValue property
    
    enum CodingKeys: String, CodingKey {
        case id
        case values
        case timerValue // Add timerValue to coding keys
    }
    
    init(id: UUID = UUID(), values: [String], timerValue: String = "") {
        self.id = id
        self.values = values
        self.timerValue = timerValue // Initialize timerValue
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        values = try container.decode([String].self, forKey: .values)
        timerValue = try container.decode(String.self, forKey: .timerValue) // Decode timerValue
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(values, forKey: .values)
        try container.encode(timerValue, forKey: .timerValue) // Encode timerValue
    }
}

struct Column: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var width: CGFloat
}

struct HighlightColor: Identifiable, Equatable, Codable {
    var id = UUID()
    var keyword: String
    var color: Color
    
    enum CodingKeys: String, CodingKey {
        case id
        case keyword
        case colorData
    }
    
    init(id: UUID = UUID(), keyword: String, color: Color) {
        self.id = id
        self.keyword = keyword
        self.color = color
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyword = try container.decode(String.self, forKey: .keyword)
        let colorData = try container.decode(Data.self, forKey: .colorData)
        self.color = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData).map(Color.init) ?? .white
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(keyword, forKey: .keyword)
        let colorData = try NSKeyedArchiver.archivedData(withRootObject: NSColor(color), requiringSecureCoding: false)
        try container.encode(colorData, forKey: .colorData)
    }
}

struct ContentView: View {
    @State private var currentTime = Date()
    @State private var countdownTime = 300
    @State private var countUpTime = 0
    @State private var countdownRunning = false
    @State private var countUpRunning = false
    @State private var stopAtZero = true
    @State private var cues = [Cue(values: ["Example Cue"])]
    @State private var columns = [Column(name: "Column 1", width: 100)]
    @State private var highlightColors = [
        HighlightColor(keyword: "video", color: .blue),
        HighlightColor(keyword: "demo", color: .red)
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
    @State private var selectedCueIndex: Int? {
        didSet {
            if let index = selectedCueIndex {
                highlightCue(at: index)
            }
        }
    }
    @State private var showDeleteConfirmation = false
    @State private var cueToDelete: Int?
    @State private var editingCueIndex: Int?
    @State var showSavePanel = false
    @State var showOpenPanel = false
    @State var showImportCSVPanel = false
    @EnvironmentObject var appDelegate: AppDelegate
    @State private var scrollViewProxy: ScrollViewProxy?

    // Undo/Redo State
    @State private var stateHistory: [(columns: [Column], cues: [Cue])] = []
    @State private var currentStateIndex = -1

    private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
                        SettingsView(font: $font, fontSize: $fontSize, fontColor: $fontColor, backgroundColor: $backgroundColor, countdownColor: $countdownColor, tableBackgroundColor: $tableBackgroundColor, highlightColors: $highlightColors, isPresented: $showSettings, clockFontSize: $clockFontSize, stopAtZero: $stopAtZero)
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .top)

                VStack {
                    // Column Titles and Add Column Button
                    HStack(spacing: 0) { // Adjusted to add space between columns
                        Spacer().frame(width: 10) // Add this line
                        ForEach(columns.indices, id: \.self) { index in
                            ResizableColumnHeader(column: self.$columns[index], allColumns: self.$columns, font: $font, fontSize: $fontSize, fontColor: $fontColor)
                        }
                        Spacer()
                        Button(action: addColumn) {
                            Text("Add Column")
                        }
                    }
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading) // Left-align HStack
                    .background(Color.gray.opacity(0.1)) // Light grey background

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
                                        TextField("", text: $cues[rowIndex].values[columnIndex], onEditingChanged: { editing in
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
                                    TextField("00:00:00", text: $cues[rowIndex].timerValue, onEditingChanged: { editing in
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
                                .frame(height: fontSize * 2) // Adjust row height based on font size
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
                                .onDrop(of: [.text], delegate: CueDropDelegate(item: self.$draggedItem, listData: self.$cues, currentItem: self.cues[rowIndex]))
                                .id(rowIndex)
                            }
                            .onDelete(perform: deleteCue)
                            .onMove(perform: moveCue)
                        }
                        .onAppear {
                            scrollViewProxy = proxy
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
                        .buttonStyle(PlainButtonStyle()) // Ensures no default button styling
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
                    .padding()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .onChange(of: showSavePanel) { _ in
                if showSavePanel {
                    saveFile()
                }
            }
            .onChange(of: showOpenPanel) { _ in
                if showOpenPanel {
                    openFile()
                }
            }
            .onChange(of: showImportCSVPanel) { _ in
                if showImportCSVPanel {
                    importCSV()
                }
            }
            .onReceive(timer) { _ in
                if countdownRunning {
                    if countdownTime > 0 {
                        countdownTime -= 1
                    } else if !stopAtZero {
                        countdownTime -= 1
                    }
                }
                if countUpRunning {
                    countUpTime += 1
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
        }
        .onAppear {
            appDelegate.contentView = self
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                self.handleKeyDown(with: event)
                return event
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            showSettings = false
        }
    }

    private func handleKeyDown(with event: NSEvent) {
        guard editingCueIndex == nil else { return }

        switch event.keyCode {
        case 36: // Return key
            advanceCue()
        case 126: // Up arrow
            previousCue()
        case 125: // Down arrow
            advanceCue()
        case 6: // 'Z' key for undo
            if event.modifierFlags.contains(.command) {
                undo()
            }
        case 7: // 'Y' key for redo
            if event.modifierFlags.contains(.command) {
                redo()
            }
        default:
            break
        }
    }

    private func advanceCue() {
        guard let selectedIndex = selectedCueIndex else { return }
        if selectedIndex < cues.count - 1 {
            selectedCueIndex = selectedIndex + 1
            withAnimation {
                scrollViewProxy?.scrollTo(selectedCueIndex, anchor: .center)
            }
        }
    }

    private func previousCue() {
        guard let selectedIndex = selectedCueIndex else { return }
        if selectedIndex > 0 {
            selectedCueIndex = selectedIndex - 1
            withAnimation {
                scrollViewProxy?.scrollTo(selectedCueIndex, anchor: .center)
            }
        }
    }

    private func highlightCue(at index: Int) {
        let cue = cues[index]
        if let timerValue = parseCountdownTime(cue.timerValue) {
            countdownTime = timerValue
            countdownRunning = true
        }
    }

    private func saveFile() {
        do {
            let data = try JSONEncoder().encode(SavedData(columns: columns, cues: cues, highlightColors: highlightColors))
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "CueData.json"
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.allowsOtherFileTypes = false

            panel.begin { response in
                if response == .OK, let url = panel.url {
                    do {
                        try data.write(to: url)
                        print("File saved to \(url)")
                    } catch {
                        print("Failed to save file: \(error.localizedDescription)")
                    }
                }
                self.showSavePanel = false
            }
        } catch {
            print("Failed to encode data: \(error.localizedDescription)")
            self.showSavePanel = false
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let savedData = try JSONDecoder().decode(SavedData.self, from: data)
                    self.columns = savedData.columns
                    self.cues = savedData.cues
                    self.highlightColors = savedData.highlightColors
                    print("File loaded from \(url)")
                    saveState() // Save the state after loading
                } catch {
                    print("Failed to load file: \(error.localizedDescription)")
                }
            }
            self.showOpenPanel = false
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let (parsedColumns, parsedCues) = parseCSV(data: data)
                    self.columns = parsedColumns
                    self.cues = parsedCues
                    print("CSV imported from \(url)")
                    saveState() // Save the state after importing CSV
                } catch {
                    print("Failed to import CSV: \(error.localizedDescription)")
                }
            }
            self.showImportCSVPanel = false
        }
    }

    private func addCue() {
        saveState() // Save the state before adding a new cue
        let newCue = Cue(values: Array(repeating: "", count: columns.count))
        cues.append(newCue)
    }

    private func deleteCue(at offsets: IndexSet) {
        saveState() // Save the state before deleting a cue
        cues.remove(atOffsets: offsets)
    }

    private func moveCue(from source: IndexSet, to destination: Int) {
        saveState() // Save the state before moving a cue
        cues.move(fromOffsets: source, toOffset: destination)
    }

    private func addColumn() {
        saveState() // Save the state before adding a new column
        columns.append(Column(name: "Column \(columns.count + 1)", width: 100))
        for index in cues.indices {
            cues[index].values.append("")
        }
    }

    private func getHighlightColor(for cue: Cue) -> Color {
        for highlight in highlightColors {
            if cue.values.contains(where: { $0.lowercased().contains(highlight.keyword.lowercased()) }) {
                return highlight.color
            }
        }
        return fontColor
    }

    private func timeString(time: Int) -> String {
        let hours = time / 3600
        let minutes = (time % 3600) / 60
        let seconds = time % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func parseCountdownTime(_ timeString: String) -> Int? {
        let components = timeString.split(separator: ":").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        return components[0] * 3600 + components[1] * 60 + components[2]
    }

    private func saveState() {
        // Save the current state to the state history
        let currentState = (columns: columns, cues: cues)
        if currentStateIndex < stateHistory.count - 1 {
            // If we are not at the end of the history, remove all states after the current index
            stateHistory = Array(stateHistory.prefix(upTo: currentStateIndex + 1))
        }
        stateHistory.append(currentState)
        currentStateIndex += 1
    }

    func undo() {
        guard currentStateIndex > 0 else { return }
        currentStateIndex -= 1
        let previousState = stateHistory[currentStateIndex]
        columns = previousState.columns
        cues = previousState.cues
    }

    func redo() {
        guard currentStateIndex < stateHistory.count - 1 else { return }
        currentStateIndex += 1
        let nextState = stateHistory[currentStateIndex]
        columns = nextState.columns
        cues = nextState.cues
    }
}

struct ResizableColumnHeader: View {
    @Binding var column: Column
    @Binding var allColumns: [Column]
    @Binding var font: Font
    @Binding var fontSize: CGFloat
    @Binding var fontColor: Color
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        HStack(spacing: -5) {
            TextField("Column Title", text: $column.name)
                .font(font)
                .bold()
                .foregroundColor(fontColor)
                .frame(width: self.column.width, alignment: .leading)
                .background(self.isDragging ? Color.gray.opacity(0.5) : Color.clear)
                .onDrag {
                    self.isDragging = true
                    return NSItemProvider(object: String(self.column.id.uuidString) as NSString)
                }
                .onDrop(of: [.text], delegate: ColumnDropDelegate(column: self.$column, allColumns: self.$allColumns))
            
            Rectangle()
                .foregroundColor(Color.gray)
                .frame(width: 5, height: 40)
                .gesture(DragGesture()
                            .onChanged { value in
                                self.column.width = max(50, self.column.width + value.translation.width)
                            }
                            .onEnded { _ in
                                self.isDragging = false
                            })
        }
    }
}

struct ColumnDropDelegate: DropDelegate {
    @Binding var column: Column
    @Binding var allColumns: [Column]

    func dropEntered(info: DropInfo) {
        guard let fromIndex = allColumns.firstIndex(of: column) else { return }

        if let provider = info.itemProviders(for: [.text]).first {
            provider.loadObject(ofClass: NSString.self) { (string, error) in
                guard let uuidString = string as? String,
                      let toColumn = allColumns.first(where: { $0.id.uuidString == uuidString }),
                      let toIndex = allColumns.firstIndex(of: toColumn) else { return }

                DispatchQueue.main.async {
                    withAnimation {
                        allColumns.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                    }
                }
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        return true
    }
}

struct CueDropDelegate: DropDelegate {
    @Binding var item: Cue?
    @Binding var listData: [Cue]
    var currentItem: Cue

    func dropEntered(info: DropInfo) {
        guard let item = item, item != currentItem,
              let fromIndex = listData.firstIndex(of: item),
              let toIndex = listData.firstIndex(of: currentItem) else { return }

        withAnimation {
            listData.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        item = nil
        return true
    }
}

private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .medium
    return formatter
}()

struct SavedData: FileDocument, Codable {
    static var readableContentTypes: [UTType] { [.json] }

    var columns: [Column]
    var cues: [Cue]
    var highlightColors: [HighlightColor]

    init(columns: [Column], cues: [Cue], highlightColors: [HighlightColor]) {
        self.columns = columns
        self.cues = cues
        self.highlightColors = highlightColors
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decodedData = try JSONDecoder().decode(SavedData.self, from: data)
        self.columns = decodedData.columns
        self.cues = decodedData.cues
        self.highlightColors = decodedData.highlightColors
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(self)
        return FileWrapper(regularFileWithContents: data)
    }
}

func parseCSV(data: Data) -> (columns: [Column], cues: [Cue]) {
    let content = String(data: data, encoding: .utf8) ?? ""
    let lines = content.split(separator: "\n").map { String($0) }
    
    guard !lines.isEmpty else {
        return ([], [])
    }

    // Parse columns from the first line
    let headers = lines[0].split(separator: ",").map { String($0) }
    let columns = headers.map { Column(name: $0, width: 100) }

    // Parse cues from the remaining lines
    let cues = lines.dropFirst().map { line -> Cue in
        let values = line.split(separator: ",").map { String($0) }
        return Cue(values: values)
    }

    return (columns, cues)
}
