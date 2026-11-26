import SwiftUI

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var canUndo: Bool
}

/// One undoable action. Closures re-apply the change (or its inverse) on the Mac.
struct HistoryEntry {
    let label: String
    let undo: @MainActor () async -> Bool
    let redo: @MainActor () async -> Bool
}

extension RemoteStore {
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Feedback

    func showToast(_ message: String, canUndo: Bool = false) {
        let t = Toast(message: message, canUndo: canUndo)
        toast = t
        UIAccessibility.post(notification: .announcement, argument: message)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled, self?.toast?.id == t.id { self?.toast = nil }
        }
    }

    // MARK: History

    func record(_ label: String, undo: @escaping @MainActor () async -> Bool, redo: @escaping @MainActor () async -> Bool) {
        undoStack.append(HistoryEntry(label: label, undo: undo, redo: redo))
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() async {
        guard let entry = undoStack.popLast() else { return }
        if await entry.undo() {
            redoStack.append(entry)
            Haptics.tap()
            showToast("Undid \(entry.label)")
        } else { undoStack.append(entry) }
    }

    func redo() async {
        guard let entry = redoStack.popLast() else { return }
        if await entry.redo() {
            undoStack.append(entry)
            Haptics.tap()
            showToast("Redid \(entry.label)")
        } else { redoStack.append(entry) }
    }

    // MARK: Running structural ops

    /// Sends one op to the Mac. Structure changes need a connection (cell text edits can queue offline).
    func perform(_ body: [String: Any]) async -> (ok: Bool, id: String?) {
        guard let api else { return (false, nil) }
        do {
            let id = try await api.op(body)
            return (true, id)
        } catch {
            if error is URLError {
                self.error = "Can't reach the Mac. Changes to the cue list need a connection."
            } else {
                self.error = Self.message(error)
            }
            return (false, nil)
        }
    }

    /// Runs an op and reloads the sheet so the list matches the Mac.
    @discardableResult
    func exec(_ body: [String: Any]) async -> Bool {
        let r = await perform(body)
        if r.ok { await refresh() }
        return r.ok
    }

    private func insertBody(stack: String, index: Int, values: [String], timer: String, struck: Bool, id: String? = nil) -> [String: Any] {
        var b: [String: Any] = ["op": "insert", "cueStackId": stack, "index": index, "values": values,
                                "timerValue": timer, "isStruckThrough": struck]
        if let id { b["cueId"] = id }
        return b
    }

    // MARK: Cue tools

    /// Inserts a cue at `index` (blank unless values are given). Returns the new cue's id.
    @discardableResult
    func insertCue(at index: Int, values: [String]? = nil, timer: String = "", struck: Bool = false,
                   label: String = "Add Cue") async -> String? {
        guard let sheet else { return nil }
        let stack = sheet.cueStackId
        let vals = values ?? Array(repeating: "", count: sheet.columns.count)
        let r = await perform(insertBody(stack: stack, index: index, values: vals, timer: timer, struck: struck))
        guard r.ok, let newID = r.id else { return nil }
        record(label,
               undo: { [weak self] in await self?.exec(["op": "delete", "cueIds": [newID]]) ?? false },
               redo: { [weak self] in
                   guard let self else { return false }
                   return await self.exec(self.insertBody(stack: stack, index: index, values: vals, timer: timer, struck: struck, id: newID)) })
        Haptics.success()
        await refresh()
        return newID
    }

    func duplicate(_ cue: SheetCue) async -> String? {
        guard let i = sheet?.cues.firstIndex(where: { $0.id == cue.id }) else { return nil }
        let id = await insertCue(at: i + 1, values: cue.values, timer: cue.timerValue,
                                 struck: cue.isStruckThrough, label: "Duplicate")
        if id != nil { showToast("Cue duplicated", canUndo: true) }
        return id
    }

    func delete(_ cues: [SheetCue]) async {
        guard let sheet, !cues.isEmpty else { return }
        let stack = sheet.cueStackId
        let items = cues.compactMap { c in sheet.cues.firstIndex(where: { $0.id == c.id }).map { (index: $0, cue: sheet.cues[$0]) } }
            .sorted { $0.index < $1.index }
        let ids = items.map(\.cue.id)
        self.sheet?.cues.removeAll { ids.contains($0.id) }          // optimistic
        guard await exec(["op": "delete", "cueIds": ids]) else { await refresh(); return }
        let label = items.count == 1 ? "Delete Cue" : "Delete \(items.count) Cues"
        record(label,
               undo: { [weak self] in
                   guard let self else { return false }
                   for item in items {   // ascending, so each lands at its original position
                       let r = await self.perform(self.insertBody(stack: stack, index: item.index, values: item.cue.values,
                                                                  timer: item.cue.timerValue, struck: item.cue.isStruckThrough,
                                                                  id: item.cue.id))
                       if !r.ok { return false }
                   }
                   await self.refresh(); return true },
               redo: { [weak self] in await self?.exec(["op": "delete", "cueIds": ids]) ?? false })
        Haptics.warning()
        showToast(items.count == 1 ? "Cue deleted" : "\(items.count) cues deleted", canUndo: true)
    }

    /// Moves a cue so it ends at `finalIndex` in the list.
    func moveCue(id: String, to finalIndex: Int) async {
        guard let from = sheet?.cues.firstIndex(where: { $0.id == id }), let count = sheet?.cues.count,
              finalIndex != from, (0..<count).contains(finalIndex) else { return }
        sheet?.cues.move(fromOffsets: IndexSet(integer: from), toOffset: finalIndex > from ? finalIndex + 1 : finalIndex)  // optimistic
        guard await exec(["op": "move", "cueId": id, "toIndex": finalIndex]) else { await refresh(); return }
        record("Move Cue",
               undo: { [weak self] in await self?.exec(["op": "move", "cueId": id, "toIndex": from]) ?? false },
               redo: { [weak self] in await self?.exec(["op": "move", "cueId": id, "toIndex": finalIndex]) ?? false })
        Haptics.tap()
    }

    func setStruck(_ cues: [SheetCue], _ struck: Bool) async {
        let targets = cues.filter { $0.isStruckThrough != struck }
        guard !targets.isEmpty else { return }
        let ids = targets.map(\.id)
        for i in sheet?.cues.indices ?? 0..<0 where ids.contains(sheet!.cues[i].id) { sheet?.cues[i].isStruckThrough = struck }
        guard await exec(["op": "strike", "cueIds": ids, "struck": struck]) else { await refresh(); return }
        record(struck ? "Skip Cue" : "Restore Cue",
               undo: { [weak self] in await self?.exec(["op": "strike", "cueIds": ids, "struck": !struck]) ?? false },
               redo: { [weak self] in await self?.exec(["op": "strike", "cueIds": ids, "struck": struck]) ?? false })
        Haptics.select()
    }

    func setTimer(_ cue: SheetCue, _ value: String) async {
        let old = cue.timerValue
        guard value != old else { return }
        guard await exec(["op": "timer", "cueId": cue.id, "timerValue": value]) else { return }
        record("Timer",
               undo: { [weak self] in await self?.exec(["op": "timer", "cueId": cue.id, "timerValue": old]) ?? false },
               redo: { [weak self] in await self?.exec(["op": "timer", "cueId": cue.id, "timerValue": value]) ?? false })
        Haptics.success()
    }

    // MARK: Column tools (administrators)

    private var columnGuard: Bool {
        if !pending.isEmpty {
            error = "Send or discard your unsent edits before changing columns."
            return false
        }
        return true
    }

    func addColumn(_ name: String, at index: Int? = nil) async {
        guard let sheet, columnGuard else { return }
        let at = index ?? sheet.columns.count
        guard await exec(["op": "addColumn", "cueStackId": sheet.cueStackId, "name": name, "index": at]) else { return }
        let stack = sheet.cueStackId
        record("Add Column",
               undo: { [weak self] in await self?.exec(["op": "deleteColumn", "cueStackId": stack, "columnIndex": at]) ?? false },
               redo: { [weak self] in await self?.exec(["op": "addColumn", "cueStackId": stack, "name": name, "index": at]) ?? false })
        Haptics.success()
    }

    func renameColumn(_ index: Int, to name: String) async {
        guard let sheet, index < sheet.columns.count, columnGuard else { return }
        let old = sheet.columns[index].name, stack = sheet.cueStackId
        guard await exec(["op": "renameColumn", "cueStackId": stack, "columnIndex": index, "name": name]) else { return }
        record("Rename Column",
               undo: { [weak self] in await self?.exec(["op": "renameColumn", "cueStackId": stack, "columnIndex": index, "name": old]) ?? false },
               redo: { [weak self] in await self?.exec(["op": "renameColumn", "cueStackId": stack, "columnIndex": index, "name": name]) ?? false })
    }

    func moveColumn(from: Int, to: Int) async {
        guard let sheet, from != to, columnGuard else { return }
        let stack = sheet.cueStackId
        guard await exec(["op": "moveColumn", "cueStackId": stack, "from": from, "to": to]) else { return }
        record("Move Column",
               undo: { [weak self] in await self?.exec(["op": "moveColumn", "cueStackId": stack, "from": to, "to": from]) ?? false },
               redo: { [weak self] in await self?.exec(["op": "moveColumn", "cueStackId": stack, "from": from, "to": to]) ?? false })
        Haptics.tap()
    }

    func deleteColumn(_ index: Int) async {
        guard let sheet, index < sheet.columns.count, columnGuard else { return }
        let stack = sheet.cueStackId, col = sheet.columns[index]
        let contents = sheet.cues.compactMap { c -> (String, String)? in
            index < c.values.count && !c.values[index].isEmpty ? (c.id, c.values[index]) : nil }
        guard await exec(["op": "deleteColumn", "cueStackId": stack, "columnIndex": index]) else { return }
        record("Delete Column",
               undo: { [weak self] in
                   guard let self, await self.exec(["op": "addColumn", "cueStackId": stack, "name": col.name,
                                                    "index": index, "width": col.width]) else { return false }
                   for (cueID, text) in contents { try? await self.api?.edit(cueID: cueID, column: index, value: text) }
                   await self.refresh(); return true },
               redo: { [weak self] in await self?.exec(["op": "deleteColumn", "cueStackId": stack, "columnIndex": index]) ?? false })
        Haptics.warning()
        showToast("Column “\(col.name)” deleted", canUndo: true)
    }
}
