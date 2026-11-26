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
    var showPrintDateTime: Bool
    var useColumnLayout: Bool
    var showTimeColumns: [Int: Bool]
    var contentHeight: CGFloat = 0
    var useLandscape: Bool
    var contentWidth: CGFloat = 612 // Default width for portrait
    var highlightColors: [HighlightColorSetting] = []
    var printDateTime: Date = Date()
    private var baseContentHeight: CGFloat = 0
    
    // Changed from private to internal so the extension can access these properties.
    var columnWidthCache: [Int: [CGFloat]] = [:] // [stackIndex: [columnWidths]]
    var longestTextCache: [Int: [CGFloat]] = [:] // [stackIndex: [longestTextWidths]]
    var timeColumnWidth: CGFloat = 75.0 // Fixed width for time column
    
    init(cueStacks: [CueStack],
         fontSize: CGFloat,
         useColors: Bool,
         showHeaders: Bool,
         showPageNumbers: Bool,
         showPrintDateTime: Bool = true,
         printDateTime: Date = Date(),
         useColumnLayout: Bool,
         showTimeColumns: [Int: Bool],
         useLandscape: Bool = false,
         highlightColors: [HighlightColorSetting] = []) {
        self.cueStacks = cueStacks
        self.fontSize = fontSize
        self.useColors = useColors
        self.showHeaders = showHeaders
        self.showPageNumbers = showPageNumbers
        self.showPrintDateTime = showPrintDateTime
        self.printDateTime = printDateTime
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
            let availableWidth = bounds.width - (Self.sideMargin * 2) - (includeTimeColumn ? timeColumnWidth : 0)
            
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
                let minDescriptionWidth: CGFloat = 80
                let currentDescriptionWidth = columnWidths[1]
                let maxReduction = currentDescriptionWidth - minDescriptionWidth
                
                if maxReduction > 0 {
                    let reduction = min(maxReduction, excessWidth)
                    columnWidths[1] -= reduction
                }
            }
        }

        // Step 5: If non-description columns alone exceed the page, scale all columns to fit.
        var fittedTotal = columnWidths.reduce(0, +)
        if fittedTotal > availableWidth, fittedTotal > 0 {
            let scale = availableWidth / fittedTotal
            for index in 0..<columnCount {
                let floor: CGFloat = index == 1 ? 80 : 36
                columnWidths[index] = max(columnWidths[index] * scale, floor)
            }

            fittedTotal = columnWidths.reduce(0, +)
            if fittedTotal > availableWidth, columnCount > 1 {
                columnWidths[1] = max(80, columnWidths[1] - (fittedTotal - availableWidth))
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
        if useColumnLayout {
            let blocks = columnLayoutBlockHeights()
            let total = blocks.reduce(0, +)
            contentHeight = Self.topMargin + total + Self.pageFooterReserve
            baseContentHeight = contentHeight
            return
        }

        var yPos: CGFloat = Self.topMargin
        
        for stackIndex in 0..<cueStacks.count {
            let cueStack = cueStacks[stackIndex]
            
            // Stack name height
            let stackNameAttr = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: fontSize + 4)]
            let stackNameSize = (cueStack.name as NSString).size(withAttributes: stackNameAttr)
            yPos += stackNameSize.height + 16
            
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
            
            yPos += 30 // Space between stacks
        }
        
        yPos += Self.pageFooterReserve
        contentHeight = yPos
        baseContentHeight = yPos
    }
    
    // MARK: - Paged display (preview + print)
    
    static let topMargin: CGFloat = 24
    static let sideMargin: CGFloat = 36
    /// Reserved footer band at the bottom of each page (page numbers only).
    static let pageFooterReserve: CGFloat = 36
    static let pageNumberTopPaddingInFooter: CGFloat = 10
    
    var pageSliceHeight: CGFloat {
        paperSize.height
    }
    
    var printableContentHeightPerPage: CGFloat {
        paperSize.height - Self.topMargin - Self.pageFooterReserve
    }
    
    func pageSliceStart(for pageIndex: Int) -> CGFloat {
        CGFloat(pageIndex) * pageSliceHeight
    }
    
    func contentTop(forPageIndex pageIndex: Int) -> CGFloat {
        pageSliceStart(for: pageIndex) + Self.topMargin
    }
    
    func contentBottom(forPageIndex pageIndex: Int) -> CGFloat {
        pageSliceStart(for: pageIndex) + pageSliceHeight - Self.pageFooterReserve
    }
    
    var paperSize: NSSize {
        useLandscape ? NSSize(width: 792, height: 612) : NSSize(width: 612, height: 792)
    }
    
    var numberOfPages: Int {
        max(1, Int(ceil(contentHeight / pageSliceHeight)))
    }
    
    /// Applies row-aware page breaks so on-screen preview matches print pagination.
    func prepareForPagedDisplay() {
        if baseContentHeight > 0 {
            contentHeight = baseContentHeight
        }
        frame = NSRect(x: 0, y: 0, width: paperSize.width, height: contentHeight)
        calculateColumnWidths()
        preprocessForPagination()
        frame = NSRect(x: 0, y: 0, width: paperSize.width, height: contentHeight)
    }

    var printableContentWidth: CGFloat {
        bounds.width - (Self.sideMargin * 2)
    }
    
    /// Row height matching drawColumnLayout — includes wrapped Description text.
    func measuredRowHeight(stackIndex: Int, cueIndex: Int) -> CGFloat {
        let baseRowHeight = fontSize * 1.5 + 8
        let cueStack = cueStacks[stackIndex]
        guard cueIndex < cueStack.cues.count else { return baseRowHeight }

        let cue = cueStack.cues[cueIndex]
        let columnWidths = columnWidthCache[stackIndex] ?? []
        var maxRowHeight = baseRowHeight

        for colIndex in 0..<min(cueStack.columns.count, cue.values.count, columnWidths.count) {
            let value = cue.values[colIndex]
            guard !value.isEmpty else { continue }

            let colWidth = columnWidths[colIndex]
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = colIndex == 1 ? .byWordWrapping : .byTruncatingTail

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .paragraphStyle: paragraphStyle
            ]
            let valueText = NSAttributedString(string: value, attributes: attributes)
            let measureWidth = colWidth - 16
            let textRect = valueText.boundingRect(
                with: NSSize(width: measureWidth, height: 10_000),
                options: [.usesLineFragmentOrigin]
            )
            let needed = colIndex == 1 ? textRect.height + 8 : baseRowHeight
            maxRowHeight = max(maxRowHeight, needed)
        }

        return maxRowHeight
    }

    private func columnLayoutBlockHeights() -> [CGFloat] {
        var blocks: [CGFloat] = []
        let headerRowHeight = fontSize * 1.5 + 8

        for stackIndex in 0..<cueStacks.count {
            let cueStack = cueStacks[stackIndex]

            let stackNameAttr = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: fontSize + 4)]
            let stackNameSize = (cueStack.name as NSString).size(withAttributes: stackNameAttr)
            blocks.append(stackNameSize.height + 16)

            if showHeaders && !cueStack.columns.isEmpty {
                blocks.append(headerRowHeight + 4)
            }

            for cueIndex in 0..<cueStack.cues.count {
                blocks.append(measuredRowHeight(stackIndex: stackIndex, cueIndex: cueIndex))
            }

            blocks.append(16)
            blocks.append(30)
        }

        return blocks
    }

    private func applyExcelStylePageBreaks() {
        let blocks = useColumnLayout ? columnLayoutBlockHeights() : compactLayoutBlockHeights()
        var y = Self.topMargin

        for blockHeight in blocks where blockHeight > 0 {
            let startY = placementStart(for: y, blockHeight: blockHeight)
            y = startY + blockHeight
        }

        contentHeight = y + Self.pageFooterReserve
        let pages = max(1, Int(ceil(contentHeight / pageSliceHeight)))
        contentHeight = CGFloat(pages) * pageSliceHeight
    }

    /// Excel-style placement: if a block won't fit on the current page, start it on the next page.
    func placementStart(for y: CGFloat, blockHeight: CGFloat) -> CGFloat {
        guard blockHeight > 0 else { return y }

        let slice = pageSliceHeight
        var pageIndex = max(0, Int(floor(y / slice)))
        var pageContentTop = contentTop(forPageIndex: pageIndex)
        var pageContentBottom = contentBottom(forPageIndex: pageIndex)
        let usableHeight = slice - Self.topMargin - Self.pageFooterReserve

        var adjustedY = y
        if adjustedY < pageContentTop - 0.5 {
            adjustedY = pageContentTop
        }

        if blockHeight > usableHeight {
            if adjustedY + blockHeight > pageContentBottom && adjustedY > pageContentTop - 0.5 {
                pageIndex += 1
                return contentTop(forPageIndex: pageIndex)
            }
            return max(adjustedY, pageContentTop)
        }

        if adjustedY + blockHeight > pageContentBottom && adjustedY > pageContentTop - 0.5 {
            pageIndex += 1
            return contentTop(forPageIndex: pageIndex)
        }

        return adjustedY
    }

    private func compactLayoutBlockHeights() -> [CGFloat] {
        var blocks: [CGFloat] = []

        for stackIndex in 0..<cueStacks.count {
            let cueStack = cueStacks[stackIndex]

            let stackNameAttr = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: fontSize + 4)]
            let stackNameSize = (cueStack.name as NSString).size(withAttributes: stackNameAttr)
            blocks.append(stackNameSize.height + 16)

            for cueIndex in 0..<cueStack.cues.count {
                let cue = cueStack.cues[cueIndex]
                var cueHeight: CGFloat = 0

                let headerAttr = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: fontSize)]
                cueHeight += ("Cue \(cueIndex + 1)" as NSString).size(withAttributes: headerAttr).height + 8

                for colIndex in 0..<min(cueStack.columns.count, cue.values.count) {
                    guard !cue.values[colIndex].isEmpty else { continue }
                    if showHeaders {
                        let colHeaderAttr = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: fontSize - 1)]
                        cueHeight += (cueStack.columns[colIndex].name as NSString)
                            .size(withAttributes: colHeaderAttr).height + 4
                    }
                    let valueAttr = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: fontSize)]
                    cueHeight += (cue.values[colIndex] as NSString).size(withAttributes: valueAttr).height + 8
                }

                cueHeight += 8
                blocks.append(cueHeight)
            }

            blocks.append(30)
        }

        return blocks
    }

    // MARK: - Pagination Methods
    
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        guard let printInfo = NSPrintOperation.current?.printInfo else {
            range.pointee = NSRange(location: 1, length: 1)
            return true
        }
        
        _ = printInfo
        
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
        
        if baseContentHeight > 0 {
            contentHeight = baseContentHeight
        }
        preprocessForPagination()
        calculateColumnWidths()
        frame = NSRect(x: 0, y: 0, width: paperSize.width, height: contentHeight)
        
        range.pointee = NSRange(location: 1, length: numberOfPages)
        return true
    }
    
    /// Pre-process the content layout to avoid splitting rows across pages (Excel-style).
    private func preprocessForPagination() {
        applyExcelStylePageBreaks()
    }
    override func rectForPage(_ page: Int) -> NSRect {
        let pageHeight = paperSize.height
        let pageOriginY = CGFloat(page - 1) * pageHeight
        
        return NSRect(
            x: 0,
            y: pageOriginY,
            width: bounds.width,
            height: pageHeight
        )
    }
}

extension CueStackPaginatedView {
    func configuredForPagedOutput() -> CueStackPaginatedView {
        prepareForPagedDisplay()
        return self
    }
}
