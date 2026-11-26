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
