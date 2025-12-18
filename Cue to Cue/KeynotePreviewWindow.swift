//
//  KeynotePreviewWindow.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 9/1/24.
//

import SwiftUI
import PDFKit

struct KeynotePreviewWindow: View {
    @State private var document: PDFDocument?
    @State private var currentPage: Int = -1 // No page selected initially
    @State private var zoomFactor: CGFloat = 1.0
    @State private var fileName: String = ""
    @State private var lastModified: Date?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var notes: [Int: String] = [:] // Notes for each page

    var pdfURL: URL
    var onNotesUpdated: ([Int: String]) -> Void // Closure to update notes

    init(pdfURL: URL, initialNotes: [Int: String] = [:], onNotesUpdated: @escaping ([Int: String]) -> Void) {
        self.pdfURL = pdfURL
        self._document = State(initialValue: PDFDocument(url: pdfURL))
        self._fileName = State(initialValue: pdfURL.lastPathComponent)
        self._lastModified = State(initialValue: try? FileManager.default.attributesOfItem(atPath: pdfURL.path)[.modificationDate] as? Date)
        self._notes = State(initialValue: initialNotes)
        self.onNotesUpdated = onNotesUpdated
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                header
                Divider()
                content
                footer
            }
            .frame(minWidth: 800, minHeight: 600)
            .navigationTitle("Keynote Preview")
            .onDisappear {
                saveNotes()
            }
            .onAppear {
                // Ensure that document loading and UI updates occur on the main thread
                DispatchQueue.main.async {
                    loadDocument()
                }
            }
            // Overlay the page number when a page is selected
            if currentPage >= 0, let document = document {
                Text("Page \(currentPage + 1) of \(document.pageCount)")
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding()
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: {
                printDocument()
            }) {
                Image(systemName: "printer")
                    .padding()
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(fileName)
                    .font(.headline)
                if let lastModified = lastModified {
                    Text("Last modified: \(lastModified, formatter: dateFormatter)")
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.2))
    }

    private var content: some View {
        Group {
            if isLoading {
                ProgressView("Loading PDF...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let document = document {
                GeometryReader { geometry in
                    ScrollView {
                        PDFPageGridView(document: document, notes: $notes, zoomFactor: $zoomFactor, currentPage: $currentPage, viewWidth: geometry.size.width)
                    }
                }
            } else {
                Text("No document loaded")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var footer: some View {
        HStack {
            ZoomControl(zoomFactor: $zoomFactor)
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.2))
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    // Save notes when the window is closed
    private func saveNotes() {
        onNotesUpdated(notes)
    }

    // Load the PDF document with error handling
    private func loadDocument() {
        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            if let pdfDocument = PDFDocument(url: pdfURL) {
                DispatchQueue.main.async {
                    self.document = pdfDocument
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load PDF document."
                    self.isLoading = false
                }
            }
        }
    }

    // Updated print functionality to handle pagination
    private func printDocument() {
        guard let originalDocument = document else { return }

        // Create a new PDF document to hold the slides and notes
        let newPDFDocument = PDFDocument()

        // Iterate through each page in the original document
        for pageIndex in 0..<originalDocument.pageCount {
            guard let originalPage = originalDocument.page(at: pageIndex) else { continue }

            // Create a new PDF page with the same size as the original
            let pageBounds = originalPage.bounds(for: .mediaBox)
            let slideHeight = pageBounds.height

            // Prepare to calculate note height
            var noteHeight: CGFloat = 0
            let maxNoteWidth = pageBounds.width - 40

            if let note = notes[pageIndex], !note.isEmpty {
                let noteAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12)
                ]

                let attributedNote = NSAttributedString(string: note, attributes: noteAttributes)
                let noteBoundingRect = attributedNote.boundingRect(with: NSSize(width: maxNoteWidth, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
                noteHeight = noteBoundingRect.height + 20 // Add some padding
            }

            // Calculate combined page size
            let combinedPageHeight = slideHeight + noteHeight

            // Create an image representation with combined height
            guard let imageRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(pageBounds.width),
                pixelsHigh: Int(combinedPageHeight),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { continue }

            // Begin graphics context to draw
            NSGraphicsContext.saveGraphicsState()
            guard let context = NSGraphicsContext(bitmapImageRep: imageRep) else {
                NSGraphicsContext.restoreGraphicsState()
                continue
            }
            NSGraphicsContext.current = context

            // Set the background color to white
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: pageBounds.width, height: combinedPageHeight).fill()

            // Draw the original page image
            if let pageImage = originalPage.asImage(size: pageBounds.size) {
                pageImage.draw(in: CGRect(x: 0, y: noteHeight, width: pageBounds.width, height: slideHeight), from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
            }

            // Draw the note below the slide
            if let note = notes[pageIndex], !note.isEmpty {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .left

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12),
                    .paragraphStyle: paragraphStyle
                ]

                // Define the note's drawing rect
                let noteRect = CGRect(x: 20, y: 10, width: maxNoteWidth, height: noteHeight - 20) // Subtract padding from height

                // Draw the note
                note.draw(in: noteRect, withAttributes: attributes)
            }

            // End graphics context
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()

            // Create an NSImage from the bitmap
            let combinedImage = NSImage(size: NSSize(width: pageBounds.width, height: combinedPageHeight))
            combinedImage.addRepresentation(imageRep)

            // Set the combined image as the page content
            if let pdfPage = PDFPage(image: combinedImage) {
                newPDFDocument.insert(pdfPage, at: newPDFDocument.pageCount)
            }
        }

        // Ensure the new PDF document has pages
        guard newPDFDocument.pageCount > 0 else {
            print("No pages to print.")
            return
        }

        // Create a PDFView to display the new document
        let pdfView = PDFView()
        pdfView.document = newPDFDocument
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = false

        // Configure the print operation
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.topMargin = 20
        printInfo.bottomMargin = 20
        printInfo.leftMargin = 20
        printInfo.rightMargin = 20
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        printInfo.paperSize = NSMakeSize(612, 792) // 8.5 x 11 inches in points
        printInfo.scalingFactor = 1.0

        // Set the frame of pdfView appropriately
        let pageWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let pageHeight = printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin
        let totalHeight = pageHeight * CGFloat(newPDFDocument.pageCount)
        pdfView.frame = NSRect(x: 0, y: 0, width: pageWidth, height: totalHeight)
        pdfView.layoutSubtreeIfNeeded()

        // Perform the print operation on the main thread
        DispatchQueue.main.async {
            let printOperation = NSPrintOperation(view: pdfView, printInfo: printInfo)
            printOperation.showsPrintPanel = true
            printOperation.showsProgressPanel = true

            // Run the print operation
            printOperation.run()
        }
    }
}

// MARK: - Supporting Views and Extensions

struct PDFPageGridView: View {
    let document: PDFDocument
    @Binding var notes: [Int: String] // Binding to notes for each page
    @Binding var zoomFactor: CGFloat
    @Binding var currentPage: Int
    let viewWidth: CGFloat

    private let minItemWidth: CGFloat = 200
    private let itemSpacing: CGFloat = 20

    private var columns: [GridItem] {
        let itemWidth = minItemWidth * zoomFactor
        let totalSpacing = itemSpacing * 2 // Left and right padding
        let availableWidth = viewWidth - totalSpacing
        let columnCount = max(1, Int(availableWidth / (itemWidth + itemSpacing)))
        return Array(repeating: GridItem(.flexible(), spacing: itemSpacing), count: columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: itemSpacing) {
            ForEach(0..<document.pageCount, id: \.self) { index in
                if let page = document.page(at: index) {
                    VStack {
                        let aspectRatio = page.bounds(for: .cropBox).size.width / page.bounds(for: .cropBox).size.height
                        PDFPageView(page: page)
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .frame(width: minItemWidth * zoomFactor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(currentPage == index ? Color.blue : Color.clear, lineWidth: 2)
                            )
                            .overlay(
                                Group {
                                    if currentPage == index {
                                        VStack {
                                            Spacer()
                                            HStack {
                                                Spacer()
                                                Text("Page \(index + 1)")
                                                    .font(.caption)
                                                    .padding(4)
                                                    .background(Color.black.opacity(0.5))
                                                    .foregroundColor(.white)
                                                    .cornerRadius(4)
                                            }
                                        }
                                        .padding(4)
                                    }
                                }
                            )
                            .onTapGesture {
                                currentPage = index
                            }
                        TextEditor(text: Binding(
                            get: { notes[index, default: ""] },
                            set: { notes[index] = $0 }
                        ))
                        .frame(height: 60)
                        .padding(5)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(5)
                    }
                    .padding(.bottom, itemSpacing)
                }
            }
        }
        .padding(itemSpacing)
    }
}

struct PDFPageView: NSViewRepresentable {
    let page: PDFPage

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()

        let pdfView = PDFView()
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        let singlePageDocument = PDFDocument()
        singlePageDocument.insert(page, at: 0)
        pdfView.document = singlePageDocument
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayBox = .cropBox

        containerView.addSubview(pdfView)

        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: containerView.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        // Add an overlay view to intercept mouse events
        let overlayView = NonInteractiveView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(overlayView)

        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No updates needed for static page view
    }

    class NonInteractiveView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            // Return self to intercept events, or nil to pass them through
            return self
        }

        override func mouseDown(with event: NSEvent) {
            // Do nothing to prevent interaction
        }

        override func mouseUp(with event: NSEvent) {
            // Do nothing
        }

        override func mouseDragged(with event: NSEvent) {
            // Do nothing
        }

        override func rightMouseDown(with event: NSEvent) {
            // Do nothing
        }

        override func otherMouseDown(with event: NSEvent) {
            // Do nothing
        }
    }
}

struct ZoomControl: View {
    @Binding var zoomFactor: CGFloat

    var body: some View {
        HStack {
            Button(action: { zoomFactor = max(0.5, zoomFactor - 0.1) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            Slider(value: $zoomFactor, in: 0.5...2.0, step: 0.1)
                .frame(width: 100)
            Button(action: { zoomFactor = min(2.0, zoomFactor + 0.1) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            Text(String(format: "%.0f%%", zoomFactor * 100))
        }
    }
}

// Extension to render PDFPage as NSImage using proper context handling
extension PDFPage {
    func asImage(size: CGSize?) -> NSImage? {
        let pageBounds = self.bounds(for: .mediaBox)
        let imageSize = size ?? pageBounds.size

        let image = NSImage(size: imageSize)
        image.lockFocus()

        // Set the background color to white
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height).fill()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }

        context.saveGState()

        // **Remove the flip transformation**
        // context.translateBy(x: 0, y: imageSize.height)
        // context.scaleBy(x: 1.0, y: -1.0)

        // **Apply scaling to fit the page within the image size**
        let scaleX = imageSize.width / pageBounds.width
        let scaleY = imageSize.height / pageBounds.height
        context.scaleBy(x: scaleX, y: scaleY)

        // **Draw the PDF page without flipping**
        self.draw(with: .mediaBox, to: context)

        context.restoreGState()
        image.unlockFocus()

        return image
    }
}
