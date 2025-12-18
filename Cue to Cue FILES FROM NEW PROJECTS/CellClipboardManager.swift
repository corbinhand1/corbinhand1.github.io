//
//  CellClipboardManager.swift
//  Cue to Cue
//

import AppKit

class CellClipboardManager {
    static let shared = CellClipboardManager()
    
    func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    func pasteText() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }
}
