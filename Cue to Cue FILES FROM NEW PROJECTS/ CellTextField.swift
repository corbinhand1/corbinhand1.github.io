//
//   CellTextField.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 2/28/25.
//

import AppKit

class CellTextField: NSTextField {
    // Override to add copy/paste menu items
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(selfCopy), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(selfPaste), keyEquivalent: "v"))
        return menu
    }
    
    // Handle context menu
    override func rightMouseDown(with event: NSEvent) {
        if let menu = self.menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
    
    // Custom copy action
    @objc private func selfCopy() {
        // If there's selected text in the editor, copy that
        if let editor = self.currentEditor() as? NSTextView,
           editor.selectedRange.length > 0 {
            editor.copy(nil)
        } else {
            // Otherwise copy the whole field
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(self.stringValue, forType: .string)
        }
    }
    
    // Custom paste action
    @objc private func selfPaste() {
        guard let pasteboardString = NSPasteboard.general.string(forType: .string) else {
            return
        }
        
        if let editor = self.currentEditor() as? NSTextView {
            // We're in edit mode, insert at current position
            editor.insertText(pasteboardString, replacementRange: editor.selectedRange())
            self.stringValue = editor.string
        } else {
            // Replace the whole string if not in edit mode
            self.stringValue = pasteboardString
        }
        
        // Notify of the change
        if let delegate = self.delegate {
            let notification = Notification(name: NSControl.textDidChangeNotification, object: self)
            delegate.controlTextDidChange?(notification)
        }
    }
}
