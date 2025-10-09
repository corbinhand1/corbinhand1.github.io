//
//  CuePrintView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 3/11/25.
//

import AppKit

class CueStackPaginatedView: NSView {
    var cueStacks: [CueStack]
    var fontSize: CGFloat
    var useColors: Bool
    var showHeaders: Bool
    var showPageNumbers: Bool
    var useColumnLayout: Bool
    var showTimeColumns: [Int: Bool]
    var contentHeight: CGFloat = 0
    var useLandscape: Bool
    var contentWidth: CGFloat = 612 // Default width for portrait
    var highlightColors: [HighlightColorSetting] = []
    
    // Changed from private to internal so the extension can access these properties.
    var columnWidthCache: [Int: [CGFloat]] = [:] // [stackIndex: [columnWidths]]
    var longestTextCache: [Int: [CGFloat]] = [:] // [stackIndex: [longestTextWidths]]
    var timeColumnWidth: CGFloat = 75.0 // Fixed width for time column
    
    init(cueStacks: [CueStack],
         fontSize: CGFloat,
         useColors: Bool,
         showHeaders: Bool,
         showPageNumbers: Bool,
         useColumnLayout: Bool,
         showTimeColumns: [Int: Bool],
         useLandscape: Bool = false,
         highlightColors: [HighlightColorSetting] = []) {
        self.cueStacks = cueStacks
        self.fontSize = fontSize
        self.useColors = useColors
        self.showHeaders = showHeaders
        self.showPageNumbers = showPageNumbers
        self.useColumnLayout = useColumnLayout
        self.showTimeColumns = showTimeColumns
        self.useLandscape = useLandscape
        self.highlightColors = highlightColors
        
        // Determine initial frame width based on orientation
        self.contentWidth = useLandscape ? 792 : 612 // 8.5" x 11" paper in points
        
        // Start with a standard frame
        super.init(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 10000))
        
        // Precalculate column widths for each stack
        calculateColumnWidths()
        
        // Calculate the content height by doing a dry-run of our layout
        calculateContentHeight()
        
        // Set the actual frame with the calculated height
        self.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var isFlipped: Bool {
        return true // Use a flipped coordinate system for easier layout
    }
    
    // MARK: - Layout & Calculation Methods
    
    private func shouldShowTimeColumn(for stackIndex: Int) -> Bool {
        return showTimeColumns[stackIndex] ?? true
    }
    
    /// Calculates the column widths for each cue stack with smart auto-adjustment and priority wrapping.
    func calculateColumnWidths() {
        for stackIndex in 0..<cueStacks.count {
            let cueStack = cueStacks[stackIndex]
            let includeTimeColumn = shouldShowTimeColumn(for: stackIndex)
            let availableWidth = bounds.width - 72 - (includeTimeColumn ? timeColumnWidth : 0) // Total width minus margins and time column
            
            // If there are no columns, skip calculation
            if cueStack.columns.isEmpty {
                columnWidthCache[stackIndex] = []
                continue
            }
            
            // Determine the longest text width for each column (header and content)
            var longestTextWidths: [CGFloat] = Array(repeating: 0, count: cueStack.columns.count)
            let textAttributes = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: fontSize)]
            
            // Check header text widths
            for (i, column) in cueStack.columns.enumerated() {
                let headerWidth = (column.name as NSString).size(withAttributes: textAttributes).width + 16
                longestTextWidths[i] = max(longestTextWidths[i], headerWidth)
            }
            
            // Check content text widths
            for cue in cueStack.cues {
                for i in 0..<min(cue.values.count, cueStack.columns.count) {
                    let contentWidth = (cue.values[i] as NSString).size(withAttributes: textAttributes).width + 16
                    longestTextWidths[i] = max(longestTextWidths[i], contentWidth)
                }
            }
            
            longestTextCache[stackIndex] = longestTextWidths
            
            // Smart column width calculation with priority wrapping
            let columnWidths = calculateSmartColumnWidths(
                cueStack: cueStack,
                longestTextWidths: longestTextWidths,
                availableWidth: availableWidth
            )
            
            columnWidthCache[stackIndex] = columnWidths
        }
    }
    
    /// Calculates smart column widths with single-line priority for all columns except Description.
    private func calculateSmartColumnWidths(cueStack: CueStack, longestTextWidths: [CGFloat], availableWidth: CGFloat) -> [CGFloat] {
        let columnCount = cueStack.columns.count
        var columnWidths: [CGFloat] = Array(repeating: 0, count: columnCount)
        
        // Step 1: Assign exact widths needed for single-line display to all columns except Description
        for i in 0..<columnCount {
            if i == 1 {
                // Description column - start with minimum width, will expand later
                columnWidths[i] = max(120, longestTextWidths[i])
            } else {
                // All other columns - give them exactly what they need for single line
                columnWidths[i] = longestTextWidths[i]
            }
        }
        
        // Step 2: Calculate remaining width after single-line assignments
        let usedWidth = columnWidths.reduce(0, +)
        let remainingWidth = max(0, availableWidth - usedWidth)
        
        // Step 3: Give ALL remaining width to Description column
        if remainingWidth > 0 && columnCount > 1 {
            columnWidths[1] += remainingWidth
        }
        
        // Step 4: If still too wide, only reduce Description column
        let totalWidth = columnWidths.reduce(0, +)
        if totalWidth > availableWidth {
            let excessWidth = totalWidth - availableWidth
            
            // Only reduce Description column - keep all other columns at their single-line width
            if columnCount > 1 {
                let minDescriptionWidth: CGFloat = 120
                let currentDescriptionWidth = columnWidths[1]
                let maxReduction = currentDescriptionWidth - minDescriptionWidth
                
                if maxReduction > 0 {
                    let reduction = min(maxReduction, excessWidth)
                    columnWidths[1] -= reduction
                }
            }
        }
        
        return columnWidths
    }
    
    /// Measures the required width for the time column based on its content.
    func calculateTimerColumnWidth() {
        let textAttributes = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: fontSize)]
        var maxWidth: CGFloat = 60 // Minimum width
        
        let headerWidth = ("Time" as NSString).size(withAttributes: textAttributes).width + 16
        maxWidth = max(maxWidth, headerWidth)
        
        for cueStack in cueStacks {
            for cue in cueStack.cues {
                let timerWidth = (cue.timerValue as NSString).size(withAttributes: textAttributes).width + 16
                maxWidth = max(maxWidth, timerWidth)
            }
        }
        
        timeColumnWidth = min(maxWidth, 120)
    }
    
    /// Calculates the total content height for the view based on its layout.
    func calculateContentHeight() {
        var yPos: CGFloat = 36 // Start margin
        
        for stackIndex in 0..<cueStacks.count {
            let cueStack = cueStacks[stackIndex]
            
            // Stack name height
            let stackNameAttr = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: fontSize + 4)]
            let stackNameSize = (cueStack.name as NSString).size(withAttributes: stackNameAttr)
            yPos += stackNameSize.height + 16
            
            if useColumnLayout {
                let rowHeight = fontSize * 1.5 + 8
                if showHeaders && !cueStack.columns.isEmpty {
                    yPos += rowHeight + 4
                }
                yPos += CGFloat(cueStack.cues.count) * rowHeight
                yPos += 16 // Extra space after rows
            } else {
                for cueIndex in 0..<cueStack.cues.count {
                    let cue = cueStack.cues[cueIndex]
                    
                    let headerAttr = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: fontSize)]
                    let headerSize = ("Cue \(cueIndex + 1)" as NSString).size(withAttributes: headerAttr)
                    yPos += headerSize.height + 8
                    
                    if shouldShowTimeColumn(for: stackIndex) && !cue.timerValue.isEmpty {
                        // Time is on the same line, no extra height needed
                    }
                    
                    for colIndex in 0..<min(cueStack.columns.count, cue.values.count) {
                        if !cue.values[colIndex].isEmpty {
                            if showHeaders {
                                let colHeaderAttr = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: fontSize - 1)]
                                let colHeaderSize = (cueStack.columns[colIndex].name as NSString).size(withAttributes: colHeaderAttr)
                                yPos += colHeaderSize.height + 4
                            }
                            let valueAttr = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: fontSize)]
                            let valueSize = (cue.values[colIndex] as NSString).size(withAttributes: valueAttr)
                            yPos += valueSize.height + 8
                        }
                    }
                    
                    yPos += 8 // Space between cues
                }
            }
            
            yPos += 30 // Space between stacks
        }
        
        yPos += 36 // Bottom margin
        contentHeight = yPos
    }
    
    // MARK: - Pagination Methods
    
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        guard let printInfo = NSPrintOperation.current?.printInfo else {
            range.pointee = NSRange(location: 1, length: 1)
            return true
        }
        
        let pageHeight = printInfo.paperSize.height - (printInfo.topMargin + printInfo.bottomMargin)
        
        // Adjust frame width based on orientation
        if printInfo.orientation == .landscape && !useLandscape {
            self.contentWidth = 792
            self.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
            calculateColumnWidths()
        } else if printInfo.orientation == .portrait && useLandscape {
            self.contentWidth = 612
            self.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
            calculateColumnWidths()
        }
        
        preprocessForPagination(pageHeight: pageHeight)
        
        let numberOfPages = Int(ceil(contentHeight / pageHeight))
        range.pointee = NSRange(location: 1, length: max(1, numberOfPages))
        return true
    }
    
    /// Pre-process the content layout to avoid splitting rows or cues across pages.
    private func preprocessForPagination(pageHeight: CGFloat) {
        var pageBreaks: [CGFloat] = []
        for i in 1...10 { // Support up to 10 pages
            pageBreaks.append(pageHeight * CGFloat(i))
        }
        
        if useColumnLayout {
            adjustColumnLayoutForPagination(pageBreaks: pageBreaks)
        } else {
            adjustCompactLayoutForPagination(pageBreaks: pageBreaks)
        }
    }
    
    private func adjustColumnLayoutForPagination(pageBreaks: [CGFloat]) {
        var yPosition: CGFloat = 36
        var rowPositions: [(start: CGFloat, height: CGFloat)] = []
        
        for stackIndex in 0..<cueStacks.count {
            let cueStack = cueStacks[stackIndex]
            
            // Stack header
            let stackHeaderStart = yPosition
            let stackNameAttr = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: fontSize + 4)]
            let stackNameSize = (cueStack.name as NSString).size(withAttributes: stackNameAttr)
            yPosition += stackNameSize.height + 16
            rowPositions.append((stackHeaderStart, yPosition - stackHeaderStart))
            
            if showHeaders && !cueStack.columns.isEmpty {
                let headerRowStart = yPosition
                let rowHeight = fontSize * 1.5 + 8
                yPosition += rowHeight + 4
                rowPositions.append((headerRowStart, yPosition - headerRowStart))
            }
            
            let rowHeight = fontSize * 1.5 + 8
            for _ in 0..<cueStack.cues.count {
                let rowStart = yPosition
                yPosition += rowHeight
                rowPositions.append((rowStart, rowHeight))
            }
            
            yPosition += 16 // After rows
            yPosition += 30 // Between stacks
        }
        
        var heightAdjustment: CGFloat = 0
        var adjustedContentHeight = contentHeight
        
        for pageBreak in pageBreaks {
            for (rowStart, rowHeight) in rowPositions {
                let adjustedRowStart = rowStart + heightAdjustment
                let rowEnd = adjustedRowStart + rowHeight
                
                if adjustedRowStart < pageBreak && rowEnd > pageBreak {
                    let spaceNeeded = pageBreak - adjustedRowStart
                    heightAdjustment += spaceNeeded
                    adjustedContentHeight += spaceNeeded
                    break
                }
            }
        }
        
        contentHeight = adjustedContentHeight
    }
    
    private func adjustCompactLayoutForPagination(pageBreaks: [CGFloat]) {
        var yPosition: CGFloat = 36
        var cuePositions: [(start: CGFloat, height: CGFloat)] = []
        
        for stackIndex in 0..<cueStacks.count {
            let cueStack = cueStacks[stackIndex]
            
            let stackHeaderStart = yPosition
            let stackNameAttr = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: fontSize + 4)]
            let stackNameSize = (cueStack.name as NSString).size(withAttributes: stackNameAttr)
            yPosition += stackNameSize.height + 16
            cuePositions.append((stackHeaderStart, yPosition - stackHeaderStart))
            
            for cueIndex in 0..<cueStack.cues.count {
                let cueStart = yPosition
                let cue = cueStack.cues[cueIndex]
                
                let headerAttr = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: fontSize)]
                let headerSize = ("Cue \(cueIndex + 1)" as NSString).size(withAttributes: headerAttr)
                yPosition += headerSize.height + 8
                
                for colIndex in 0..<min(cueStack.columns.count, cue.values.count) {
                    if !cue.values[colIndex].isEmpty {
                        if showHeaders {
                            let colHeaderAttr = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: fontSize - 1)]
                            let colHeaderSize = (cueStack.columns[colIndex].name as NSString).size(withAttributes: colHeaderAttr)
                            yPosition += colHeaderSize.height + 4
                        }
                        
                        let valueAttr = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: fontSize)]
                        let valueSize = (cue.values[colIndex] as NSString).size(withAttributes: valueAttr)
                        yPosition += valueSize.height + 8
                    }
                }
                
                yPosition += 8
                cuePositions.append((cueStart, yPosition - cueStart))
            }
            
            yPosition += 30
        }
        
        var heightAdjustment: CGFloat = 0
        var adjustedContentHeight = contentHeight
        
        for pageBreak in pageBreaks {
            for (cueStart, cueHeight) in cuePositions {
                let adjustedCueStart = cueStart + heightAdjustment
                let cueEnd = adjustedCueStart + cueHeight
                
                if adjustedCueStart < pageBreak && cueEnd > pageBreak {
                    let spaceNeeded = pageBreak - adjustedCueStart
                    heightAdjustment += spaceNeeded
                    adjustedContentHeight += spaceNeeded
                    break
                }
            }
        }
        
        contentHeight = adjustedContentHeight
    }
    
    override func rectForPage(_ page: Int) -> NSRect {
        guard let printInfo = NSPrintOperation.current?.printInfo else {
            return self.bounds
        }
        
        let pageHeight = printInfo.paperSize.height - (printInfo.topMargin + printInfo.bottomMargin)
        let pageOriginY = CGFloat(page - 1) * pageHeight
        
        let safetyMargin: CGFloat = 0.5
        return NSRect(
            x: 0,
            y: pageOriginY + safetyMargin,
            width: self.bounds.width,
            height: pageHeight - safetyMargin * 2
        )
    }
}
