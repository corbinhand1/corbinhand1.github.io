import Foundation

/// A cell edit made on the phone that the Mac hasn't confirmed yet.
struct PendingEdit: Codable, Identifiable, Equatable {
    var id = UUID()
    var stackID: String
    var cueID: String
    var column: Int
    var columnName: String
    /// Short label ("Cue 12 · Gloria Mic Hot") so conflicts are recognizable.
    var cueLabel: String
    /// The cell value the user saw when they started editing.
    var base: String
    var newValue: String
    /// Set when the Mac's value changed to something else in the meantime.
    var conflictRemote: String?
}

/// Disk persistence so unsent edits and the last-seen sheet survive relaunches.
enum Outbox {
    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static var pendingURL: URL { dir.appendingPathComponent("pending-edits.json") }
    private static var sheetURL: URL { dir.appendingPathComponent("last-sheet.json") }

    static func loadPending() -> [PendingEdit] {
        (try? Data(contentsOf: pendingURL)).flatMap { try? JSONDecoder().decode([PendingEdit].self, from: $0) } ?? []
    }
    static func savePending(_ edits: [PendingEdit]) {
        if edits.isEmpty { try? FileManager.default.removeItem(at: pendingURL); return }
        try? JSONEncoder().encode(edits).write(to: pendingURL, options: .atomic)
    }
    static func loadSheet() -> Sheet? {
        (try? Data(contentsOf: sheetURL)).flatMap { try? JSONDecoder().decode(Sheet.self, from: $0) }
    }
    static func saveSheet(_ sheet: Sheet) {
        try? JSONEncoder().encode(sheet).write(to: sheetURL, options: .atomic)
    }
    static func clearAll() {
        try? FileManager.default.removeItem(at: pendingURL)
        try? FileManager.default.removeItem(at: sheetURL)
    }
}
