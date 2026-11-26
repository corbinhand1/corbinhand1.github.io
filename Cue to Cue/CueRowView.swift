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
    let upNextIndex: Int?
    let selectedIndices: Set<Int>
    let fontSize: CGFloat
    let tableBackgroundColor: Color

    let onDelete: (Int) -> Void
    let onCopy: (Int) -> Void
    let onPaste: (Int) -> Void
    let getHighlightColor: (Cue) -> Color
    let saveState: () -> Void
    let updateWebClients: () -> Void
    let onCueValueCommitted: (UUID, Int, String) -> Void
    let onSelect: (Int, Bool, Bool) -> Void // (index, isShiftDown, isCommandDown)
    let onAddCueAbove: (Int) -> Void
    let onAddCueBelow: (Int) -> Void

    // Tracks the cell that's currently being edited (if any)
    @Binding var editingCueIndex: Int?
    @Binding var scrollViewProxy: ScrollViewProxy?
    let isReorderingCues: Bool

    /// Column being edited in this row (-1 = timer), so only that cell
    /// shows an edit frame; every other cell is plain text.
    @State private var editingColumn: Int?

    private var isLive: Bool { index == selectedIndex }
    private var isUpNext: Bool { upNextIndex == index && !isLive }

    var body: some View {
        HStack(spacing: 8) {
            // State column: LIVE / NEXT / CUT, readable without relying on color.
            CueStateChip(state: rowState)
                .frame(width: CueRowStyle.stateColumnWidth, alignment: .leading)

            // Cells are plain text; only the cell being edited is a real text
            // field. (One NSTextField per cell made scrolling stutter: macOS
            // built ~9 of them for every row coming into view.)
            ForEach(cue.values.indices, id: \.self) { columnIndex in
                cell(column: columnIndex, text: $cue.values[columnIndex])
                    .frame(width: columns[columnIndex].width, alignment: .leading)
            }

            Spacer()

            // Timer column
            cell(column: -1, text: $cue.timerValue)
                .frame(width: CueRowStyle.timerColumnWidth, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(backgroundColorForRow)
        .overlay(rowStateOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(rowState.accessibilityLabel.map { Text("\($0), cue \(cue.values.first ?? "")") } ?? Text("Cue \(cue.values.first ?? "")"))
        .onTapGesture {
            // Only handle tap gestures when NOT reordering cues
            guard !isReorderingCues else { return }
            
            // Capture modifier keys when tapped
            let modifierFlags = NSEvent.modifierFlags
            let isShiftDown = modifierFlags.contains(.shift)
            let isCommandDown = modifierFlags.contains(.command)
            
            // No scrolling here: the row is already on screen, and moving it
            // under the pointer made double-click-to-type jump around.
            onSelect(index, isShiftDown, isCommandDown)
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
        updateWebClients()
    }

    // MARK: - Row Appearance Helpers

    // MARK: - Cells

    /// Column order for Tab / Shift-Tab: every column, then the timer (-1).
    private var editableColumns: [Int] { Array(cue.values.indices) + [-1] }

    @ViewBuilder
    private func cell(column: Int, text: Binding<String>) -> some View {
        if editingColumn == column {
            CellTextFieldWrapper(
                text: text,
                placeholder: "",
                width: column == -1 ? CueRowStyle.timerColumnWidth : columns[column].width,
                fontSize: fontSize,
                fontColor: cellColor(column: column),
                isSelected: isLive,
                isStruckThrough: cue.isStruckThrough,
                onEditingChanged: { editing in
                    if editing {
                        editingCueIndex = index
                    } else {
                        finishEditing(column: column)
                    }
                },
                onCommit: {},
                autoFocus: true,
                onTab: { step in moveEditing(from: column, by: step) }
            )
            .padding(6)
            .modifier(CellEditFrame(isEditing: true))
        } else {
            Text(text.wrappedValue)
                .font(.system(size: fontSize, weight: isLive ? .bold : .regular))
                .foregroundColor(cue.isStruckThrough ? .gray : cellColor(column: column))
                .strikethrough(cue.isStruckThrough, color: .gray)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: ceil(fontSize * 1.35), alignment: .leading)
                .padding(6)
                .contentShape(Rectangle())
                // Single click selects the row (row gesture); double-click edits.
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    guard !isReorderingCues else { return }
                    beginEditing(column: column)
                })
        }
    }

    private func cellColor(column: Int) -> Color {
        if column == -1 { return Color(NSColor.labelColor) }
        // Live row uses the main text color: keyword colors (e.g. video
        // blue) fall below 4.5:1 on the green live fill.
        return isLive ? fontColorForLiveRow : Color(textColorForCell(cue))
    }

    private func beginEditing(column: Int) {
        editingColumn = column
        editingCueIndex = index   // stops arrow keys moving the cue while typing
    }

    private func moveEditing(from column: Int, by step: Int) {
        guard let position = editableColumns.firstIndex(of: column) else { return }
        let next = position + step
        guard editableColumns.indices.contains(next) else {
            finishEditing(column: column)
            NSApp.keyWindow?.makeFirstResponder(nil)
            return
        }
        commit(column: column)
        beginEditing(column: editableColumns[next])
    }

    /// End editing for `column` unless editing already moved to another cell.
    private func finishEditing(column: Int) {
        guard editingColumn == column else { return }
        editingColumn = nil
        editingCueIndex = nil
        commit(column: column)
    }

    private func commit(column: Int) {
        saveState()
        if column >= 0, cue.values.indices.contains(column) {
            onCueValueCommitted(cue.id, column, cue.values[column])
        }
    }

    private var fontColorForLiveRow: Color { Color(nsColor: NSColor(calibratedWhite: 0.97, alpha: 1)) }

    private var rowState: CueRowState {
        if isLive { return .live }
        if isUpNext { return .next }
        if cue.isStruckThrough { return .cut }
        return .none
    }

    /// Fill only; the live/next edges and outline are drawn by the overlay so
    /// state never depends on a faint tint alone (the old 10% tints measured
    /// about 1.2:1 against a normal row).
    private var backgroundColorForRow: some View {
        ZStack {
            tableBackgroundColor
            if selectedIndices.contains(index) && selectedIndices.count > 1 {
                Color.blue.opacity(0.25)
            } else if isLive {
                CueRowStyle.live.opacity(0.24)
            }
        }
    }

    @ViewBuilder
    private var rowStateOverlay: some View {
        if isLive {
            HStack(spacing: 0) {
                CueRowStyle.live.frame(width: 4)
                Spacer(minLength: 0)
            }
        } else if isUpNext {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(CueRowStyle.next.opacity(0.85), lineWidth: 1)
                CueRowStyle.next.frame(width: 4)
            }
        }
    }

    private func nsFontForCell(columnIndex: Int) -> NSFont {
        if let upNextIndex, index == upNextIndex {
            return NSFont.boldSystemFont(ofSize: fontSize)
        } else {
            return NSFont.systemFont(ofSize: fontSize)
        }
    }

    private var nsFontForTimerCell: NSFont {
        if let upNextIndex, index == upNextIndex {
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

// MARK: - Row state styling (option A)

enum CueRowState {
    case none, live, next, cut

    var label: String? {
        switch self {
        case .live: return "LIVE"
        case .next: return "NEXT"
        case .cut: return "CUT"
        case .none: return nil
        }
    }

    var accessibilityLabel: String? {
        switch self {
        case .live: return "Live"
        case .next: return "Up next"
        case .cut: return "Cut"
        case .none: return nil
        }
    }
}

enum CueRowStyle {
    /// Live = green, next = amber. Both also carry a label and a shape
    /// (solid edge vs outline), so they work without color vision.
    static let live = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
    static let next = Color(red: 0xFF / 255, green: 0xD6 / 255, blue: 0x0A / 255)
    static let stateColumnWidth: CGFloat = 40
    static let timerColumnWidth: CGFloat = 75
}

struct CueStateChip: View {
    let state: CueRowState

    var body: some View {
        if let label = state.label {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .foregroundColor(foreground)
                .background(background)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(height: 1)
        }
    }

    private var foreground: Color {
        switch state {
        case .live: return Color(red: 0.02, green: 0.13, blue: 0.06)
        case .next: return CueRowStyle.next
        default: return Color.gray
        }
    }

    private var background: Color { state == .live ? CueRowStyle.live : .clear }

    private var border: Color {
        switch state {
        case .live: return CueRowStyle.live
        case .next: return CueRowStyle.next
        default: return Color.gray.opacity(0.5)
        }
    }
}

/// Cells are plain text; only the cell being edited gets a frame.
struct CellEditFrame: ViewModifier {
    let isEditing: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(isEditing ? 0.08 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.accentColor.opacity(isEditing ? 0.9 : 0), lineWidth: 1.5)
            )
    }
}
