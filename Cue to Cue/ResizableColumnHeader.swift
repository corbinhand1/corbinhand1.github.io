//
//  ResizableColumnHeader.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/5/24.
//

import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ResizableColumnHeader: View {
    @Binding var column: Column
    @Binding var allColumns: [Column]
    @Binding var font: Font
    @Binding var fontSize: CGFloat
    @Binding var fontColor: Color
    @Binding var columnToDelete: Int?
    @Binding var cues: [Cue]
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack {
            Capsule()
                .fill(Color.gray)
                .frame(width: 20, height: 8)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                            isDragging = true
                        }
                        .onEnded { value in
                            if let fromIndex = allColumns.firstIndex(of: column) {
                                let toIndex = (value.translation.width > 0) ? fromIndex + 1 : fromIndex - 1
                                if toIndex >= 0 && toIndex < allColumns.count {
                                    withAnimation {
                                        allColumns.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex)
                                        for i in 0..<cues.count {
                                            let temp = cues[i].values[fromIndex]
                                            cues[i].values[fromIndex] = cues[i].values[toIndex]
                                            cues[i].values[toIndex] = temp
                                        }
                                    }
                                }
                            }
                            dragOffset = .zero
                            isDragging = false
                        }
                )
                .contextMenu {
                    Button(action: {
                        if let index = allColumns.firstIndex(of: column) {
                            columnToDelete = index
                        }
                    }) {
                        Text("Delete Column")
                        Image(systemName: "trash")
                    }
                }

            HStack(spacing: -5) {
                TextField("Column Title", text: $column.name)
                    .font(font)
                    .bold()
                    .foregroundColor(fontColor)
                    .frame(width: self.column.width, alignment: .leading)
                    .background(self.isDragging ? Color.gray.opacity(0.5) : Color.clear)
                    .onDrag {
                        self.isDragging = true
                        return NSItemProvider(object: String(self.column.id.uuidString) as NSString)
                    }
                    .onDrop(of: [.text], delegate: ColumnDropDelegate(column: self.$column, allColumns: self.$allColumns, cues: self.$cues))
                
                Rectangle()
                    .foregroundColor(Color.gray)
                    .frame(width: 5, height: 40)
                    .gesture(DragGesture()
                                .onChanged { value in
                                    self.column.width = max(50, self.column.width + value.translation.width)
                                }
                                .onEnded { _ in
                                    self.isDragging = false
                                })
            }
        }
    }
}

struct ColumnDropDelegate: DropDelegate {
    @Binding var column: Column
    @Binding var allColumns: [Column]
    @Binding var cues: [Cue]

    func dropEntered(info: DropInfo) {
        guard let fromIndex = allColumns.firstIndex(of: column) else { return }

        if let provider = info.itemProviders(for: [.text]).first {
            provider.loadObject(ofClass: NSString.self) { (string, error) in
                guard let uuidString = string as? String,
                      let toColumn = allColumns.first(where: { $0.id.uuidString == uuidString }),
                      let toIndex = allColumns.firstIndex(of: toColumn) else { return }

                DispatchQueue.main.async {
                    withAnimation {
                        allColumns.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                        for i in 0..<cues.count {
                            let temp = cues[i].values[fromIndex]
                            cues[i].values[fromIndex] = cues[i].values[toIndex]
                            cues[i].values[toIndex] = temp
                        }
                    }
                }
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        return true
    }
}

struct CueDropDelegate: DropDelegate {
    @Binding var item: Cue?
    @Binding var listData: [Cue]
    var currentItem: Cue

    func dropEntered(info: DropInfo) {
        guard let item = item, item != currentItem,
              let fromIndex = listData.firstIndex(of: item),
              let toIndex = listData.firstIndex(of: currentItem) else { return }

        withAnimation {
            listData.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        item = nil
        return true
    }
}
