//
//  CellTextFieldWrapper.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 1/15/25.
//

import SwiftUI
import AppKit

struct CellTextFieldWrapper: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let width: CGFloat
    let fontSize: CGFloat
    let fontColor: Color
    let isSelected: Bool
    let isStruckThrough: Bool
    let onEditingChanged: (Bool) -> Void
    let onCommit: () -> Void
    /// Become first responder as soon as the field appears (double-click to edit).
    var autoFocus: Bool = false
    /// Tab (+1) / Shift-Tab (-1) while editing.
    var onTab: ((Int) -> Void)? = nil
    
    func makeNSView(context: Context) -> CellTextField {
        let textField = CellTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.backgroundColor = NSColor.clear
        textField.focusRingType = .none
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.usesSingleLineMode = true
        if autoFocus {
            DispatchQueue.main.async {
                guard let window = textField.window else { return }
                window.makeFirstResponder(textField)
                // Caret at the end, like clicking after the text.
                if let editor = textField.currentEditor() {
                    editor.selectedRange = NSRange(location: (textField.stringValue as NSString).length, length: 0)
                }
            }
        }
        return textField
    }
    
    func updateNSView(_ nsView: CellTextField, context: Context) {
        nsView.stringValue = text
        nsView.font = NSFont.systemFont(ofSize: fontSize, weight: isSelected ? .bold : .regular)
        
        // Apply strike-through styling
        if isStruckThrough {
            let effectiveColor = NSColor.gray
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: isSelected ? .bold : .regular),
                .foregroundColor: effectiveColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: effectiveColor
            ]
            let attributedString = NSAttributedString(string: text, attributes: attributes)
            nsView.attributedStringValue = attributedString
        } else {
            nsView.textColor = NSColor(fontColor)
            // Reset to plain string to remove any previous strike-through
            nsView.stringValue = text
        }
        
        // Update coordinator with current state
        context.coordinator.parent = self
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CellTextFieldWrapper
        
        init(_ parent: CellTextFieldWrapper) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
        
        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onEditingChanged(true)
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)):
                if let onTab = parent.onTab { onTab(1); return true }
            case #selector(NSResponder.insertBacktab(_:)):
                if let onTab = parent.onTab { onTab(-1); return true }
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.insertNewline(_:)):
                // Esc / Return: finish editing this cell.
                control.window?.makeFirstResponder(nil)
                return true
            default:
                break
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onEditingChanged(false)
            parent.onCommit()
        }
    }
}


