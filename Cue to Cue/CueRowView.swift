//
//  CueRowView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/11/24.
//

import SwiftUI
import AppKit

struct CueRowView: View {
    @Binding var cue: Cue
    @Binding var columns: [Column]
    let index: Int
    let selectedIndex: Int?
    let selectedIndices: Set<Int>
    let fontSize: CGFloat
    let tableBackgroundColor: Color

    let onDelete: (Int) -> Void
    let onCopy: (Int) -> Void
    let onPaste: (Int) -> Void
    let getHighlightColor: (Cue) -> Color
    let saveState: () -> Void
    let onSelect: (Int, Bool, Bool) -> Void // (index, isShiftDown, isCommandDown)
    let onAddCueAbove: (Int) -> Void
    let onAddCueBelow: (Int) -> Void

    // Tracks the cell that's currently being edited (if any)
    @Binding var editingCueIndex: Int?
    @Binding var scrollViewProxy: ScrollViewProxy?
    let isReorderingCues: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Green circle to indicate current row selection
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
                .opacity(selectedIndex == index ? 1 : 0)

            // Render each cell for the columns
            ForEach(cue.values.indices, id: \.self) { columnIndex in
                CellTextFieldWrapper(
                    text: $cue.values[columnIndex],
                    placeholder: "",
                    width: columns[columnIndex].width,
                    fontSize: fontSize,
                    fontColor: Color(textColorForCell(cue)),
                    isSelected: index == selectedIndex,
                    isStruckThrough: cue.isStruckThrough,
                    onEditingChanged: { editing in
                        editingCueIndex = editing ? index : nil
                        if !editing {
                            NSApp.keyWindow?.makeFirstResponder(nil) // Resign first responder
                            saveState()
                        }
                    },
                    onCommit: {
                        // saveState() is already called in onEditingChanged when editing ends
                    }
                )
                .padding(6)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
                .frame(width: columns[columnIndex].width, alignment: .leading)
            }

            Spacer()

            // Timer column
            CellTextFieldWrapper(
                text: $cue.timerValue,
                placeholder: "",
                width: 75,
                fontSize: fontSize,
                fontColor: Color(NSColor.labelColor),
                isSelected: index == selectedIndex,
                isStruckThrough: cue.isStruckThrough,
                onEditingChanged: { editing in
                    editingCueIndex = editing ? index : nil
                    if !editing {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        saveState()
                    }
                },
                onCommit: {
                    // saveState() is already called in onEditingChanged when editing ends
                }
            )
            .padding(6)
            .background(Color.white.opacity(0.1))
            .cornerRadius(6)
            .frame(width: 75, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(backgroundColorForRow)
        .cornerRadius(8)
        .onTapGesture {
            // Only handle tap gestures when NOT reordering cues
            guard !isReorderingCues else { return }
            
            // Capture modifier keys when tapped
            let modifierFlags = NSEvent.modifierFlags
            let isShiftDown = modifierFlags.contains(.shift)
            let isCommandDown = modifierFlags.contains(.command)
            
            onSelect(index, isShiftDown, isCommandDown)
            
            // Only scroll if not multi-selecting
            if !isShiftDown && !isCommandDown {
                withAnimation {
                    scrollViewProxy?.scrollTo(index, anchor: .center)
                }
            }
        }
        .simultaneousGesture(
            // Add a high-priority drag gesture when reordering to prevent tap gesture interference
            isReorderingCues ? DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    // This gesture exists only to prevent tap gesture interference
                    // The actual drag handling is done by List's .onMove
                }
                .onEnded { _ in
                    // This gesture exists only to prevent tap gesture interference
                    // The actual drag handling is done by List's .onMove
                } : nil
        )
        .contextMenu {
            Button(action: { onAddCueAbove(index) }) {
                Label("Add Cue Above", systemImage: "arrow.up")
            }
            Button(action: { onAddCueBelow(index) }) {
                Label("Add Cue Below", systemImage: "arrow.down")
            }
            Divider()
            Button(action: { onDelete(index) }) {
                Label("Delete Cue", systemImage: "trash")
            }
            Button(action: { onCopy(index) }) {
                Label("Copy Cue", systemImage: "doc.on.doc")
            }
            Button(action: { onPaste(index) }) {
                Label("Paste Cue", systemImage: "doc.on.clipboard")
            }
            // Strike Through option
            Button(action: { toggleStrikethrough() }) {
                Label("Strike Through", systemImage: "strikethrough")
            }
        }
    }

    private func toggleStrikethrough() {
        cue.isStruckThrough.toggle()
        saveState()
    }

    // MARK: - Row Appearance Helpers

    private var backgroundColorForRow: Color {
        if selectedIndices.contains(index) && selectedIndices.count > 1 {
            // Multi-selected row
            return Color.blue.opacity(0.2)
        } else if index == selectedIndex {
            // Active row
            return Color.green.opacity(0.1)
        } else if let selected = selectedIndex, index == selected + 1 {
            // Up next row
            return Color.yellow.opacity(0.1)
        } else {
            return tableBackgroundColor
        }
    }

    private func nsFontForCell(columnIndex: Int) -> NSFont {
        if let selected = selectedIndex, index == selected + 1 {
            return NSFont.boldSystemFont(ofSize: fontSize)
        } else {
            return NSFont.systemFont(ofSize: fontSize)
        }
    }

    private var nsFontForTimerCell: NSFont {
        if let selected = selectedIndex, index == selected + 1 {
            return NSFont.boldSystemFont(ofSize: fontSize)
        } else {
            return NSFont.systemFont(ofSize: fontSize)
        }
    }

    private func textColorForCell(_ cue: Cue) -> NSColor {
        let swiftUIColor = getHighlightColor(cue)
        guard let cgColor = swiftUIColor.cgColor else {
            return NSColor.labelColor
        }
        return NSColor(cgColor: cgColor) ?? NSColor.labelColor
    }
}

// MARK: - NoScrollingTextField

struct NoScrollingTextField: NSViewRepresentable {
    @Binding var text: String
    var textColor: NSColor
    var font: NSFont
    var alignment: NSTextAlignment
    var isEditable: Bool = true
    var isSelectable: Bool = true
    var isStrikethrough: Bool = false // Strike-through support
    var onEditingChanged: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.isEditable = isEditable
        textField.isSelectable = isSelectable
        textField.delegate = context.coordinator
        textField.alignment = alignment
        updateAttributedString(for: textField)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Force update the attributed string on every update
        updateAttributedString(for: nsView)
        nsView.alignment = alignment
    }

    private func updateAttributedString(for textField: NSTextField) {
        // If the text is struck through, use gray as the effective color.
        let effectiveColor: NSColor = isStrikethrough ? NSColor.gray : textColor

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: effectiveColor,
            .strikethroughStyle: isStrikethrough ? NSUnderlineStyle.single.rawValue : 0,
            .strikethroughColor: effectiveColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        textField.attributedStringValue = attributed
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: NoScrollingTextField

        init(_ parent: NoScrollingTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onEditingChanged?(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEditingChanged?(false)
        }

        func controlTextDidChange(_ notification: Notification) {
            if let textField = notification.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}