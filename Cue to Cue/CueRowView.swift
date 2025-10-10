//
//  CueRowView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/5/24.
//

import SwiftUI

struct CueRowView: View {
    @Binding var cue: Cue
    let columns: [Column]
    let rowIndex: Int
    @Binding var selectedCueIndex: Int?
    let fontSize: CGFloat
    let fontColor: Color
    let tableBackgroundColor: Color
    let scrollViewProxy: ScrollViewProxy?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { columnIndex in
                TextField("", text: $cue.values[columnIndex], onEditingChanged: { editing in
                    if !editing {
                        // Perform necessary updates only when editing ends
                    }
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: columnIndex < columns.count ? columns[columnIndex].width : 100, alignment: .leading)
                .font(selectedCueIndex == rowIndex ? .system(size: fontSize, weight: .bold) : .system(size: fontSize))
                .foregroundColor(getHighlightColor(for: cue))
            }
            Spacer()
        }
        .background(selectedCueIndex == rowIndex ? Color.green.opacity(0.2) : tableBackgroundColor)
        .frame(height: fontSize * 2)
        .onTapGesture {
            selectedCueIndex = rowIndex
            withAnimation {
                scrollViewProxy?.scrollTo(rowIndex, anchor: .center)
            }
        }
    }

    private func getHighlightColor(for cue: Cue) -> Color {
        // Implement the logic for highlighting based on the cue's values
        return fontColor
    }
}
