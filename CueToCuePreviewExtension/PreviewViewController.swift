//
//  PreviewViewController.swift
//  CueToCuePreviewExtension
//
//  Created by Corbin Hand on 8/31/24.
//

import Cocoa
import Quartz
import os.log

class PreviewViewController: NSViewController, QLPreviewingController, NSTableViewDataSource, NSTableViewDelegate {
    
    private var tableView: NSTableView!
    private let logger = OSLog(subsystem: "com.yourcompany.CueToCuePreviewExtension", category: "Preview")
    private var cues: [[String]] = []
    private let columnTitles = ["Cue #", "Column 2", "Column 3", "Column 4"]
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        
        let scrollView = NSScrollView(frame: view.bounds)
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        
        tableView = NSTableView(frame: scrollView.bounds)
        tableView.autoresizingMask = [.width, .height]
        tableView.style = .fullWidth
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.backgroundColor = NSColor.black
        
        for (index, title) in columnTitles.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            column.title = title
            column.width = 150
            tableView.addTableColumn(column)
        }
        
        tableView.dataSource = self
        tableView.delegate = self
        
        scrollView.documentView = tableView
        view.addSubview(scrollView)
    }
    
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        os_log("Preparing preview for file: %{public}@", log: logger, type: .debug, url.path)
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                
                if let jsonDict = json as? [String: Any],
                   let cueStacks = jsonDict["cueStacks"] as? [[String: Any]],
                   let firstStack = cueStacks.first,
                   let cues = firstStack["cues"] as? [[String: Any]] {
                    
                    self.cues = cues.compactMap { cue -> [String]? in
                        guard let values = cue["values"] as? [String] else { return nil }
                        return Array(values.prefix(4))  // Take only the first 4 values
                    }
                    
                    DispatchQueue.main.async {
                        self.tableView.reloadData()
                        handler(nil)
                    }
                } else {
                    self.setErrorMessage("Invalid JSON structure")
                    handler(NSError(domain: "PreviewError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON structure"]))
                }
            } catch {
                self.setErrorMessage("Error: \(error.localizedDescription)")
                handler(error)
            }
        }
    }
    
    private func setErrorMessage(_ message: String) {
        DispatchQueue.main.async {
            let label = NSTextField(labelWithString: "Error: \(message)")
            label.textColor = .white
            label.backgroundColor = .clear
            self.view.addSubview(label)
            label.frame = self.view.bounds
            os_log("Error: %{public}@", log: self.logger, type: .error, message)
        }
    }
    
    // MARK: - NSTableViewDataSource
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return cues.count
    }
    
    // MARK: - NSTableViewDelegate
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let columnIndex = tableView.tableColumns.firstIndex(of: tableColumn!) else { return nil }
        
        let cellIdentifier = NSUserInterfaceItemIdentifier("CellID")
        var cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
        
        if cellView == nil {
            cellView = NSTableCellView(frame: NSRect(x: 0, y: 0, width: tableColumn!.width, height: 20))
            let textField = NSTextField(frame: cellView!.bounds)
            textField.isBordered = false
            textField.isEditable = false
            textField.drawsBackground = false
            cellView!.addSubview(textField)
            cellView!.textField = textField
            cellView!.identifier = cellIdentifier
        }
        
        if row < cues.count && columnIndex < cues[row].count {
            cellView?.textField?.stringValue = cues[row][columnIndex]
        } else {
            cellView?.textField?.stringValue = ""
        }
        
        cellView?.textField?.textColor = .white
        
        return cellView
    }
}
