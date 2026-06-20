//
//  CueStackPreviewProvider.swift
//  CueToCuePreviewExtension
//

import AppKit
import Quartz

@objc(CueStackPreviewProvider)
final class CueStackPreviewProvider: NSViewController, QLPreviewingController, NSTableViewDataSource, NSTableViewDelegate {

    private let titleLabel = NSTextField(labelWithString: "")
    private let stackPopup = NSPopUpButton()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    private var stacks: [CueStackPreviewParser.ParsedStack] = []
    private var columnTitles: [String] = []
    private var rows: [[String]] = []

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 920, height: 640))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).cgColor

        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        stackPopup.translatesAutoresizingMaskIntoConstraints = false
        stackPopup.target = self
        stackPopup.action = #selector(stackSelectionChanged(_:))
        stackPopup.isHidden = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 1, height: 1)
        tableView.backgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.11, alpha: 1)
        tableView.gridColor = NSColor(white: 0.25, alpha: 1)
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = NSTableView.ColumnAutoresizingStyle(rawValue: 0)!
        tableView.dataSource = self
        tableView.delegate = self
        scrollView.documentView = tableView

        container.addSubview(titleLabel)
        container.addSubview(stackPopup)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            stackPopup.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            stackPopup.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stackPopup.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: stackPopup.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        guard url.pathExtension.lowercased() == "cuestack" else {
            handler(PreviewError.unsupportedType)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let document = try CueStackPreviewParser.parse(at: url)
                DispatchQueue.main.async {
                    self.loadViewIfNeeded()
                    self.apply(document)
                    self.view.layoutSubtreeIfNeeded()
                    handler(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadViewIfNeeded()
                    self.showError(error.localizedDescription)
                    self.view.layoutSubtreeIfNeeded()
                    handler(error)
                }
            }
        }
    }

    private func apply(_ document: CueStackPreviewParser.ParsedDocument) {
        titleLabel.stringValue = document.fileTitle
        stacks = document.stacks

        stackPopup.removeAllItems()
        for (index, stack) in stacks.enumerated() {
            let cueCount = stack.rows.count
            let suffix = cueCount == 1 ? "1 cue" : "\(cueCount) cues"
            stackPopup.addItem(withTitle: "\(stack.name) (\(suffix))")
            stackPopup.lastItem?.tag = index
        }

        stackPopup.isHidden = stacks.count <= 1
        showStack(at: 0)
    }

    @objc private func stackSelectionChanged(_ sender: NSPopUpButton) {
        showStack(at: sender.indexOfSelectedItem)
    }

    private func showStack(at index: Int) {
        guard stacks.indices.contains(index) else { return }

        let stack = stacks[index]
        columnTitles = stack.columns
        rows = stack.rows

        tableView.tableColumns.forEach { tableView.removeTableColumn($0) }

        for (columnIndex, title) in columnTitles.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("col-\(columnIndex)"))
            column.title = title
            column.minWidth = 40
            column.maxWidth = 800
            column.width = initialColumnWidth(for: columnIndex, title: title)
            column.resizingMask = .userResizingMask
            tableView.addTableColumn(column)
        }

        tableView.reloadData()
    }

    private func initialColumnWidth(for columnIndex: Int, title: String) -> CGFloat {
        let headerWidth = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
        ]).width + 24
        let font = NSFont.systemFont(ofSize: 12)
        var maxWidth = headerWidth
        for row in rows where columnIndex < row.count {
            let cellWidth = (row[columnIndex] as NSString).size(withAttributes: [.font: font]).width + 16
            maxWidth = max(maxWidth, cellWidth)
        }
        return min(max(maxWidth, 80), 320)
    }

    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
        guard column < columnTitles.count else { return 80 }
        return initialColumnWidth(for: column, title: columnTitles[column])
    }

    private func showError(_ message: String) {
        titleLabel.stringValue = "Unable to preview this cue stack"
        stackPopup.isHidden = true
        columnTitles = ["Details"]
        rows = [[message]]
        tableView.tableColumns.forEach { tableView.removeTableColumn($0) }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("error"))
        column.title = "Details"
        column.width = 800
        tableView.addTableColumn(column)
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn,
              let columnIndex = tableView.tableColumns.firstIndex(of: tableColumn),
              row < rows.count,
              columnIndex < rows[row].count else {
            return nil
        }

        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let view = NSTableCellView()
            view.identifier = identifier
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingTail
            field.textColor = .white
            field.font = NSFont.systemFont(ofSize: 12)
            field.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(field)
            view.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                field.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            return view
        }()

        cell.textField?.stringValue = rows[row][columnIndex]
        return cell
    }
}

private enum CueStackPreviewParser {
    struct ParsedStack {
        let name: String
        let columns: [String]
        let rows: [[String]]
    }

    struct ParsedDocument {
        let fileTitle: String
        let stacks: [ParsedStack]
    }

    static func parse(at url: URL) throws -> ParsedDocument {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cueStacks = root["cueStacks"] as? [[String: Any]],
              !cueStacks.isEmpty else {
            throw PreviewError.invalidStructure
        }

        let fileTitle = url.deletingPathExtension().lastPathComponent
        let stacks = cueStacks.enumerated().map { index, stack in
            parseStack(stack, fallbackName: "Stack \(index + 1)")
        }

        guard stacks.contains(where: { !$0.rows.isEmpty }) else {
            throw PreviewError.noCues
        }

        return ParsedDocument(fileTitle: fileTitle, stacks: stacks)
    }

    private static func parseStack(_ stack: [String: Any], fallbackName: String) -> ParsedStack {
        let stackName = (stack["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (stackName?.isEmpty == false ? stackName! : fallbackName)

        let columns = (stack["columns"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let columnTitles = columns.isEmpty ? ["Cue #", "Description", "Preset", "Audio"] : columns

        let cues = stack["cues"] as? [[String: Any]] ?? []
        let rows: [[String]] = cues.map { cue in
            let values = cue["values"] as? [String] ?? []
            return (0..<columnTitles.count).map { index in
                index < values.count ? values[index] : ""
            }
        }

        return ParsedStack(name: name, columns: columnTitles, rows: rows)
    }
}

private enum PreviewError: LocalizedError {
    case invalidStructure
    case noCues
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .invalidStructure:
            return "This file does not contain a recognizable Cue to Cue stack."
        case .noCues:
            return "This file has no cues to preview."
        case .unsupportedType:
            return "This preview extension only handles .cuestack files."
        }
    }
}
