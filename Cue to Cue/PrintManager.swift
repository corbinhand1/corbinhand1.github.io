//
//  PrintManager.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 3/12/25.
//

import SwiftUI
import AppKit

// MARK: - Configuration

enum PrintOrientation: String, CaseIterable, Identifiable {
    case portrait = "Portrait"
    case landscape = "Landscape"

    var id: String { rawValue }
}

struct PrintConfiguration: Equatable {
    var selectedStackIndices: Set<Int>
    var fontSize: CGFloat
    var printWithColors: Bool
    var showFullHeaders: Bool
    var showPageNumbers: Bool
    var showPrintDateTime: Bool
    var orientation: PrintOrientation
    var selectedColumns: [Int: Set<Int>]
    var showTimeColumn: [Int: Bool]
    var printHighlightColors: [HighlightColorSetting]
    var printedAt: Date?
}

enum PrintLayoutBuilder {
    static func filteredStacks(
        allStacks: [CueStack],
        configuration: PrintConfiguration
    ) -> [(originalIndex: Int, stack: CueStack)] {
        configuration.selectedStackIndices
            .sorted()
            .compactMap { index in
                guard allStacks.indices.contains(index) else { return nil }
                let original = allStacks[index]
                let stack = applyColumnFilter(
                    to: original,
                    originalIndex: index,
                    configuration: configuration
                )
                return (index, stack)
            }
    }

    static func paginatedView(
        allStacks: [CueStack],
        configuration: PrintConfiguration
    ) -> CueStackPaginatedView? {
        let stacks = filteredStacks(allStacks: allStacks, configuration: configuration)
            .map(\.stack)
        guard !stacks.isEmpty else { return nil }

        var showTimeColumns: [Int: Bool] = [:]
        let sortedSelection = configuration.selectedStackIndices.sorted()
        for previewIndex in stacks.indices {
            let sourceIndex = sortedSelection[previewIndex]
            showTimeColumns[previewIndex] = configuration.showTimeColumn[sourceIndex] ?? true
        }

        let activeHighlightColors = configuration.printWithColors ? configuration.printHighlightColors : []

        return CueStackPaginatedView(
            cueStacks: stacks,
            fontSize: configuration.fontSize,
            useColors: configuration.printWithColors,
            showHeaders: configuration.showFullHeaders,
            showPageNumbers: configuration.showPageNumbers,
            showPrintDateTime: configuration.showPrintDateTime,
            printDateTime: configuration.printedAt ?? Date(),
            useColumnLayout: true,
            showTimeColumns: showTimeColumns,
            useLandscape: configuration.orientation == .landscape,
            highlightColors: activeHighlightColors
        ).configuredForPagedOutput()
    }

    static func estimatedPageCount(
        for view: CueStackPaginatedView,
        landscape: Bool
    ) -> Int {
        _ = landscape
        return view.numberOfPages
    }

    private static func applyColumnFilter(
        to stack: CueStack,
        originalIndex: Int,
        configuration: PrintConfiguration
    ) -> CueStack {
        guard let selectedCols = configuration.selectedColumns[originalIndex],
              !selectedCols.isEmpty else {
            return stack
        }

        let filteredColumns = selectedCols.sorted().compactMap { colIndex -> Column? in
            guard colIndex < stack.columns.count else { return nil }
            return stack.columns[colIndex]
        }

        let filteredCues = stack.cues.map { cue -> Cue in
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

        return CueStack(name: stack.name, cues: filteredCues, columns: filteredColumns)
    }

    static func performPrint(
        configuration: PrintConfiguration,
        allCueStacks: [CueStack]
    ) {
        guard let printView = paginatedView(allStacks: allCueStacks, configuration: configuration) else { return }

        let printInfo = NSPrintInfo.shared
        // Margins are handled inside the paginated view — avoid double margins on print/PDF.
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.orientation = configuration.orientation == .landscape ? .landscape : .portrait
        printInfo.horizontalPagination = .clip
        printInfo.verticalPagination = .clip
        printInfo.isVerticallyCentered = false
        printInfo.isHorizontallyCentered = false

        printView.wantsLayer = false
        printView.layer?.masksToBounds = false

        let printOperation = NSPrintOperation(view: printView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true
        printOperation.run()
    }
}

enum PrintPreferences {
    static func load() -> (
        printWithColors: Bool,
        showFullHeaders: Bool,
        showPageNumbers: Bool,
        showPrintDateTime: Bool,
        orientation: PrintOrientation,
        showTimeColumn: [Int: Bool]
    ) {
        let printWithColors = UserDefaults.standard.object(forKey: "PrintWithColors") as? Bool ?? true
        let showFullHeaders = UserDefaults.standard.object(forKey: "PrintShowHeaders") as? Bool ?? true
        let showPageNumbers = UserDefaults.standard.object(forKey: "PrintShowPageNumbers") as? Bool ?? true
        let showPrintDateTime = UserDefaults.standard.object(forKey: "PrintShowDateTime") as? Bool ?? true
        let orientation: PrintOrientation = UserDefaults.standard.bool(forKey: "PrintLandscapeOrientation") ? .landscape : .portrait

        var showTimeColumn: [Int: Bool] = [:]
        if let timeColumnData = UserDefaults.standard.data(forKey: "PrintShowTimeColumn"),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: timeColumnData) {
            for (key, value) in decoded {
                if let intKey = Int(key) {
                    showTimeColumn[intKey] = value
                }
            }
        }

        return (printWithColors, showFullHeaders, showPageNumbers, showPrintDateTime, orientation, showTimeColumn)
    }

    static func loadPrintHighlightColors(matching screenColors: [HighlightColorSetting]) -> [HighlightColorSetting] {
        var overrides: [String: String] = [:]
        if let data = UserDefaults.standard.data(forKey: "PrintHighlightColors"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            overrides = decoded
        }

        return screenColors.map { screenColor in
            let key = screenColor.keyword.lowercased()
            if let hex = overrides[key] {
                return HighlightColorSetting(id: screenColor.id, keyword: screenColor.keyword, color: Color(hex: hex))
            }
            return screenColor
        }
    }

    static func savePrintHighlightColors(_ colors: [HighlightColorSetting]) {
        let overrides = Dictionary(
            uniqueKeysWithValues: colors.map { ($0.keyword.lowercased(), $0.color.toHex()) }
        )
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: "PrintHighlightColors")
        }
    }

    static func save(configuration: PrintConfiguration) {
        var encodableColumns: [String: Set<Int>] = [:]
        for (key, value) in configuration.selectedColumns {
            encodableColumns[String(key)] = value
        }

        var encodableTimeColumns: [String: Bool] = [:]
        for (key, value) in configuration.showTimeColumn {
            encodableTimeColumns[String(key)] = value
        }

        if let selectedColumnsData = try? JSONEncoder().encode(encodableColumns) {
            UserDefaults.standard.set(selectedColumnsData, forKey: "PrintSelectedColumns")
        }

        if let timeColumnData = try? JSONEncoder().encode(encodableTimeColumns) {
            UserDefaults.standard.set(timeColumnData, forKey: "PrintShowTimeColumn")
        }

        UserDefaults.standard.set(true, forKey: "PrintColumnsLayout")
        UserDefaults.standard.set(configuration.printWithColors, forKey: "PrintWithColors")
        UserDefaults.standard.set(configuration.showFullHeaders, forKey: "PrintShowHeaders")
        UserDefaults.standard.set(configuration.showPageNumbers, forKey: "PrintShowPageNumbers")
        UserDefaults.standard.set(configuration.showPrintDateTime, forKey: "PrintShowDateTime")
        UserDefaults.standard.set(configuration.orientation == .landscape, forKey: "PrintLandscapeOrientation")
        savePrintHighlightColors(configuration.printHighlightColors)
    }
}

// MARK: - Preview

private func printPreviewSignature(
    _ configuration: PrintConfiguration,
    stackCount: Int
) -> String {
    let columnSignature = configuration.selectedColumns
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value.sorted())" }
        .joined(separator: "|")
    let timeSignature = configuration.showTimeColumn
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "|")
    let highlightSignature = configuration.printHighlightColors
        .map { "\($0.keyword.lowercased())=\($0.color.toHex())" }
        .joined(separator: "|")
    return "\(configuration.selectedStackIndices.sorted())-\(configuration.fontSize)-\(configuration.printWithColors)-\(configuration.showFullHeaders)-\(configuration.showPageNumbers)-\(configuration.showPrintDateTime)-\(configuration.orientation)-\(columnSignature)-\(timeSignature)-\(highlightSignature)-\(stackCount)"
}

final class PrintPreviewDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class PrintPagePreviewHostView: NSView {
    private let scrollView = NSScrollView()
    private var pageDocumentView: PrintPreviewDocumentView?
    private var installedPaginatedView: CueStackPaginatedView?
    private var landscape = false
    private var pageCount = 1

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35).cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.05
        scrollView.maxMagnification = 2.0

        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func clear() {
        installedPaginatedView?.removeFromSuperview()
        installedPaginatedView = nil
        pageDocumentView = nil
        scrollView.documentView = nil
    }

    func install(paginatedView: CueStackPaginatedView, landscape: Bool) {
        self.landscape = landscape
        self.pageCount = paginatedView.numberOfPages

        let pageWidth = paginatedView.paperSize.width
        let pageHeight = paginatedView.pageSliceHeight
        let documentHeight = CGFloat(pageCount) * pageHeight

        let document = PrintPreviewDocumentView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: documentHeight))

        for pageIndex in 0..<pageCount {
            let y = CGFloat(pageIndex) * pageHeight
            let pageBackground = NSView(frame: NSRect(x: 0, y: y, width: pageWidth, height: pageHeight))
            pageBackground.wantsLayer = true
            pageBackground.layer?.backgroundColor = NSColor.white.cgColor
            pageBackground.layer?.cornerRadius = 3
            pageBackground.layer?.shadowColor = NSColor.black.cgColor
            pageBackground.layer?.shadowOpacity = 0.10
            pageBackground.layer?.shadowRadius = 5
            pageBackground.layer?.shadowOffset = CGSize(width: 0, height: -1)
            document.addSubview(pageBackground)
        }

        paginatedView.frame = NSRect(
            x: 0,
            y: 0,
            width: pageWidth,
            height: paginatedView.contentHeight
        )
        document.addSubview(paginatedView)

        for pageIndex in 1..<pageCount {
            let y = CGFloat(pageIndex) * pageHeight
            let separator = NSView(frame: NSRect(x: 0, y: y, width: pageWidth, height: 1))
            separator.wantsLayer = true
            separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
            document.addSubview(separator)
        }

        paginatedView.needsDisplay = true

        installedPaginatedView = paginatedView
        pageDocumentView = document
        scrollView.documentView = document
        scrollToTop()

        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard pageDocumentView != nil else { return }

        let pageWidth = installedPaginatedView?.paperSize.width ?? Self.pageWidth(landscape: landscape)
        let horizontalInset: CGFloat = 8
        let availableWidth = max(1, scrollView.bounds.width - horizontalInset * 2)
        scrollView.magnification = availableWidth / pageWidth
    }

    private func scrollToTop() {
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
    }

    private static func pageWidth(landscape: Bool) -> CGFloat {
        landscape ? 792.0 : 612.0
    }
}

struct CuePrintPreviewRepresentable: NSViewRepresentable {
    let configuration: PrintConfiguration
    let allStacks: [CueStack]

    final class Coordinator {
        var hostView: PrintPagePreviewHostView?
        var cachedSignature: String?
        var paginatedView: CueStackPaginatedView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PrintPagePreviewHostView {
        let host = PrintPagePreviewHostView()
        context.coordinator.hostView = host
        refreshPreview(context: context)
        return host
    }

    func updateNSView(_ nsView: PrintPagePreviewHostView, context: Context) {
        context.coordinator.hostView = nsView
        refreshPreview(context: context)
    }

    private func refreshPreview(context: Context) {
        let signature = printPreviewSignature(configuration, stackCount: allStacks.count)
        guard context.coordinator.cachedSignature != signature else { return }
        context.coordinator.cachedSignature = signature

        guard let view = PrintLayoutBuilder.paginatedView(
            allStacks: allStacks,
            configuration: configuration
        ) else {
            context.coordinator.paginatedView = nil
            context.coordinator.hostView?.clear()
            return
        }

        context.coordinator.paginatedView = view
        context.coordinator.hostView?.install(
            paginatedView: view,
            landscape: configuration.orientation == .landscape
        )
    }
}

// MARK: - Settings View

struct PrintSettingsView: View {
    @Binding var selectedIndices: Set<Int>
    @Binding var fontSize: CGFloat

    var cueStacks: [CueStack]
    var documentName: String
    var highlightColors: [HighlightColorSetting]
    var onPrint: (PrintConfiguration) -> Void
    var onCancel: () -> Void

    @Environment(\.presentationMode) private var presentationMode

    @State private var printWithColors = true
    @State private var showFullHeaders = true
    @State private var showPageNumbers = true
    @State private var showPrintDateTime = true
    @State private var orientation: PrintOrientation = .portrait
    @State private var selectedColumns: [Int: Set<Int>] = [:]
    @State private var showTimeColumn: [Int: Bool] = [:]
    @State private var printHighlightColors: [HighlightColorSetting] = []
    @State private var focusedStackIndex: Int?

    private let contentHeight: CGFloat = 430
    private let selectionPanelWidth: CGFloat = 200
    private let optionsColumnWidth: CGFloat = 280

    private var configuration: PrintConfiguration {
        PrintConfiguration(
            selectedStackIndices: selectedIndices,
            fontSize: fontSize,
            printWithColors: printWithColors,
            showFullHeaders: showFullHeaders,
            showPageNumbers: showPageNumbers,
            showPrintDateTime: showPrintDateTime,
            orientation: orientation,
            selectedColumns: selectedColumns,
            showTimeColumn: showTimeColumn,
            printHighlightColors: printHighlightColors,
            printedAt: nil
        )
    }

    private var selectedCueCount: Int {
        selectedIndices.reduce(0) { total, index in
            guard cueStacks.indices.contains(index) else { return total }
            return total + cueStacks[index].cues.count
        }
    }

    private var estimatedPages: Int {
        guard let previewView = PrintLayoutBuilder.paginatedView(
            allStacks: cueStacks,
            configuration: configuration
        ) else { return 0 }
        return PrintLayoutBuilder.estimatedPageCount(
            for: previewView,
            landscape: orientation == .landscape
        )
    }

    private var focusedStack: CueStack? {
        guard let index = focusedStackIndex, cueStacks.indices.contains(index) else { return nil }
        return cueStacks[index]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                summarySection

                HStack(alignment: .top, spacing: 16) {
                    optionsColumn
                        .frame(width: optionsColumnWidth, height: contentHeight, alignment: .topLeading)

                    stacksAndColumnsColumn
                        .frame(width: selectionPanelWidth * 2 + 12, height: contentHeight, alignment: .topLeading)

                    previewColumn
                        .frame(maxWidth: .infinity)
                        .frame(height: contentHeight, alignment: .topLeading)
                }
            }
            .padding(20)

            Spacer(minLength: 0)

            Divider()
            footer
        }
        .frame(width: 1040, height: 700)
        .onAppear(perform: loadPreferences)
    }

    // MARK: Header & Footer

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Print Cue Sheets")
                    .font(.headline)
                Text(documentName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var footer: some View {
        HStack {
            Button("Cancel", action: dismiss)
                .keyboardShortcut(.cancelAction)

            Spacer()

            if selectedIndices.isEmpty {
                Text("Select at least one cue stack to print.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Print…") {
                var config = configuration
                config.printedAt = Date()
                PrintPreferences.save(configuration: config)
                onPrint(config)
                presentationMode.wrappedValue.dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selectedIndices.isEmpty)
        }
        .padding(16)
    }

    // MARK: Summary

    private var summarySection: some View {
        HStack(spacing: 20) {
            summaryStat(title: "Stacks", value: "\(selectedIndices.count) of \(cueStacks.count)")
            summaryStat(title: "Cues", value: "\(selectedCueCount)")
            summaryStat(title: "Est. pages", value: selectedIndices.isEmpty ? "—" : "\(estimatedPages)")
            Spacer()
            Text(summaryDetail)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 320, alignment: .trailing)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .cornerRadius(10)
    }

    private var summaryDetail: String {
        if selectedIndices.isEmpty {
            return "Choose stacks and columns, then review the page preview."
        }
        return "\(orientation.rawValue) · \(Int(fontSize)) pt · scroll to review all pages"
    }

    private func summaryStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.medium)
        }
    }

    // MARK: Options

    private var optionsColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Page")

                Picker("Orientation", selection: $orientation) {
                    ForEach(PrintOrientation.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Font size")
                    Slider(value: $fontSize, in: 8...18, step: 1)
                    Text("\(Int(fontSize)) pt")
                        .frame(width: 36, alignment: .trailing)
                        .monospacedDigit()
                }

                sectionTitle("Content")
                    .padding(.top, 4)

                Toggle("Show column headers", isOn: $showFullHeaders)
                Toggle("Show page numbers", isOn: $showPageNumbers)
                Toggle("Show print date & time", isOn: $showPrintDateTime)
                Toggle("Use highlight colors", isOn: $printWithColors)

                if printWithColors && !printHighlightColors.isEmpty {
                    printHighlightColorsSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var printHighlightColorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Print Highlight Colors")
                .padding(.top, 4)

            Text("Tune colors for paper — these do not change on-screen colors.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach($printHighlightColors) { $highlight in
                HStack(spacing: 8) {
                    Text(highlight.keyword)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(width: 72, alignment: .leading)
                    ColorPicker("", selection: $highlight.color)
                        .labelsHidden()
                }
            }

            Button("Reset to screen colors") {
                printHighlightColors = highlightColors.map {
                    HighlightColorSetting(id: $0.id, keyword: $0.keyword, color: $0.color)
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
    }

    // MARK: Stacks + Columns

    private var stacksAndColumnsColumn: some View {
        HStack(alignment: .top, spacing: 12) {
            stackListSection
                .frame(width: selectionPanelWidth, height: contentHeight, alignment: .topLeading)
            columnSelectionSection
                .frame(width: selectionPanelWidth, height: contentHeight, alignment: .topLeading)
        }
    }

    private var stackListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Cue Stacks")
                Spacer()
                Button("All") {
                    selectedIndices = Set(cueStacks.indices)
                    cueStacks.indices.forEach { initializeColumns(for: $0) }
                    if focusedStackIndex == nil {
                        focusedStackIndex = cueStacks.indices.first
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Button("None") {
                    selectedIndices.removeAll()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(cueStacks.indices, id: \.self) { index in
                        stackRow(at: index)
                        if index != cueStacks.indices.last {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .frame(maxHeight: .infinity)
    }

    private var columnSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle("Columns to Print")
                    if let stack = focusedStack {
                        Text(stack.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Select a cue stack")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if focusedStackIndex != nil {
                    Button("All") {
                        if let index = focusedStackIndex {
                            initializeColumns(for: index)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    Button("None") {
                        if let index = focusedStackIndex {
                            clearColumns(for: index)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            Group {
                if let stack = focusedStack, let index = focusedStackIndex {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if stack.columns.isEmpty {
                                Text("This stack has no columns.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(stack.columns.indices, id: \.self) { colIndex in
                                    Toggle(isOn: columnBinding(stackIndex: index, columnIndex: colIndex)) {
                                        Text(stack.columns[colIndex].name)
                                            .font(.body)
                                    }
                                }
                            }

                            Toggle(isOn: timeColumnBinding(stackIndex: index)) {
                                Text("Timer column")
                                    .font(.body)
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "tablecells")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Choose a stack to pick which columns appear on the printout.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .frame(maxHeight: .infinity)
    }

    private func stackRow(at index: Int) -> some View {
        let stack = cueStacks[index]
        let isFocused = focusedStackIndex == index

        return HStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { selectedIndices.contains(index) },
                set: { isSelected in
                    if isSelected {
                        selectedIndices.insert(index)
                        if selectedColumns[index] == nil {
                            initializeColumns(for: index)
                        }
                        focusedStackIndex = index
                    } else {
                        selectedIndices.remove(index)
                        if focusedStackIndex == index {
                            focusedStackIndex = selectedIndices.sorted().first
                        }
                    }
                }
            )) {
                EmptyView()
            }
            .labelsHidden()
            .toggleStyle(.checkbox)

            Button {
                focusedStackIndex = index
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(stack.name)
                        .font(.body)
                        .fontWeight(isFocused ? .semibold : .regular)
                        .foregroundColor(.primary)
                    Text("\(stack.cues.count) cue\(stack.cues.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .padding(.vertical, 8)
                .background(isFocused ? Color.accentColor.opacity(0.10) : Color.clear)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
    }

    // MARK: Preview

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Preview")
                Spacer()
                Text(selectedIndices.isEmpty ? "No stacks selected" : "Full page width · scroll for more")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.45))

                if selectedIndices.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("Select a cue stack to see a print preview.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 220)
                    }
                } else {
                    CuePrintPreviewRepresentable(
                        configuration: configuration,
                        allStacks: cueStacks
                    )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: Helpers

    private func dismiss() {
        onCancel()
        presentationMode.wrappedValue.dismiss()
    }

    private func loadPreferences() {
        let prefs = PrintPreferences.load()
        printWithColors = prefs.printWithColors
        showFullHeaders = prefs.showFullHeaders
        showPageNumbers = prefs.showPageNumbers
        showPrintDateTime = prefs.showPrintDateTime
        orientation = prefs.orientation
        showTimeColumn = prefs.showTimeColumn
        printHighlightColors = PrintPreferences.loadPrintHighlightColors(matching: highlightColors)

        if selectedIndices.isEmpty, let firstIndex = cueStacks.indices.first {
            selectedIndices = [firstIndex]
        }

        for index in selectedIndices where selectedColumns[index] == nil {
            initializeColumns(for: index)
        }

        focusedStackIndex = selectedIndices.sorted().first ?? cueStacks.indices.first
    }

    private func initializeColumns(for stackIndex: Int) {
        guard cueStacks.indices.contains(stackIndex) else { return }
        selectedColumns[stackIndex] = Set(cueStacks[stackIndex].columns.indices)
        showTimeColumn[stackIndex] = true
    }

    private func clearColumns(for stackIndex: Int) {
        selectedColumns[stackIndex] = []
        showTimeColumn[stackIndex] = false
    }

    private func columnBinding(stackIndex: Int, columnIndex: Int) -> Binding<Bool> {
        Binding(
            get: { selectedColumns[stackIndex]?.contains(columnIndex) ?? true },
            set: { isSelected in
                var cols = selectedColumns[stackIndex] ?? Set(cueStacks[stackIndex].columns.indices)
                if isSelected {
                    cols.insert(columnIndex)
                } else {
                    cols.remove(columnIndex)
                }
                selectedColumns[stackIndex] = cols
            }
        )
    }

    private func timeColumnBinding(stackIndex: Int) -> Binding<Bool> {
        Binding(
            get: { showTimeColumn[stackIndex] ?? true },
            set: { showTimeColumn[stackIndex] = $0 }
        )
    }
}
