//
//  Delegates.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/11/24.
//

import Foundation
import SwiftUI

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

struct CueStackDropDelegate: DropDelegate {
    @Binding var item: Int?
    @Binding var cueStacks: [CueStack]
    var currentIndex: Int
    
    func performDrop(info: DropInfo) -> Bool {
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let item = item else { return }
        
        if item != currentIndex {
            let from = cueStacks[item]
            cueStacks.remove(at: item)
            cueStacks.insert(from, at: currentIndex)
            self.item = currentIndex
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}
