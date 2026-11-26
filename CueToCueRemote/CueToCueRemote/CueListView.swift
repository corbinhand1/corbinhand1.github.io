import SwiftUI

struct EditTarget: Identifiable {
    let cueID: String
    var column: Int
    var id: String { "\(cueID)#\(column)" }
}
struct WhenTarget: Identifiable { let id: String }
struct TimerTarget: Identifiable { let id: String }

enum CueScope: String, CaseIterable, Identifiable {
    case all = "All", when = "[When]", skipped = "Skipped"
    var id: String { rawValue }
}

struct CueListView: View {
    @EnvironmentObject var store: RemoteStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var target: EditTarget?
    @State private var whenTarget: WhenTarget?
    @State private var timerTarget: TimerTarget?
    @State private var showColumns = false
    @State private var showConflicts = false
    @State private var showJump = false
    @State private var flashID: String?
    @State private var scrollRequest: String?
    @State private var confirmBulkDelete = false
    @State private var search = ""
    @State private var scope: CueScope = .all

    private var sheet: Sheet? { store.sheet }
    private var descCol: Int { sheet?.descriptionColumn ?? 1 }
    private var isEditing: Bool { editMode.isEditing }
    private var isFiltering: Bool { scope != .all || !search.trimmingCharacters(in: .whitespaces).isEmpty }
    private var loading: Bool { sheet == nil || sheet?.cueStackId != store.selectedStackID }

    private var cues: [SheetCue] {
        guard let sheet else { return [] }
        var all = sheet.cues
        let col = sheet.descriptionColumn
        switch scope {
        case .all: break
        case .when: all = all.filter { col < $0.values.count && When.text(in: $0.values[col]) != nil }
        case .skipped: all = all.filter(\.isStruckThrough)
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.values.contains { $0.lowercased().contains(q) } }
    }

    // MARK: Body

    var body: some View {
        list
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(sheet?.cueStackName ?? "Cues")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search cues")
        .searchScopes($scope) { ForEach(CueScope.allCases) { Text($0.rawValue).tag($0) } }
        .toolbar { toolbar }
        .toolbarBackground(Theme.background, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { OutboxBanner(showConflicts: $showConflicts) }
        .safeAreaInset(edge: .bottom, spacing: 0) { ToastView() }
        .environment(\.editMode, $editMode)
        .onChange(of: editMode) { _, new in if !new.isEditing { selection.removeAll() } }
        .onChange(of: selection) { _, new in if !isEditing && !new.isEmpty { selection.removeAll() } }  // iPad taps select outside Select mode
        .sensoryFeedback(.selection, trigger: selection.count)
        .sheet(item: $target) { CueEditor(start: $0).environmentObject(store) }
        .sheet(item: $whenTarget) { WhenEditor(start: $0.id).environmentObject(store) }
        .sheet(item: $timerTarget) { TimerEditor(cueID: $0.id).environmentObject(store).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showColumns) { ColumnsEditor().environmentObject(store) }
        .sheet(isPresented: $showConflicts) { ConflictsView().environmentObject(store) }
        .sheet(isPresented: $showJump) { JumpView(onJump: jump).environmentObject(store) }
        .confirmationDialog("Delete \(selection.count) cues?", isPresented: $confirmBulkDelete, titleVisibility: .visible) {
            Button("Delete \(selection.count) Cues", role: .destructive) { bulk { await store.delete($0) } }
        } message: { Text("You can undo right after.") }
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            rawList
                .onChange(of: scrollRequest) { _, id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : .snappy) { proxy.scrollTo(id, anchor: .top) }
                    scrollRequest = nil
                }
        }
    }

    private var rawList: some View {
        List(selection: $selection) {
            ForEach(cues) { cue in
                row(for: cue)
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { Task { await store.setStruck([cue], !cue.isStruckThrough) } } label: {
                            Label(cue.isStruckThrough ? "Restore" : "Skip", systemImage: "strikethrough")
                        }.tint(.indigo)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { Task { await store.delete([cue]) } } label: { Label("Delete", systemImage: "trash") }
                            .tint(.red)
                        Button { Task { _ = await store.duplicate(cue) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            .tint(.blue)
                    }
                    .contextMenu { menu(for: cue) }
            }
            .onMove(perform: isFiltering ? nil : moveRows)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 820)                // readable measure on iPad
        .frame(maxWidth: .infinity)
        .overlay { overlayState }
        .refreshable { await store.refresh() }
        .animation(reduceMotion ? nil : .snappy, value: cues.map(\.id))
    }

    @ViewBuilder private var overlayState: some View {
        if loading {
            ProgressView().controlSize(.large)
        } else if cues.isEmpty {
            ContentUnavailableView(isFiltering ? "No matches" : "No cues yet",
                                   systemImage: isFiltering ? "magnifyingglass" : "list.bullet.rectangle",
                                   description: Text(isFiltering ? "Try a different search or filter." : "Tap + to add the first cue."))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private func row(for cue: SheetCue) -> some View {
        let position = (sheet?.cues.firstIndex { $0.id == cue.id } ?? 0) + 1
        let total = sheet?.cues.count ?? 0
        let label = Self.spokenLabel(cue, columns: sheet?.columns ?? [], descCol: descCol, position: position, total: total)
        return CueRow(cue: cue, columns: sheet?.columns ?? [], descCol: descCol,
                      unsent: store.unsentCueIDs.contains(cue.id),
                      selected: selection.contains(cue.id), editing: isEditing,
                      flash: flashID == cue.id,
                      highlights: sheet?.highlightColors ?? [],
                      open: { col in target = EditTarget(cueID: cue.id, column: col) },
                      editWhen: { whenTarget = WhenTarget(id: cue.id) },
                      editTimer: { timerTarget = TimerTarget(id: cue.id) })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityHint(isEditing ? "Double tap to select" : "Double tap to edit")
            .accessibilityAddTraits(selection.contains(cue.id) ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { if !isEditing { target = EditTarget(cueID: cue.id, column: descCol) } }
            .accessibilityAction(named: "Edit when") { whenTarget = WhenTarget(id: cue.id) }
            .accessibilityAction(named: "Set timer") { timerTarget = TimerTarget(id: cue.id) }
            .accessibilityAction(named: cue.isStruckThrough ? "Restore" : "Skip") { Task { await store.setStruck([cue], !cue.isStruckThrough) } }
            .accessibilityAction(named: "Duplicate") { Task { _ = await store.duplicate(cue) } }
            .accessibilityAction(named: "Insert above") { insert(relativeTo: cue, delta: 0) }
            .accessibilityAction(named: "Insert below") { insert(relativeTo: cue, delta: 1) }
            .accessibilityAction(named: "Move up") { shift(cue, by: -1) }
            .accessibilityAction(named: "Move down") { shift(cue, by: 1) }
            .accessibilityAction(named: "Delete") { Task { await store.delete([cue]) } }
    }

    static func spokenLabel(_ cue: SheetCue, columns: [SheetColumn], descCol: Int, position: Int, total: Int) -> String {
        var parts: [String] = []
        let num = cue.values.first ?? ""
        parts.append(num.isEmpty ? "Cue \(position) of \(total)" : "Cue \(num), \(position) of \(total)")
        if descCol < cue.values.count {
            let d = When.stripped(cue.values[descCol]); if !d.isEmpty { parts.append(d) }
            if let w = When.text(in: cue.values[descCol]) { parts.append("When: \(w.isEmpty ? "empty" : w)") }
        }
        if !cue.timerValue.isEmpty { parts.append("Timer \(cue.timerValue)") }
        for (i, v) in cue.values.enumerated() where i != 0 && i != descCol && !v.isEmpty {
            parts.append("\(i < columns.count ? columns[i].name : "Column \(i + 1)"): \(v)")
        }
        if cue.isStruckThrough { parts.append("Skipped") }
        return parts.joined(separator: ". ")
    }

    // MARK: Menus and toolbar

    @ViewBuilder private func menu(for cue: SheetCue) -> some View {
        Button { target = EditTarget(cueID: cue.id, column: descCol) } label: { Label("Edit Cue", systemImage: "pencil") }
        Button { whenTarget = WhenTarget(id: cue.id) } label: {
            Label(When.text(in: descText(cue)) == nil ? "Add [when]" : "Edit [when]", systemImage: "text.bubble") }
        Button { timerTarget = TimerTarget(id: cue.id) } label: { Label("Set Timer", systemImage: "timer") }
        Divider()
        Button { insert(relativeTo: cue, delta: 0) } label: { Label("Insert Above", systemImage: "arrow.up.to.line") }
        Button { insert(relativeTo: cue, delta: 1) } label: { Label("Insert Below", systemImage: "arrow.down.to.line") }
        Button { Task { _ = await store.duplicate(cue) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Menu {
            Button { shift(cue, by: -1) } label: { Label("Move Up", systemImage: "chevron.up") }
            Button { shift(cue, by: 1) } label: { Label("Move Down", systemImage: "chevron.down") }
            Button { shift(cue, to: 0) } label: { Label("Move to Top", systemImage: "arrow.up.to.line.compact") }
            Button { shift(cue, to: (sheet?.cues.count ?? 1) - 1) } label: { Label("Move to Bottom", systemImage: "arrow.down.to.line.compact") }
        } label: { Label("Move", systemImage: "arrow.up.arrow.down") }
        Button { Task { await store.setStruck([cue], !cue.isStruckThrough) } } label: {
            Label(cue.isStruckThrough ? "Restore Cue" : "Skip Cue", systemImage: "strikethrough") }
        Divider()
        Button(role: .destructive) { Task { await store.delete([cue]) } } label: { Label("Delete", systemImage: "trash") }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(sheet?.cueStackName ?? "Cues").font(.headline).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: store.live ? "dot.radiowaves.left.and.right" : "wifi.slash").imageScale(.small)
                    Text(store.live ? "Live" : "Offline")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(store.live ? Theme.success : Color.orange)
            }
            .accessibilityElement(children: .combine)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !isEditing {
                Button { showJump = true } label: { Image(systemName: "arrow.down.to.line.compact").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Jump to a demo or cue")
                    .keyboardShortcut("j", modifiers: .command)
            }
            if store.canUndo && !isEditing {
                Button { Task { await store.undo() } } label: { Image(systemName: "arrow.uturn.backward").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Undo \(store.undoStack.last?.label ?? "")")
                    .keyboardShortcut("z", modifiers: .command)
            }
            Menu {
                Button { Task { await store.undo() } } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(!store.canUndo)
                Button { Task { await store.redo() } } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(!store.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                Divider()
                Button { addAtEnd() } label: { Label("Add Cue at End", systemImage: "plus") }
                Button { withAnimation { editMode = .active } } label: { Label("Select Cues", systemImage: "checkmark.circle") }
                Button { showColumns = true } label: { Label("Columns", systemImage: "rectangle.split.3x1") }
            } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                .accessibilityLabel("More")
            if isEditing {
                Button("Done") { withAnimation { editMode = .inactive } }.fontWeight(.semibold)
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            if isEditing {
                Button(selection.count == cues.count && !cues.isEmpty ? "Deselect All" : "Select All") {
                    selection = selection.count == cues.count ? [] : Set(cues.map(\.id))
                }
                Spacer()
                Button { bulk { cs in await store.setStruck(cs, !cs.allSatisfy(\.isStruckThrough)) } } label: {
                    Image(systemName: "strikethrough") }.disabled(selection.isEmpty).accessibilityLabel("Skip or restore selected")
                Button { bulk { cs in for c in cs.reversed() { _ = await store.duplicate(c) } } } label: {
                    Image(systemName: "plus.square.on.square") }.disabled(selection.isEmpty).accessibilityLabel("Duplicate selected")
                Button(role: .destructive) { selection.count == 1 ? bulk { await store.delete($0) } : (confirmBulkDelete = true) } label: {
                    Image(systemName: "trash") }.disabled(selection.isEmpty).accessibilityLabel("Delete selected")
            }
        }
    }

    // MARK: Actions

    /// Scrolls to a cue (clearing any search or filter first) and flashes it so it's easy to spot.
    private func jump(to cueID: String) {
        scope = .all; search = ""
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)     // let the full list come back first
            scrollRequest = cueID
            flashID = cueID
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if flashID == cueID { flashID = nil }
        }
    }

    private func descText(_ cue: SheetCue) -> String { descCol < cue.values.count ? cue.values[descCol] : "" }

    private func addAtEnd() {
        Task {
            if let id = await store.insertCue(at: sheet?.cues.count ?? 0) {
                scope = .all; search = ""
                target = EditTarget(cueID: id, column: descCol)
            }
        }
    }

    private func insert(relativeTo cue: SheetCue, delta: Int) {
        guard let i = sheet?.cues.firstIndex(where: { $0.id == cue.id }) else { return }
        Task {
            if let id = await store.insertCue(at: i + delta, label: delta == 0 ? "Insert Above" : "Insert Below") {
                target = EditTarget(cueID: id, column: descCol)
            }
        }
    }

    private func shift(_ cue: SheetCue, by delta: Int) {
        guard let i = sheet?.cues.firstIndex(where: { $0.id == cue.id }) else { return }
        shift(cue, to: i + delta)
    }

    private func shift(_ cue: SheetCue, to index: Int) { Task { await store.moveCue(id: cue.id, to: index) } }

    private func moveRows(from: IndexSet, to: Int) {
        guard let f = from.first, cues.indices.contains(f) else { return }
        let id = cues[f].id
        Task { await store.moveCue(id: id, to: to > f ? to - 1 : to) }
    }

    /// Runs an action over the selected cues, in list order, then leaves select mode.
    private func bulk(_ action: @escaping ([SheetCue]) async -> Void) {
        let chosen = (sheet?.cues ?? []).filter { selection.contains($0.id) }
        Task {
            await action(chosen)
            selection.removeAll()
            withAnimation { editMode = .inactive }
        }
    }
}

// MARK: - Cue row

struct CueRow: View {
    let cue: SheetCue
    let columns: [SheetColumn]
    let descCol: Int
    let unsent: Bool
    let selected: Bool
    let editing: Bool
    let flash: Bool
    let highlights: [HighlightRule]
    let open: (Int) -> Void
    let editWhen: () -> Void
    let editTimer: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .title3) private var numberWidth: CGFloat = 52

    /// Whole-cue text color from the show's highlight rules (same rule as the Mac); nil = normal text.
    private var tint: Color? {
        guard let i = Highlight.ruleIndex(for: cue, rules: highlights) else { return nil }
        return .highlight(hex: highlights[i].color, darkMode: scheme == .dark)
    }
    private var number: String { cue.values.first ?? "" }
    private var description: String { descCol < cue.values.count ? cue.values[descCol] : "" }
    private var when: String? { When.text(in: description) }
    private var title: String { When.stripped(description) }
    private var chips: [(index: Int, name: String, value: String)] {
        cue.values.enumerated().compactMap { i, v in
            guard i != 0, i != descCol, !v.isEmpty else { return nil }
            return (i, i < columns.count ? columns[i].name : "Col \(i + 1)", v)
        }
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            numberButton
            VStack(alignment: .leading, spacing: 8) {
                titleButton
                if let when { whenButton(when) }
                if !cue.timerValue.isEmpty { timerButton }
                if !chips.isEmpty { chipFlow }
                if cue.isStruckThrough {
                    Label("Skipped", systemImage: "strikethrough").font(.caption.weight(.semibold)).foregroundStyle(Theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .strokeBorder(selected || flash ? Theme.accent : Color.clear, lineWidth: 2))
        .animation(.easeOut(duration: 0.25), value: flash)
        .overlay(alignment: .topTrailing) {
            if unsent {
                Image(systemName: "arrow.up.circle.fill").font(.footnote).foregroundStyle(Color.orange).padding(6)
            }
        }
        .opacity(cue.isStruckThrough ? 0.6 : 1)
        .contentShape(Rectangle())
    }

    private var numberButton: some View {
        Button { open(0) } label: {
            Text(number.isEmpty ? "·" : number)
                .font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                .foregroundStyle(number.isEmpty ? Theme.textMuted : Theme.accent)
                .minimumScaleFactor(0.6).lineLimit(1)
                .padding(.horizontal, typeSize.isAccessibilitySize ? 16 : 0)
                .frame(minWidth: typeSize.isAccessibilitySize ? 0 : numberWidth, minHeight: Theme.minTarget)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressStyle()).disabled(editing)
    }

    private var titleButton: some View {
        Button { open(descCol) } label: {
            Text(title.isEmpty ? "Add description" : title)
                .font(.body.weight(.medium))
                .strikethrough(cue.isStruckThrough)
                .foregroundStyle(title.isEmpty ? Theme.textMuted : (tint ?? Theme.text))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle()).disabled(editing)
    }

    private func whenButton(_ when: String) -> some View {
        Button(action: editWhen) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("WHEN").font(.caption2.weight(.heavy)).foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 4))
                Text(when.isEmpty ? "tap to add" : when)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(when.isEmpty ? Theme.textMuted : (tint ?? Theme.text))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.accent.opacity(0.8), lineWidth: 1.5))
        }
        .buttonStyle(PressStyle()).disabled(editing)
    }

    private var timerButton: some View {
        Button(action: editTimer) {
            Label(cue.timerValue, systemImage: "timer").monospacedDigit().font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text).padding(.horizontal, 12)
                .frame(minHeight: 36).background(Theme.cardRaised, in: Capsule())
        }
        .buttonStyle(PressStyle()).disabled(editing)
    }

    private var chipFlow: some View {
        FlowLayout(spacing: 8) {
            ForEach(chips, id: \.index) { chip in
                Button { open(chip.index) } label: {
                    HStack(spacing: 6) {
                        Text(chip.name.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                        Text(chip.value).font(.subheadline).foregroundStyle(tint ?? Theme.text).lineLimit(2)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 40)
                    .background(Theme.cardRaised, in: Capsule())
                }
                .buttonStyle(PressStyle()).disabled(editing)
            }
        }
    }
}
