//
//  PrintManager.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 3/12/25.
//

import SwiftUI
import AppKit

/// A view to let the user select which cue stacks to print and adjust the print font size.
struct PrintSettingsView: View {
    @Binding var selectedIndices: Set<Int>
    @Binding var fontSize: CGFloat
    @State private var printWithColors: Bool = true
    @State private var showFullHeaders: Bool = true
    @State private var showPageNumbers: Bool = true
    @State private var printLayout: PrintLayout = .columns
    @State private var orientation: PrintOrientation = .portrait
    @State private var selectedColumns: [Int: Set<Int>] = [:] // [stackIndex: Set of selected column indices]
    @State private var showTimeColumn: [Int: Bool] = [:] // [stackIndex: show time column]
    
    var cueStacks: [CueStack]
    var onPrint: () -> Void

    @Environment(\.presentationMode) var presentationMode
    
    enum PrintLayout: String, CaseIterable, Identifiable {
        case columns = "Columns"
        case compactList = "Compact List"
        
        var id: String { self.rawValue }
    }
    
    enum PrintOrientation: String, CaseIterable, Identifiable {
        case portrait = "Portrait"
        case landscape = "Landscape"
        
        var id: String { self.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Print Settings")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 5)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Cue Stacks to Print")
                    .font(.headline)
                
                List(cueStacks.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: Binding(
                            get: { selectedIndices.contains(index) },
                            set: { isSelected in
                                if isSelected {
                                    selectedIndices.insert(index)
                                    // Initialize selected columns for this stack if needed
                                    if selectedColumns[index] == nil {
                                        initializeColumns(for: index)
                                    }
                                } else {
                                    selectedIndices.remove(index)
                                }
                            }
                        )) {
                            Text(cueStacks[index].name)
                        }
                        
                        if selectedIndices.contains(index) && !cueStacks[index].columns.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Columns:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Button("Select All") {
                                        initializeColumns(for: index)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                    
                                    Button("Deselect All") {
                                        clearColumns(for: index)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }
                                
                                // Column selection toggles
                                ForEach(0..<cueStacks[index].columns.count, id: \.self) { colIndex in
                                    Toggle(isOn: Binding(
                                        get: { selectedColumns[index]?.contains(colIndex) ?? true },
                                        set: { isSelected in
                                            var cols = selectedColumns[index] ?? Set<Int>()
                                            if isSelected {
                                                cols.insert(colIndex)
                                            } else {
                                                cols.remove(colIndex)
                                            }
                                            selectedColumns[index] = cols
                                        }
                                    )) {
                                        Text(cueStacks[index].columns[colIndex].name)
                                            .font(.caption)
                                    }
                                    .padding(.leading, 8)
                                }
                                
                                // Time column toggle
                                Toggle(isOn: Binding(
                                    get: { showTimeColumn[index] ?? true },
                                    set: { isSelected in
                                        showTimeColumn[index] = isSelected
                                    }
                                )) {
                                    Text("Time Column")
                                        .font(.caption)
                                }
                                .padding(.leading, 8)
                                .padding(.top, 4)
                            }
                            .padding(.leading, 24)
                        }
                    }
                }
                .frame(height: 250)
                .listStyle(PlainListStyle())
                .border(Color.gray.opacity(0.3), width: 1)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Layout Options")
                    .font(.headline)
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Content Layout:")
                        Picker("", selection: $printLayout) {
                            ForEach(PrintLayout.allCases) { layout in
                                Text(layout.rawValue).tag(layout)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .labelsHidden()
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Orientation:")
                        Picker("", selection: $orientation) {
                            ForEach(PrintOrientation.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .labelsHidden()
                    }
                }
                .padding(.bottom, 4)
                
                HStack {
                    Text("Print Font Size:")
                    Slider(value: $fontSize, in: 8...18, step: 1)
                    Text("\(Int(fontSize))")
                        .frame(width: 25, alignment: .trailing)
                }
                
                Toggle("Print with Colors", isOn: $printWithColors)
                Toggle("Show Column Headers", isOn: $showFullHeaders)
                Toggle("Show Page Numbers", isOn: $showPageNumbers)
            }
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Print") {
                    // Save column selection to UserDefaults
                    // Convert Int keys to String keys for JSON encoding
                    var encodableColumns: [String: Set<Int>] = [:]
                    for (key, value) in selectedColumns {
                        encodableColumns[String(key)] = value
                    }
                    
                    var encodableTimeColumns: [String: Bool] = [:]
                    for (key, value) in showTimeColumn {
                        encodableTimeColumns[String(key)] = value
                    }
                    
                    if let selectedColumnsData = try? JSONEncoder().encode(encodableColumns) {
                        UserDefaults.standard.set(selectedColumnsData, forKey: "PrintSelectedColumns")
                    }
                    
                    if let timeColumnData = try? JSONEncoder().encode(encodableTimeColumns) {
                        UserDefaults.standard.set(timeColumnData, forKey: "PrintShowTimeColumn")
                    }
                    
                    // Save other preferences
                    UserDefaults.standard.set(printLayout == .columns, forKey: "PrintColumnsLayout")
                    UserDefaults.standard.set(printWithColors, forKey: "PrintWithColors")
                    UserDefaults.standard.set(showFullHeaders, forKey: "PrintShowHeaders")
                    UserDefaults.standard.set(showPageNumbers, forKey: "PrintShowPageNumbers")
                    UserDefaults.standard.set(orientation == .landscape, forKey: "PrintLandscapeOrientation")
                    
                    onPrint()
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 600)
        .onAppear {
            loadPreferences()
        }
    }
    
    func loadPreferences() {
        // Load user preferences
        printWithColors = UserDefaults.standard.bool(forKey: "PrintWithColors")
        showFullHeaders = UserDefaults.standard.bool(forKey: "PrintShowHeaders")
        showPageNumbers = UserDefaults.standard.bool(forKey: "PrintShowPageNumbers")
        printLayout = UserDefaults.standard.bool(forKey: "PrintColumnsLayout") ? .columns : .compactList
        orientation = UserDefaults.standard.bool(forKey: "PrintLandscapeOrientation") ? .landscape : .portrait
        
        // Load time column preferences
        if let timeColumnData = UserDefaults.standard.data(forKey: "PrintShowTimeColumn"),
           let decodedTimeColumns = try? JSONDecoder().decode([String: Bool].self, from: timeColumnData) {
            for (key, value) in decodedTimeColumns {
                if let intKey = Int(key) {
                    showTimeColumn[intKey] = value
                }
            }
        }
        
        // Initialize selected columns for all selected stacks
        for index in selectedIndices {
            if selectedColumns[index] == nil {
                initializeColumns(for: index)
            }
        }
    }
    
    func initializeColumns(for stackIndex: Int) {
        guard stackIndex < cueStacks.count else { return }
        let allColumnIndices = Set(0..<cueStacks[stackIndex].columns.count)
        selectedColumns[stackIndex] = allColumnIndices
        showTimeColumn[stackIndex] = true
    }
    
    func clearColumns(for stackIndex: Int) {
        selectedColumns[stackIndex] = Set<Int>()
        showTimeColumn[stackIndex] = false
    }
}

/// Performs the print operation with proper pagination
func performPrint(cueStacks: [CueStack], fontSize: CGFloat) {
    // Load user preferences
    let useColumnLayout = UserDefaults.standard.bool(forKey: "PrintColumnsLayout")
    let useColors = UserDefaults.standard.bool(forKey: "PrintWithColors")
    let showHeaders = UserDefaults.standard.bool(forKey: "PrintShowHeaders")
    let showPageNumbers = UserDefaults.standard.bool(forKey: "PrintShowPageNumbers")
    let useLandscape = UserDefaults.standard.bool(forKey: "PrintLandscapeOrientation")
    
    // Load selected columns from UserDefaults
    var selectedColumns: [Int: Set<Int>] = [:]
    if let selectedColumnsData = UserDefaults.standard.data(forKey: "PrintSelectedColumns"),
       let decodedColumns = try? JSONDecoder().decode([String: Set<Int>].self, from: selectedColumnsData) {
        // Convert String keys back to Int keys
        for (key, value) in decodedColumns {
            if let intKey = Int(key) {
                selectedColumns[intKey] = value
            }
        }
    }
    
    // Load time column preferences
    var showTimeColumn: [Int: Bool] = [:]
    if let timeColumnData = UserDefaults.standard.data(forKey: "PrintShowTimeColumn"),
       let decodedTimeColumns = try? JSONDecoder().decode([String: Bool].self, from: timeColumnData) {
        for (key, value) in decodedTimeColumns {
            if let intKey = Int(key) {
                showTimeColumn[intKey] = value
            }
        }
    }
    
    // Create modified cue stacks with only selected columns
    var modifiedCueStacks = cueStacks
    for stackIndex in 0..<modifiedCueStacks.count {
        if let selectedCols = selectedColumns[stackIndex], !selectedCols.isEmpty {
            // Only modify if we have specific columns selected
            let originalStack = modifiedCueStacks[stackIndex]
            
            // Create filtered columns
            let filteredColumns = selectedCols.sorted().compactMap { colIndex -> Column? in
                guard colIndex < originalStack.columns.count else { return nil }
                return originalStack.columns[colIndex]
            }
            
            // Create filtered cues
            let filteredCues = originalStack.cues.map { cue -> Cue in
                var newValues = [String]()
                for colIndex in selectedCols.sorted() {
                    if colIndex < cue.values.count {
                        newValues.append(cue.values[colIndex])
                    } else {
                        newValues.append("")
                    }
                }
                var newCue = cue
                newCue.values = newValues
                return newCue
            }
            
            // Replace the stack with a filtered version
            modifiedCueStacks[stackIndex] = CueStack(
                name: originalStack.name,
                cues: filteredCues,
                columns: filteredColumns
            )
        }
    }
    
    // Create a paginated printable view
    let printView = CueStackPaginatedView(
        cueStacks: modifiedCueStacks,
        fontSize: fontSize,
        useColors: useColors,
        showHeaders: showHeaders,
        showPageNumbers: showPageNumbers,
        useColumnLayout: useColumnLayout,
        showTimeColumns: showTimeColumn,
        useLandscape: useLandscape
    )
    
    // Configure print info
    let printInfo = NSPrintInfo.shared
    printInfo.topMargin = 36
    printInfo.bottomMargin = 56  // Increased bottom margin to give space for page numbers
    printInfo.leftMargin = 36
    printInfo.rightMargin = 36
    
    // Set orientation based on user preference
    if useLandscape {
        // Swap paper size width and height for landscape
        _ = printInfo.paperSize
        printInfo.orientation = .landscape
    } else {
        printInfo.orientation = .portrait
    }
    
    // These settings are crucial for proper pagination
    printInfo.horizontalPagination = .fit
    printInfo.verticalPagination = .automatic
    printInfo.isVerticallyCentered = false // Don't center content vertically
    printInfo.isHorizontallyCentered = true // Do center content horizontally
    
    // Create print operation
    let printOperation = NSPrintOperation(view: printView, printInfo: printInfo)
    printOperation.showsPrintPanel = true
    printOperation.showsProgressPanel = true
    
    // Run the print operation
    printOperation.run()
}
