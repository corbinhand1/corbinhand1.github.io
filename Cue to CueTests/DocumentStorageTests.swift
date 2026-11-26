//
//  DocumentStorageTests.swift
//  Cue to CueTests
//
//  Real save / load / conflict / recovery / relaunch flows, run against an
//  isolated DocumentStore: a temp folder for files and Application Support,
//  a private UserDefaults suite, and backup fan-out turned off. Nothing here
//  touches the user's real last-document bookmark, Desktop or backups.
//

import XCTest
@testable import Cue_to_Cue

@MainActor
final class DocumentStorageTests: XCTestCase {

    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: DocumentStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueToCueStorageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // One fixed suite, cleared before and after each test: macOS
        // re-creates a plist for every suite name, so per-test names left
        // dozens of files in ~/Library/Preferences.
        suiteName = "CueToCueStorageTests"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = makeStore()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore() -> DocumentStore {
        DocumentStore(defaults: defaults, appSupportRoot: root.appendingPathComponent("AppSupport"), fansOutBackups: false)
    }

    private func makeDocument(store: DocumentStore? = nil) -> (DataSyncManager, CueEditorController, DocumentController) {
        let data = DataSyncManager()
        let editor = CueEditorController(data: data)
        let document = DocumentController(data: data, editor: editor, store: store ?? self.store)
        return (data, editor, document)
    }

    private func sampleStacks() -> [CueStack] {
        [CueStack(name: "Main", cues: [Cue(values: ["1", "Doors"]), Cue(values: ["2", "Walk-in"])],
                  columns: [Column(name: "#", width: 60), Column(name: "Description", width: 200)])]
    }

    private var showURL: URL { root.appendingPathComponent("Show.cuestack") }

    // MARK: Save As

    /// File ▸ Save As… passes no completion; the chosen file must still be
    /// written and become the open document.
    func testSaveAsWithoutCompletionWritesTheNewFile() throws {
        let (data, _, document) = makeDocument()
        data.cueStacks = sampleStacks()
        XCTAssertTrue(document.saveToURL(showURL))
        let newURL = root.appendingPathComponent("New Show.cuestack")

        document.finishSaveAs(chosenURL: newURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertEqual(document.lastSavedURL?.standardizedFileURL, newURL.standardizedFileURL)
        XCTAssertEqual(document.fileName, "New Show.cuestack")
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(try store.load(from: newURL).cueStacks.first?.cues.count, 2)
    }

    func testSaveAsCancelledWritesNothing() {
        var result: Bool?
        let (_, _, document) = makeDocument()
        document.finishSaveAs(chosenURL: nil) { result = $0 }
        XCTAssertEqual(result, false)
        XCTAssertNil(document.lastSavedURL)
    }

    // MARK: DocumentStore

    func testSaveAndLoadRoundTrip() throws {
        let saved = SavedData(cueStacks: sampleStacks(), highlightColors: [])
        let result = try store.save(saved, to: showURL)
        XCTAssertEqual(result.url, showURL)
        let loaded = try store.load(from: showURL)
        XCTAssertEqual(loaded.cueStacks, saved.cueStacks)
    }

    func testRefusesToSaveEmptyDocument() {
        XCTAssertThrowsError(try store.save(SavedData(cueStacks: [], highlightColors: []), to: showURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: showURL.path))
    }

    func testOverwriteSnapshotsPreviousVersion() throws {
        var stacks = sampleStacks()
        try store.save(SavedData(cueStacks: stacks, highlightColors: []), to: showURL)
        stacks[0].name = "Renamed"
        let second = try store.save(SavedData(cueStacks: stacks, highlightColors: []), to: showURL)
        let backup = try XCTUnwrap(second.backedUpTo)
        XCTAssertEqual(try store.load(from: backup).cueStacks.first?.name, "Main")
        XCTAssertTrue(backup.path.hasPrefix(root.path), "backups stay inside the isolated root")
    }

    func testBookmarksUseInjectedDefaults() throws {
        try store.saveBookmark(for: showURL.deletingLastPathComponent())
        XCTAssertNotNil(defaults.data(forKey: "LastDocumentBookmark"))
        store.clearBookmark()
        XCTAssertNil(defaults.data(forKey: "LastDocumentBookmark"))
    }

    func testRecoveryAutosavesReuseOneFile() throws {
        let saved = SavedData(cueStacks: sampleStacks(), highlightColors: [])
        let first = try store.saveRecovery(saved, suggestedStem: "Untitled")
        let second = try store.saveRecovery(saved, suggestedStem: "Untitled")
        XCTAssertEqual(first.url, second.url, "autosave must overwrite, not add a file every 30 s")
        let files = try FileManager.default.contentsOfDirectory(atPath: store.recoveryDirectory().path)
        XCTAssertEqual(files.count, 1)
    }

    func testPruneRecoveryKeepsRecentAndNewest() throws {
        let dir = try store.recoveryDirectory()
        let old = Date().addingTimeInterval(-30 * 24 * 3600)
        for i in 0..<25 {
            let url = dir.appendingPathComponent("old-\(i).json")
            try Data("{}".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: old.addingTimeInterval(Double(i))], ofItemAtPath: url.path)
        }
        store.pruneRecoveryFiles()
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(remaining.count, 20, "old files beyond the newest 20 are removed")
        XCTAssertTrue(remaining.contains("old-24.json"))
        XCTAssertFalse(remaining.contains("old-0.json"))
    }

    // MARK: DocumentController with real files

    func testSaveToURLClearsDirtyAndRemembersFile() {
        let (data, _, document) = makeDocument()
        data.cueStacks = sampleStacks()
        XCTAssertTrue(document.isDirty)

        XCTAssertTrue(document.saveToURL(showURL))
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(document.fileName, "Show.cuestack")
        XCTAssertEqual(document.lastSavedURL, showURL)
        XCTAssertNotNil(defaults.data(forKey: "LastDocumentBookmark"))
    }

    func testRelaunchReopensLastFile() {
        let (data, _, document) = makeDocument()
        data.cueStacks = sampleStacks()
        XCTAssertTrue(document.saveToURL(showURL))

        // A fresh controller (as after relaunch) sharing the same store/defaults.
        let (data2, _, document2) = makeDocument(store: makeStore())
        document2.loadLastFile()
        XCTAssertEqual(data2.cueStacks, data.cueStacks)
        XCTAssertEqual(document2.lastSavedURL?.standardizedFileURL, showURL.standardizedFileURL)
        XCTAssertFalse(document2.isDirty)
    }

    func testRelaunchLoadsNewerVersionChangedWhileClosed() throws {
        let (data, _, document) = makeDocument()
        data.cueStacks = sampleStacks()
        XCTAssertTrue(document.saveToURL(showURL))

        // Another Mac / iCloud updates the file while the app is closed.
        var newer = sampleStacks()
        newer[0].cues.append(Cue(values: ["3", "Added elsewhere"]))
        try JSONEncoder().encode(SavedData(cueStacks: newer, highlightColors: [])).write(to: showURL)

        let (data2, _, document2) = makeDocument(store: makeStore())
        document2.loadLastFile()
        XCTAssertEqual(data2.cueStacks.first?.cues.count, 3, "the newer file loads; no empty-overwrite conflict prompt")
        XCTAssertFalse(document2.showConflictAlert)
    }

    func testSaveRefusesToOverwriteExternalChanges() throws {
        let (data, _, document) = makeDocument()
        data.cueStacks = sampleStacks()
        XCTAssertTrue(document.saveToURL(showURL))

        let external = Data(#"{"cueStacks":[{"id":"\#(UUID().uuidString)","name":"External edit with a longer name","cues":[],"columns":[]}],"highlightColors":[]}"#.utf8)
        // Wait out the self-write window so this counts as someone else's write.
        RunLoop.main.run(until: Date().addingTimeInterval(2.2))
        try external.write(to: showURL)

        data.cueStacks[0].name = "My edit"
        XCTAssertFalse(document.saveToURL(showURL), "must not silently overwrite")
        XCTAssertTrue(document.showConflictAlert)
        XCTAssertEqual(try Data(contentsOf: showURL), external, "the other program's version is untouched")
    }

    func testAutosaveWritesToCurrentFile() throws {
        let (data, _, document) = makeDocument()
        data.cueStacks = sampleStacks()
        XCTAssertTrue(document.saveToURL(showURL))
        data.cueStacks[0].name = "Autosaved"
        document.autoSave()
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(try store.load(from: showURL).cueStacks.first?.name, "Autosaved")
    }

    func testAutosaveOfUntitledGoesToRecoveryAndStaysDirty() throws {
        let (data, _, document) = makeDocument()
        data.cueStacks = sampleStacks()
        document.autoSave()
        document.autoSave()
        let recovery = try XCTUnwrap(document.lastRecoveryURL)
        XCTAssertTrue(recovery.path.hasPrefix(root.path))
        XCTAssertTrue(document.isDirty, "still needs a real Save As")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.recoveryDirectory().path).count, 1)
    }

    func testQuitWithUnsavedChangesSavesToCurrentFile() throws {
        let (data, _, document) = makeDocument()
        data.cueStacks = sampleStacks()
        XCTAssertTrue(document.saveToURL(showURL))
        data.cueStacks[0].name = "Edited before quit"

        var canQuit: Bool?
        document.prepareForQuit { canQuit = $0 }
        XCTAssertEqual(canQuit, true)
        XCTAssertEqual(try store.load(from: showURL).cueStacks.first?.name, "Edited before quit")
    }
}
