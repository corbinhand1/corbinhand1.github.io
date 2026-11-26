import SwiftUI

/// Which cue and column the editor should open on.
struct EditTarget: Identifiable {
    let cueID: String
    var column: Int
    var id: String { "\(cueID)#\(column)" }
}

struct WhenTarget: Identifiable { let id: String }

struct SheetView: View {
    @EnvironmentObject var store: RemoteStore
    @State private var target: EditTarget?
    @State private var search = ""
    @State private var pendingDelete: SheetCue?
    @State private var whenTarget: WhenTarget?
    @State private var onlyWhen = false
    @State private var showConflicts = false
    @State private var confirmSignOut = false

    private var cues: [SheetCue] {
        guard var all = store.sheet?.cues else { return [] }
        if onlyWhen {
            let col = store.sheet?.descriptionColumn ?? 1
            all = all.filter { col < $0.values.count && When.text(in: $0.values[col]) != nil }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.values.contains { $0.lowercased().contains(q) } }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(cues) { cue in
                            CueCard(cue: cue, columns: store.sheet?.columns ?? [],
                                    descCol: store.sheet?.descriptionColumn ?? 1,
                                    position: position(of: cue),
                                    unsent: store.unsentCueIDs.contains(cue.id),
                                    open: { col in target = EditTarget(cueID: cue.id, column: col) },
                                    editWhen: { whenTarget = WhenTarget(id: cue.id) },
                                    delete: { pendingDelete = cue })
                        }
                        if cues.isEmpty {
                            ContentUnavailableView(search.isEmpty ? "No cues yet" : "No matches",
                                                   systemImage: search.isEmpty ? "list.bullet.rectangle" : "magnifyingglass",
                                                   description: Text(search.isEmpty ? "Tap the + button to add the first cue." : "Try a different search."))
                                .foregroundStyle(Theme.textMuted)
                                .padding(.top, 60)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 110) // room for the add button
                }
                .refreshable { await store.refresh() }
                addButton
            }
            .navigationTitle(store.sheet?.cueStackName ?? "Cues")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search cues")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { stackMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Button { onlyWhen.toggle() } label: {
                            Text("[ ]")
                                .font(.system(.body, design: .monospaced).weight(.bold))
                                .foregroundStyle(onlyWhen ? Theme.onAccent : Theme.accent)
                                .frame(width: 44, height: 36)
                                .background(onlyWhen ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .accessibilityLabel("Show only cues with a when")
                        .accessibilityAddTraits(onlyWhen ? .isSelected : [])
                        liveBadge
                    }
                }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: $target) { t in
                CueEditor(start: t).environmentObject(store)
            }
            .safeAreaInset(edge: .top, spacing: 0) { OutboxBanner(showConflicts: $showConflicts) }
            .sheet(isPresented: $showConflicts) { ConflictsView().environmentObject(store) }
            .confirmationDialog("You have edits that haven't reached the Mac.", isPresented: $confirmSignOut,
                                titleVisibility: .visible) {
                Button("Sign Out and Discard Them", role: .destructive) { store.signOut() }
            } message: { Text("Wait until they send, or they'll be lost.") }
            .sheet(item: $whenTarget) { t in
                WhenEditor(start: t.id).environmentObject(store)
            }
            .confirmationDialog("Delete this cue?", isPresented: Binding(get: { pendingDelete != nil },
                                                                         set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete Cue", role: .destructive) {
                    if let c = pendingDelete { Task { await store.delete(c) } }
                }
            } message: { Text("This removes it from the show on your Mac. It can't be undone from here.") }
            .alert("Problem", isPresented: Binding(get: { store.error != nil },
                                                   set: { if !$0 { store.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(store.error ?? "") }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func position(of cue: SheetCue) -> Int {
        (store.sheet?.cues.firstIndex(where: { $0.id == cue.id }) ?? 0) + 1
    }

    private var addButton: some View {
        Button {
            Task { if let id = await store.addCue() { target = EditTarget(cueID: id, column: 1) } }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 60, height: 60)
                .background(Theme.accent, in: Circle())
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
        }
        .accessibilityLabel("Add cue")
        .padding(20)
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: store.live ? "dot.radiowaves.left.and.right" : "wifi.exclamationmark")
            Text(store.live ? "Live" : "Offline").font(.caption.weight(.semibold))
        }
        .foregroundStyle(store.live ? Color.green : Color.orange)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(store.live ? "Connected, live" : "Reconnecting")
    }

    private var stackMenu: some View {
        Menu {
            if let stacks = store.sheet?.availableCueStacks {
                ForEach(stacks) { s in
                    Button {
                        Task { await store.selectStack(s.id) }
                    } label: {
                        if s.id == store.selectedStackID { Label(s.name, systemImage: "checkmark") }
                        else { Text(s.name) }
                    }
                }
            }
            Divider()
            if store.faceIDEnabled {
                Button("Turn off \(Biometrics.name) lock") { store.disableFaceID() }
            }
            Button("Sign out", role: .destructive) {
                if store.pending.isEmpty { store.signOut() } else { confirmSignOut = true }
            }
        } label: {
            Image(systemName: "rectangle.stack").frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Switch cue stack")
    }
}

// MARK: - Cue card

private struct CueCard: View {
    let cue: SheetCue
    let columns: [SheetColumn]
    let descCol: Int
    let position: Int
    let unsent: Bool
    let open: (Int) -> Void
    let editWhen: () -> Void
    let delete: () -> Void

    private var number: String { cue.values.first ?? "" }
    private var description: String { descCol < cue.values.count ? cue.values[descCol] : "" }
    private var when: String? { When.text(in: description) }
    private var title: String { When.stripped(description) }
    /// Filled columns beyond # and Description, shown as tappable chips.
    private var chips: [(index: Int, name: String, value: String)] {
        cue.values.enumerated().compactMap { i, v in
            guard i >= 1, i != descCol, i != 0, !v.isEmpty else { return nil }
            return (i, i < columns.count ? columns[i].name : "Col \(i + 1)", v)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Cue number — tap to edit it directly.
            Button { open(0) } label: {
                Text(number.isEmpty ? "·" : number)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(number.isEmpty ? Theme.textMuted : Theme.accent)
                    .frame(width: 52, height: Theme.minTarget)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Cue number \(number.isEmpty ? "not set" : number). Edit")

            VStack(alignment: .leading, spacing: 8) {
                Button { open(descCol) } label: {
                    Text(title.isEmpty ? "Add description" : title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(title.isEmpty ? Theme.textMuted : Theme.text)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Description: \(title.isEmpty ? "empty" : title). Edit")

                if let when {
                    Button(action: editWhen) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("WHEN").font(.caption2.weight(.heavy)).foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 4))
                            Text(when.isEmpty ? "tap to add" : when)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(when.isEmpty ? Theme.textMuted : Theme.text)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.8), lineWidth: 1.5))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("When: \(when.isEmpty ? "empty" : when). Edit")
                }

                if !chips.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(chips, id: \.index) { chip in
                            Button { open(chip.index) } label: {
                                HStack(spacing: 6) {
                                    Text(chip.name.uppercased())
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Theme.accent)
                                    Text(chip.value)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(2)
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 40)
                                .background(Theme.cardRaised, in: Capsule())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel("\(chip.name): \(chip.value). Edit")
                        }
                    }
                }
            }

            Menu {
                Button(action: editWhen) { Label(when == nil ? "Add [when]" : "Edit [when]", systemImage: "text.bubble") }
                Button { open(descCol) } label: { Label("Edit cue", systemImage: "pencil") }
                Button(role: .destructive, action: delete) { Label("Delete cue", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 40, height: Theme.minTarget)
            }
            .accessibilityLabel("More actions for cue \(position)")
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .opacity(cue.isStruckThrough ? 0.45 : 1)
        .overlay(alignment: .topTrailing) {
            if unsent {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.footnote).foregroundStyle(Color.orange)
                    .padding(6)
                    .accessibilityLabel("Not sent to the Mac yet")
            }
        }
        .overlay(alignment: .topLeading) {
            if cue.isStruckThrough {
                Text("Skipped").font(.caption2.weight(.bold)).foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 6).padding(.top, 2)
            }
        }
    }
}

/// Brief dim on press so every tap target gives immediate feedback.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}


// MARK: - Outbox banner and conflicts

/// Shows edits that are waiting for the Mac, and any that need a decision.
private struct OutboxBanner: View {
    @EnvironmentObject var store: RemoteStore
    @Binding var showConflicts: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !store.conflicts.isEmpty {
                Button { showConflicts = true } label: {
                    row(icon: "exclamationmark.triangle.fill", color: Theme.danger,
                        text: "\(store.conflicts.count) edit\(store.conflicts.count == 1 ? "" : "s") conflict with changes on the Mac — tap to review",
                        chevron: true)
                }
                .buttonStyle(.plain)
            }
            if !store.unsent.isEmpty {
                row(icon: store.live ? "arrow.triangle.2.circlepath" : "wifi.slash", color: .orange,
                    text: store.live
                        ? "Sending \(store.unsent.count) edit\(store.unsent.count == 1 ? "" : "s")…"
                        : "Offline — \(store.unsent.count) edit\(store.unsent.count == 1 ? "" : "s") saved on this phone, will send when connected",
                    chevron: false)
            }
        }
    }

    private func row(icon: String, color: Color, text: String, chevron: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text).font(.footnote.weight(.semibold)).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if chevron { Image(systemName: "chevron.right") }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(color.opacity(0.15))
        .accessibilityElement(children: .combine)
    }
}

struct ConflictsView: View {
    @EnvironmentObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Someone changed these on the Mac while you were editing. Choose which version to keep.")
                        .font(.subheadline).foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(store.conflicts) { c in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(c.cueLabel) — \(c.columnName)").font(.headline).foregroundStyle(Theme.text)
                            versionBox(title: "ON THE MAC", text: c.conflictRemote ?? "")
                            versionBox(title: "YOUR EDIT", text: c.newValue, highlight: true)
                            HStack(spacing: 10) {
                                choice("Use Mac's", filled: false) { await store.resolve(c.id, keepMine: false) }
                                choice("Keep mine", filled: true) { await store.resolve(c.id, keepMine: true) }
                            }
                        }
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if store.conflicts.isEmpty {
                        Text("All resolved.").foregroundStyle(Theme.textMuted).padding(.top, 40)
                    }
                }
                .padding(12)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Review conflicts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.frame(minHeight: 44) } }
            .onChange(of: store.conflicts.isEmpty) { _, empty in if empty { dismiss() } }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private func versionBox(title: String, text: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.weight(.heavy)).foregroundStyle(highlight ? Theme.accent : Theme.textMuted)
            Text(text.isEmpty ? "(empty)" : text).font(.body).foregroundStyle(Theme.text)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func choice(_ title: String, filled: Bool, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                .background(filled ? Theme.accent : Theme.cardRaised, in: Capsule())
                .foregroundStyle(filled ? Theme.onAccent : Theme.text)
        }
        .buttonStyle(PressStyle())
    }
}
