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
        
        let contentWidth = bounds.width - 72 // 36pt margin on each side
        var yPosition: CGFloat = 36.0 // Start 36pt from top
        
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
            
            if yPosition + stackNameSize.height >= dirtyRect.minY {
                stackName.draw(at: NSPoint(x: 36.0, y: yPosition))
            }
            
            yPosition += stackNameSize.height + 16.0
            
            if useColumnLayout {
                drawColumnLayout(stackIndex: stackIndex,
                                 cueStack: cueStack,
                                 startY: yPosition,
                                 width: contentWidth,
                                 dirtyRect: dirtyRect,
                                 yPos: &yPosition)
            } else {
                drawCompactLayout(cueStack: cueStack,
                                  startY: yPosition,
                                  width: contentWidth,
                                  dirtyRect: dirtyRect,
                                  yPos: &yPosition)
            }
            
            // Draw divider line if visible
            if yPosition >= dirtyRect.minY && yPosition <= dirtyRect.maxY {
                context.setStrokeColor(NSColor.lightGray.cgColor)
                context.move(to: CGPoint(x: 36.0, y: yPosition))
                context.addLine(to: CGPoint(x: bounds.width - 36.0, y: yPosition))
                context.strokePath()
            }
            
            yPosition += 30.0 // Space between stacks
        }
    }
    
    private func drawColumnLayout(stackIndex: Int,
                                  cueStack: CueStack,
                                  startY: CGFloat,
                                  width: CGFloat,
                                  dirtyRect: NSRect,
                                  yPos: inout CGFloat) {
        guard !cueStack.columns.isEmpty else { return }
        
        let contentX: CGFloat = 36.0 // Left margin
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
        
        let rowHeight: CGFloat = fontSize * 1.5 + 8.0
        
        // Header row
        if showHeaders {
            if currentY + rowHeight >= dirtyRect.minY && currentY <= dirtyRect.maxY {
                let headerBackground = NSRect(x: contentX, y: currentY, width: width, height: rowHeight)
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
                    
                    let headerAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.boldSystemFont(ofSize: fontSize),
                        .foregroundColor: NSColor.black
                    ]
                    
                    let headerText = NSAttributedString(string: headerName, attributes: headerAttributes)
                    headerText.draw(at: NSPoint(x: colX + 8.0, y: currentY + (rowHeight - headerText.size().height) / 2))
                }
                
                // Time column header (if showing time)
                if includeTimeColumn {
                    let timeX = columnPositions.last ?? (contentX + width - 75.0)
                    let timeHeaderAttributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.boldSystemFont(ofSize: fontSize),
                        .foregroundColor: NSColor.black
                    ]
                    
                    let timeHeader = NSAttributedString(string: "Time", attributes: timeHeaderAttributes)
                    let timeTextSize = timeHeader.size()
                    timeHeader.draw(at: NSPoint(x: timeX + (75.0 - timeTextSize.width) - 4.0,
                                                  y: currentY + (rowHeight - timeTextSize.height) / 2))
                }
            }
            
            currentY += rowHeight + 4.0 // Move below header
        }
        
        // Draw each cue row
        for cueIndex in 0..<cueStack.cues.count {
            if currentY + rowHeight < dirtyRect.minY || currentY > dirtyRect.maxY {
                currentY += rowHeight
                continue
            }
            
            let cue = cueStack.cues[cueIndex]
            
            if cueIndex % 2 != 0 {
                let rowBackground = NSRect(x: contentX, y: currentY, width: width, height: rowHeight)
                NSColor.lightGray.withAlphaComponent(0.05).setFill()
                if NSGraphicsContext.current != nil {
                    NSBezierPath(roundedRect: rowBackground, xRadius: 2.0, yRadius: 2.0).fill()
                } else {
                    NSLog("Skipping row background fill due to nil graphics context.")
                }
            }
            
            for colIndex in 0..<min(cueStack.columns.count, cue.values.count) {
                let value = cue.values[colIndex]
                let colX = columnPositions[colIndex]
                let colWidth = columnWidths[colIndex]
                
                let valueColor: NSColor
                if cue.isStruckThrough {
                    valueColor = NSColor.gray
                } else if useColors {
                    if value.lowercased().contains("warning") {
                        valueColor = NSColor.red
                    } else if value.lowercased().contains("note") {
                        valueColor = NSColor.blue
                    } else {
                        valueColor = NSColor.black
                    }
                } else {
                    valueColor = NSColor.black
                }
                
                let valueAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: valueColor,
                    .strikethroughStyle: cue.isStruckThrough ? NSUnderlineStyle.single.rawValue : 0,
                    .paragraphStyle: getParagraphStyle(for: colWidth - 16.0)
                ]
                
                let valueText = NSAttributedString(string: value, attributes: valueAttributes)
                valueText.draw(at: NSPoint(x: colX + 8.0, y: currentY + (rowHeight - valueText.size().height) / 2))
            }
            
            // Draw timer value (if showing time)
            if includeTimeColumn {
                let timeX = columnPositions.last ?? (contentX + width - 75.0)
                let timeAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor.black
                ]
                
                let timeValue = NSAttributedString(string: cue.timerValue, attributes: timeAttributes)
                let timeSize = timeValue.size()
                timeValue.draw(at: NSPoint(x: timeX + (75.0 - timeSize.width) - 4.0,
                                            y: currentY + (rowHeight - timeSize.height) / 2))
            }
            
            currentY += rowHeight
        }
        
        currentY += 16.0
        yPos = currentY
    }
    
    private func drawCompactLayout(cueStack: CueStack,
                                   startY: CGFloat,
                                   width: CGFloat,
                                   dirtyRect: NSRect,
                                   yPos: inout CGFloat) {
        let contentX: CGFloat = 36.0 // Left margin
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
                        if cue.values[colIndex].lowercased().contains("warning") {
                            valueColor = NSColor.red
                        } else if cue.values[colIndex].lowercased().contains("note") {
                            valueColor = NSColor.blue
                        } else {
                            valueColor = NSColor.black
                        }
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
}
