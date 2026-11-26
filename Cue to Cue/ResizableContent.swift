//
//  ResizableContent.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/11/24.
//

import SwiftUI

struct ResizableColumnHeader: View {
    @Binding var column: Column
    @Binding var allColumns: [Column]
    @Binding var font: Font
    @Binding var fontSize: CGFloat
    @Binding var fontColor: Color
    @Binding var cues: [Cue]
    @Binding var isReorderingCues: Bool
    let addColumn: () -> Void
    let deleteColumn: (Int) -> Void

    @State private var isEditing: Bool = false
    /// Move arrows appear only while hovering, so the header reads as labels.
    @State private var isHovering: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Column movement buttons (hover to reveal)
            HStack {
                moveButton(direction: .left)
                Spacer()
                moveButton(direction: .right)
            }
            .frame(height: 14)
            .padding(.horizontal, 6)
            .opacity(isHovering ? 1 : 0)

            // Column title
            HStack(spacing: 0) {
                if isEditing {
                    TextField("Column Title", text: $column.name, onCommit: {
                        isEditing = false
                    })
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(font.weight(.semibold))
                    .foregroundColor(fontColor)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                } else {
                    Text(column.name.uppercased())
                        .font(.system(size: max(10, fontSize - 3), weight: .semibold))
                        .tracking(0.8)
                        .foregroundColor(fontColor.opacity(0.65))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { isEditing = true }
                        .help("Click to rename. Hover to move; drag the edge to resize.")
                }

                // Resizing handle
                ResizeHandle(width: $column.width)
            }.padding(.bottom, 6)
        }
        .frame(width: column.width)
        .padding(.horizontal, 4)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(action: {
                if let index = allColumns.firstIndex(where: { $0.id == column.id }) {
                    deleteColumn(index)
                }
            }) {
                Label("Delete Column", systemImage: "trash")
            }
        }
    }
        
    private func moveButton(direction: MoveDirection) -> some View {
        Button(action: {
            move(direction: direction)
        }) {
            Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                .accessibilityLabel(Text(direction == .left ? "Move Column Left" : "Move Column Right"))
                .help(direction == .left ? "Move Column Left" : "Move Column Right")
                .foregroundColor(buttonColor(for: direction))
                .font(.system(size: 10))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isButtonDisabled(for: direction))
    }
    
    private func buttonColor(for direction: MoveDirection) -> Color {
        isButtonDisabled(for: direction) ? .gray.opacity(0.3) : .white
    }
    
    private func isButtonDisabled(for direction: MoveDirection) -> Bool {
        guard let index = allColumns.firstIndex(where: { $0.id == column.id }) else { return true }
        return direction == .left ? index == 0 : index == allColumns.count - 1
    }
    
    private func move(direction: MoveDirection) {
        guard let fromIndex = allColumns.firstIndex(where: { $0.id == column.id }) else { return }
        let toIndex = direction == .left ? fromIndex - 1 : fromIndex + 1
        guard toIndex >= 0 && toIndex < allColumns.count else { return }
        
        withAnimation {
            allColumns.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: direction == .left ? toIndex : toIndex + 1)
            for i in 0..<cues.count {
                cues[i].values.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: direction == .left ? toIndex : toIndex + 1)
            }
        }
    }
}

struct ResizeHandle: View {
    @Binding var width: CGFloat
    @State private var isDragging = false
    
    var body: some View {
        // Thin divider line with a wider invisible grab area.
        Rectangle()
            .fill(Color.gray.opacity(isDragging ? 0.9 : 0.3))
            .frame(width: isDragging ? 2 : 1, height: 16)
            .frame(width: 9, height: 20)
            .contentShape(Rectangle())
            .offset(x: 4)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        width = max(50, width + value.translation.width)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}

struct HeaderButtons: View {
    let addColumn: () -> Void
    @Binding var isReorderingCues: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: addColumn) {
                Image(systemName: "plus")
                    .accessibilityLabel(Text("Add Column"))
                    .help("Add Column")
                    .foregroundColor(.white.opacity(0.85))
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 22)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button(action: { isReorderingCues.toggle() }) {
                Image(systemName: isReorderingCues ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                    .accessibilityLabel(Text(isReorderingCues ? "Finish Reordering Cues" : "Reorder Cues"))
                    .help(isReorderingCues ? "Finish Reordering Cues" : "Reorder Cues")
                    .foregroundColor(isReorderingCues ? .blue : .white.opacity(0.85))
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 8)
    }
}

enum MoveDirection {
    case left, right
}

// Add ResizableDivider here so ContentView can find it
struct ResizableDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 10)

            Rectangle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 4, height: 50)
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    width = max(minWidth, min(width + value.translation.width, maxWidth))
                }
        )
    }
}
