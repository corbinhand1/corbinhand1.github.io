//
//  CuePrintRender.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 3/11/25.
//

import AppKit

extension CueStackPaginatedView {
    override func draw(_ dirtyRect: NSRect) {
        // Ensure drawing is performed on the main thread.
        assert(Thread.isMainThread, "Drawing code must be executed on the main thread!")
        
        // Save the current graphics state.
        NSGraphicsContext.saveGraphicsState()
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }
        
        // Log a warning if there is no current graphics context.
        if NSGraphicsContext.current == nil {
            NSLog("Warning: NSGraphicsContext.current is nil in draw(_:)")
            return
        }
        
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            NSLog("Error: CGContext is nil!")
            return
        }
        
        // Fill background with white
        context.setFillColor(NSColor.white.cgColor)
        context.fill(dirtyRect)
        
        let contentWidth = bounds.width - (Self.sideMargin * 2)
        var yPosition: CGFloat = Self.topMargin
        
        // For each cue stack
        for stackIndex in 0..<cueStacks.count {
            if yPosition > dirtyRect.maxY { break }
            
            let cueStack = cueStacks[stackIndex]
            
            // Draw cue stack name
            let stackNameAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: fontSize + 4),
                .foregroundColor: NSColor.black
            ]
            let stackName = NSAttributedString(string: cueStack.name, attributes: stackNameAttributes)
            let stackNameSize = stackName.size()
            let stackBlockHeight = stackNameSize.height + 16.0
            let stackY = placementStart(for: yPosition, blockHeight: stackBlockHeight)
            
            if stackY + stackNameSize.height >= dirtyRect.minY {
                stackName.draw(at: NSPoint(x: Self.sideMargin, y: stackY))
            }
            
            yPosition = stackY + stackBlockHeight
            
            if useColumnLayout {
                drawColumnLayout(stackIndex: stackIndex,
                                 cueStack: cueStack,
                                 startY: yPosition,
                                 width: contentWidth,
                                 dirtyRect: dirtyRect,
                                 yPos: &yPosition,
                                 highlightColors: highlightColors)
            } else {
                drawCompactLayout(cueStack: cueStack,
                                  startY: yPosition,
                                  width: contentWidth,
                                  dirtyRect: dirtyRect,
                                  yPos: &yPosition,
                                  highlightColors: highlightColors)
            }
            
            // Draw divider line if visible
            let dividerBlockHeight: CGFloat = 30.0
            let dividerY = placementStart(for: yPosition, blockHeight: dividerBlockHeight)
            if dividerY >= dirtyRect.minY && dividerY <= dirtyRect.maxY {
                context.setStrokeColor(NSColor.lightGray.cgColor)
                context.move(to: CGPoint(x: Self.sideMargin, y: dividerY))
                context.addLine(to: CGPoint(x: bounds.width - Self.sideMargin, y: dividerY))
                context.strokePath()
            }
            
            yPosition = dividerY + dividerBlockHeight
        }
        
        drawPageDecorations(in: dirtyRect)
    }
    
    private func drawPageDecorations(in dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let slice = pageSliceHeight
        let totalPages = numberOfPages
        
        for page in 1...totalPages {
            let pageIndex = page - 1
            let pageStart = pageSliceStart(for: pageIndex)
            let pageBottom = pageStart + slice
            guard dirtyRect.maxY >= pageStart && dirtyRect.minY <= pageBottom else { continue }
            
            // Safe print margins — paint over any content that bled into margin bands.
            context.setFillColor(NSColor.white.cgColor)
            context.fill(NSRect(x: 0, y: pageStart, width: bounds.width, height: Self.topMargin))
            context.fill(NSRect(x: 0, y: pageStart, width: Self.sideMargin, height: slice))
            context.fill(NSRect(x: bounds.width - Self.sideMargin, y: pageStart, width: Self.sideMargin, height: slice))
            
            let footerTop = pageBottom - Self.pageFooterReserve
            context.fill(NSRect(x: 0, y: footerTop, width: bounds.width, height: Self.pageFooterReserve))

            if page == 1 && showPrintDateTime {
                let formatter = Self.printDateFormatter
                let dateText = "Printed \(formatter.string(from: printDateTime))"
                let dateAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: max(9, fontSize - 2)),
                    .foregroundColor: NSColor.gray
                ]
                let dateLabel = NSAttributedString(string: dateText, attributes: dateAttributes)
                let dateSize = dateLabel.size()
                let dateX = bounds.width - Self.sideMargin - dateSize.width
                let dateY = pageStart + 8
                dateLabel.draw(in: NSRect(x: dateX, y: dateY, width: dateSize.width, height: dateSize.height))
            }

            if showPageNumbers {
                let text = "Page \(page) of \(totalPages)"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: max(9, fontSize - 2)),
                    .foregroundColor: NSColor.gray
                ]
                let label = NSAttributedString(string: text, attributes: attributes)
                let size = label.size()
                let x = (bounds.width - size.width) / 2
                let y = footerTop + Self.pageNumberTopPaddingInFooter
                label.draw(in: NSRect(x: x, y: y, width: size.width, height: size.height))
            }
        }
    }

    private static let printDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private func drawColumnLayout(stackIndex: Int,
                                  cueStack: CueStack,
                                  startY: CGFloat,
                                  width: CGFloat,
                                  dirtyRect: NSRect,
                                  yPos: inout CGFloat,
                                  highlightColors: [HighlightColorSetting]) {
        guard !cueStack.columns.isEmpty else { return }
        
        let contentX: CGFloat = Self.sideMargin
        var currentY = startY
        let includeTimeColumn = showTimeColumns[stackIndex] ?? true
        
        // Get the calculated column widths for this stack
        let columnWidths = columnWidthCache[stackIndex] ??
            Array(repeating: (width - (includeTimeColumn ? 75.0 : 0.0)) / CGFloat(cueStack.columns.count),
                  count: cueStack.columns.count)
        
        // Calculate column positions (where each column starts)
        var columnPositions: [CGFloat] = [contentX]
        var runningX: CGFloat = contentX
        for colWidth in columnWidths {
            runningX += colWidth
            columnPositions.append(runningX)
        }

        let timeColumnWidth = includeTimeColumn ? self.timeColumnWidth : 0
        let timeX = contentX + width - timeColumnWidth
        
        let baseRowHeight: CGFloat = fontSize * 1.5 + 8.0
        
        // Header row
        if showHeaders {
            let headerBlockHeight = baseRowHeight + 4.0
            let headerY = placementStart(for: currentY, blockHeight: headerBlockHeight)
            if headerY + baseRowHeight >= dirtyRect.minY && headerY <= dirtyRect.maxY {
                let headerBackground = NSRect(x: contentX, y: headerY, width: width, height: baseRowHeight)
                NSColor.lightGray.withAlphaComponent(0.2).setFill()
                // Check if context exists before drawing using NSBezierPath
                if NSGraphicsContext.current != nil {
                    NSBezierPath(roundedRect: headerBackground, xRadius: 4.0, yRadius: 4.0).fill()
                } else {
                    NSLog("Skipping header background fill due to nil graphics context.")
                }
                
                for colIndex in 0..<cueStack.columns.count {
                    let headerName = cueStack.columns[colIndex].name
                    let colX = columnPositions[colIndex]
                    let colWidth = columnWidths[colIndex]
                    
                    let headerAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.boldSystemFont(ofSize: fontSize),
                        .foregroundColor: NSColor.black,
                        .paragraphStyle: getParagraphStyle(for: colWidth - 16.0)
                    ]
                    
                    let headerText = NSAttributedString(string: headerName, attributes: headerAttributes)
                    headerText.draw(at: NSPoint(x: colX + 8.0, y: headerY + (baseRowHeight - headerText.size().height) / 2))
                }
                
                // Time column header (if showing time)
                if includeTimeColumn {
                    let timeHeaderAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.boldSystemFont(ofSize: fontSize),
                        .foregroundColor: NSColor.black
                    ]
                    
                    let timeHeader = NSAttributedString(string: "Time", attributes: timeHeaderAttributes)
                    let timeTextSize = timeHeader.size()
                    timeHeader.draw(at: NSPoint(x: timeX + (timeColumnWidth - timeTextSize.width) - 4.0,
                                                  y: headerY + (baseRowHeight - timeTextSize.height) / 2))
                }
            }
            
            currentY = headerY + headerBlockHeight
        }
        
        // Draw each cue row
        for cueIndex in 0..<cueStack.cues.count {
            let cue = cueStack.cues[cueIndex]
            let maxRowHeight = measuredRowHeight(stackIndex: stackIndex, cueIndex: cueIndex)
            let rowY = placementStart(for: currentY, blockHeight: maxRowHeight)
            
            // Skip drawing if this row is completely outside the dirty rect
            if rowY + maxRowHeight < dirtyRect.minY || rowY > dirtyRect.maxY {
                currentY = rowY + maxRowHeight
                continue
            }
            
            // Draw alternating row background
            if cueIndex % 2 != 0 {
                let rowBackground = NSRect(x: contentX, y: rowY, width: width, height: maxRowHeight)
                NSColor.lightGray.withAlphaComponent(0.05).setFill()
                if NSGraphicsContext.current != nil {
                    NSBezierPath(roundedRect: rowBackground, xRadius: 2.0, yRadius: 2.0).fill()
                } else {
                    NSLog("Skipping row background fill due to nil graphics context.")
                }
            }
            
            // Draw each column's text with proper wrapping
            for colIndex in 0..<min(cueStack.columns.count, cue.values.count) {
                let value = cue.values[colIndex]
                let colX = columnPositions[colIndex]
                let colWidth = columnWidths[colIndex]
                
                let valueColor: NSColor
                if cue.isStruckThrough {
                    valueColor = NSColor.gray
                } else if useColors {
                    // Use the actual highlight color system from settings
                    valueColor = getHighlightColorForCue(cue, highlightColors: highlightColors)
                } else {
                    valueColor = NSColor.black
                }
                
                // Use different paragraph styles based on column type
                let paragraphStyle: NSParagraphStyle
                if colIndex == 1 {
                    // Description column - use wrapping
                    paragraphStyle = getWrappingParagraphStyle(for: colWidth - 16.0)
                } else {
                    // All other columns - use truncation for single-line display
                    paragraphStyle = getParagraphStyle(for: colWidth - 16.0)
                }
                
                let valueAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: valueColor,
                    .strikethroughStyle: cue.isStruckThrough ? NSUnderlineStyle.single.rawValue : 0,
                    .paragraphStyle: paragraphStyle
                ]
                
                let valueText = NSAttributedString(string: value, attributes: valueAttributes)
                
                if colIndex == 1 {
                    // Description column - draw with wrapping
                    let textRect = valueText.boundingRect(with: NSSize(width: colWidth - 16.0, height: 1000), 
                                                         options: [.usesLineFragmentOrigin])
                    
                    if rowY + textRect.height >= dirtyRect.minY && rowY <= dirtyRect.maxY {
                        valueText.draw(in: NSRect(x: colX + 8.0, y: rowY + (maxRowHeight - textRect.height) / 2,
                                                width: colWidth - 16.0, height: textRect.height))
                    }
                } else {
                    // All other columns - draw single line with truncation
                    if rowY + fontSize * 1.5 >= dirtyRect.minY && rowY <= dirtyRect.maxY {
                        valueText.draw(at: NSPoint(x: colX + 8.0, y: rowY + (maxRowHeight - fontSize * 1.5) / 2))
                    }
                }
            }
            
            // Draw timer value (if showing time)
            if includeTimeColumn {
                let timeAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor.black
                ]
                
                let timeValue = NSAttributedString(string: cue.timerValue, attributes: timeAttributes)
                let timeSize = timeValue.size()
                timeValue.draw(at: NSPoint(x: timeX + (timeColumnWidth - timeSize.width) - 4.0,
                                            y: rowY + (maxRowHeight - timeSize.height) / 2))
            }
            
            currentY = rowY + maxRowHeight
        }
        
        let trailingSpacer: CGFloat = 16.0
        let trailingY = placementStart(for: currentY, blockHeight: trailingSpacer)
        yPos = trailingY + trailingSpacer
    }
    
    private func drawCompactLayout(cueStack: CueStack,
                                   startY: CGFloat,
                                   width: CGFloat,
                                   dirtyRect: NSRect,
                                   yPos: inout CGFloat,
                                   highlightColors: [HighlightColorSetting]) {
        let contentX: CGFloat = Self.sideMargin
        var currentY = startY
        let includeTimeColumn = showTimeColumns[cueStacks.firstIndex(where: { $0.name == cueStack.name }) ?? 0] ?? true
        
        for cueIndex in 0..<cueStack.cues.count {
            let cue = cueStack.cues[cueIndex]
            let rowStartY = currentY
            
            let cueHeaderAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: NSColor.black
            ]
            let cueHeaderText = NSAttributedString(string: "Cue \(cueIndex + 1)", attributes: cueHeaderAttributes)
            let cueHeaderSize = cueHeaderText.size()
            
            if currentY + cueHeaderSize.height >= dirtyRect.minY && currentY <= dirtyRect.maxY {
                cueHeaderText.draw(at: NSPoint(x: contentX, y: currentY))
                if includeTimeColumn && !cue.timerValue.isEmpty {
                    let timeAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: fontSize),
                        .foregroundColor: NSColor.black
                    ]
                    let timeText = NSAttributedString(string: "Time: \(cue.timerValue)", attributes: timeAttributes)
                    let timeSize = timeText.size()
                    timeText.draw(at: NSPoint(x: contentX + width - timeSize.width - 8.0, y: currentY))
                }
            }
            
            currentY += cueHeaderSize.height + 8.0
            
            for colIndex in 0..<min(cueStack.columns.count, cue.values.count) {
                if !cue.values[colIndex].isEmpty {
                    if showHeaders {
                        let headerAttributes: [NSAttributedString.Key: Any] = [
                            .font: NSFont.boldSystemFont(ofSize: fontSize - 1),
                            .foregroundColor: NSColor.darkGray
                        ]
                        let headerName = cueStack.columns[colIndex].name + ":"
                        let headerText = NSAttributedString(string: headerName, attributes: headerAttributes)
                        let headerSize = headerText.size()
                        
                        if currentY + headerSize.height >= dirtyRect.minY && currentY <= dirtyRect.maxY {
                            headerText.draw(at: NSPoint(x: contentX + 12.0, y: currentY))
                        }
                        
                        currentY += headerSize.height + 4.0
                    }
                    
                    let valueColor: NSColor
                    if cue.isStruckThrough {
                        valueColor = NSColor.gray
                    } else if useColors {
                        // Use the actual highlight color system from settings
                        valueColor = getHighlightColorForCue(cue, highlightColors: highlightColors)
                    } else {
                        valueColor = NSColor.black
                    }
                    
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.lineBreakMode = .byWordWrapping
                    
                    let valueAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: fontSize),
                        .foregroundColor: valueColor,
                        .strikethroughStyle: cue.isStruckThrough ? NSUnderlineStyle.single.rawValue : 0,
                        .paragraphStyle: paragraphStyle
                    ]
                    
                    let valueText = NSAttributedString(string: cue.values[colIndex], attributes: valueAttributes)
                    let maxSize = NSSize(width: width - contentX - 32.0, height: 1000)
                    let textRect = valueText.boundingRect(with: maxSize, options: [.usesLineFragmentOrigin])
                    
                    if currentY + textRect.height >= dirtyRect.minY && currentY <= dirtyRect.maxY {
                        valueText.draw(in: NSRect(x: contentX + 24.0, y: currentY, width: maxSize.width, height: textRect.height))
                    }
                    
                    currentY += textRect.height + 8.0
                }
            }
            
            if cueIndex % 2 != 0 {
                let rowHeight = currentY - rowStartY
                if (rowStartY + rowHeight >= dirtyRect.minY) && (rowStartY <= dirtyRect.maxY) {
                    let rowBackground = NSRect(x: contentX - 8.0, y: rowStartY - 4.0, width: width + 16.0, height: rowHeight + 8.0)
                    NSColor.lightGray.withAlphaComponent(0.05).setFill()
                    if NSGraphicsContext.current != nil {
                        NSBezierPath(roundedRect: rowBackground, xRadius: 4.0, yRadius: 4.0).fill()
                    } else {
                        NSLog("Skipping compact row background fill due to nil graphics context.")
                    }
                }
            }
            
            currentY += 8.0
        }
        
        currentY += 8.0
        yPos = currentY
    }
    
    /// Creates and returns a paragraph style with truncation enabled.
    private func getParagraphStyle(for width: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = .left
        style.allowsDefaultTighteningForTruncation = true
        return style
    }
    
    /// Creates and returns a paragraph style with word wrapping enabled.
    private func getWrappingParagraphStyle(for width: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.alignment = .left
        style.allowsDefaultTighteningForTruncation = true
        return style
    }
    
    /// Gets the highlight color for a cue based on the highlight color settings.
    private func getHighlightColorForCue(_ cue: Cue, highlightColors: [HighlightColorSetting]) -> NSColor {
        // Check each highlight color setting
        for highlight in highlightColors {
            // Check if any value in the cue contains the keyword
            for value in cue.values {
                if value.lowercased().contains(highlight.keyword.lowercased()) {
                    // Convert SwiftUI Color to NSColor
                    return NSColor(highlight.color)
                }
            }
        }
        // Return black if no highlight matches
        return NSColor.black
    }
}
