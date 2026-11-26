//
//  DocumentControllerTests.swift
//  Cue to CueTests
//
//  Dirty tracking, naming, launch fallback and the quit check.
//
//  These tests deliberately avoid paths that write through DocumentStore
//  (save/open/new), because DocumentStore is a singleton that writes the
//  app's real "last document" bookmark and backup folders.
//

import XCTest
@testable import Cue_to_Cue

@MainActor
final class DocumentControllerTests: XCTestCase {

    private var data: DataSyncManager!
    private var editor: CueEditorController!
    private var document: DocumentController!

    override func setUp() async throws {
        data = DataSyncManager()
        editor = CueEditorController(data: data)
        document = DocumentController(data: data, editor: editor)
    }

    private func spinRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    // MARK: Dirty tracking

    func testStartsClean() {
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(document.fileName, "Untitled")
    }

    func testCueEditMarksDirty() {
        data.cueStacks = [CueStack(name: "A", cues: [], columns: [])]
        XCTAssertTrue(document.isDirty)
    }

    func testPlaylistEditMarksDirty() {
        var playlist = data.countdownPlaylist
        playlist.loopPlaylist.toggle()
        data.countdownPlaylist = playlist
        XCTAssertTrue(document.isDirty)
    }

    func testPDFNotesEditMarksDirty() {
        document.pdfNotes = ["deck.pdf": [1: "note"]]
        XCTAssertTrue(document.isDirty)
    }

    func testChangesWhileLoadingDoNotMarkDirty() {
        document.isLoadingFromDisk = true
        data.cueStacks = [CueStack(name: "Loaded", cues: [], columns: [])]
        document.pdfNotes = ["x": [:]]
        document.markDirty()
        XCTAssertFalse(document.isDirty)
    }

    // MARK: Naming

    func testFileStemStripsExtensions() {
        document.fileName = "Keynote.cuestack"
        XCTAssertEqual(document.fileStem, "Keynote")
        document.fileName = "Old Show.json"
        XCTAssertEqual(document.fileStem, "Old Show")
        document.fileName = "Untitled"
        XCTAssertEqual(document.fileStem, "Untitled")
    }

    // MARK: Launch fallback

    func testEnsureDocumentHasAStackInstallsBlankStackWithoutDirtying() {
        XCTAssertTrue(data.cueStacks.isEmpty)
        document.ensureDocumentHasAStack()
        spinRunLoop()
        XCTAssertEqual(data.cueStacks.count, 1)
        XCTAssertEqual(data.selectedCueStackIndex, 0)
        XCTAssertFalse(document.isDirty, "a blank starting stack is not an unsaved edit")
        XCTAssertFalse(document.isLoadingFromDisk)

        // ...and the editor's undo baseline is the blank stack.
        editor.addCue()
        editor.undo()
        XCTAssertEqual(data.cueStacks[0].cues.count, 0)
    }

    func testEnsureDocumentHasAStackLeavesExistingStacksAlone() {
        data.cueStacks = [CueStack(name: "Mine", cues: [], columns: [])]
        document.ensureDocumentHasAStack()
        XCTAssertEqual(data.cueStacks.map(\.name), ["Mine"])
    }

    // MARK: Quit

    func testQuitWhenCleanIsAllowedImmediately() {
        var answer: Bool?
        document.prepareForQuit { answer = $0 }
        XCTAssertEqual(answer, true)
    }

    func testAutosaveDoesNothingWhenClean() {
        document.autoSave()
        XCTAssertNil(document.lastSaveDate)
        XCTAssertNil(document.lastRecoveryURL)
    }
}

// MARK: - Loading another show, naming after an empty file

@MainActor
final class DocumentLoadingTests: XCTestCase {
    private func makeDocument() -> (DataSyncManager, DocumentController) {
        let data = DataSyncManager()
        let editor = CueEditorController(data: data)
        return (data, DocumentController(data: data, editor: editor))
    }

    private func show(_ stackCount: Int) -> SavedData {
        SavedData(cueStacks: (0..<stackCount).map { i in
            CueStack(name: "S\(i)", cues: (0..<5).map { Cue(values: ["\($0)"]) }, columns: [Column(name: "#", width: 40)])
        }, highlightColors: [])
    }

    func testOpeningADifferentShowStartsAtTheTop() {
        let (data, document) = makeDocument()
        data.cueStacks = show(4).cueStacks
        data.selectedCueStackIndex = 2
        data.selectedCueIndex = 3
        data.activeCueIndex = 3
        document.applyLoadedData(show(3), from: URL(fileURLWithPath: "/tmp/other-show.cuestack"), persistAsLastSavedURL: false)
        XCTAssertEqual(data.selectedCueStackIndex, 0)
        XCTAssertEqual(data.selectedCueIndex, -1)
        XCTAssertEqual(data.activeCueIndex, -1)
    }

    func testReloadingTheSameFileKeepsYourPlace() throws {
        let (data, document) = makeDocument()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("same-\(UUID().uuidString).cuestack")
        try Data("{}".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        data.cueStacks = show(4).cueStacks
        document.lastSavedURL = url
        data.selectedCueStackIndex = 2
        data.selectedCueIndex = 3
        document.applyLoadedData(show(4), from: url, persistAsLastSavedURL: false)
        XCTAssertEqual(data.selectedCueStackIndex, 2)
        XCTAssertEqual(data.selectedCueIndex, 3)
    }

    func testNamesAfterAnEmptyFileAreClean() {
        let (_, document) = makeDocument()
        document.fileName = "Keynote.cuestack (empty — choose Save As to keep changes)"
        XCTAssertEqual(document.fileStem, "Keynote")
        XCTAssertEqual(document.suggestedDuplicateFilename(), "Copy of Keynote.cuestack")
    }
}
