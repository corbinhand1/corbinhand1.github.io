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

    var body: some View {
        VStack(spacing: 0) {
            // Column movement buttons
            HStack {
                moveButton(direction: .left)
                Spacer()
                moveButton(direction: .right)
            }
            .frame(height: 20)
            .padding(.bottom, 2)
            .padding(.horizontal, 8)

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
                    Text(column.name)
                        .font(font.weight(.semibold))
                        .foregroundColor(fontColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { isEditing = true }
                }
                
                // Resizing handle
                ResizeHandle(width: $column.width)
            }.padding(.bottom, 10)
        }
        .frame(width: column.width)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .offset(x: 30)
        .padding(.horizontal, 4)
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
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(isDragging ? 1 : 0.5))
            .frame(width: 8, height: 20)
            .offset(x: 4)
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
                Label("Add Column", systemImage: "plus")
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .background(Color.blue)
            .cornerRadius(8)

            Button(action: { isReorderingCues.toggle() }) {
                Image(systemName: isReorderingCues ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                    .foregroundColor(isReorderingCues ? .blue : .white)
                    .font(.system(size: 20))
            }
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
