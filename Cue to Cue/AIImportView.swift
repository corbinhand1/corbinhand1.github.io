//
//  AIImportView.swift
//  Cue to Cue
//
//  File ▸ New Cue Stack from Documents…: pick the run of show and client
//  document, pick a few of your own stacks as the style to copy, and Claude
//  writes a new stack. Nothing is added to the show until you review it and
//  choose Add to Show (and that is undoable).
//

import SwiftUI
import UniformTypeIdentifiers

/// One stack offered as a style example, from this show or another file.
struct StyleCandidate: Identifiable, Equatable {
    let id = UUID()
    var stack: CueStack
    /// File it came from, or nil for the open show.
    var sourceFile: String?
}

struct AIImportView: View {
    let currentStacks: [CueStack]
    let onAdd: (CueStack) -> Void
    let onClose: () -> Void

    private enum Phase: Equatable {
        case setup
        case working(cues: Int)
        case review(GeneratedCueStack)
    }

    fileprivate enum DocumentSlot: String, Identifiable {
        case runOfShow, client
        var id: String { rawValue }
        var title: String { self == .runOfShow ? "Run of Show" : "Client Document" }
        var plural: String { self == .runOfShow ? "Run of Show" : "Client Documents" }
    }

    private enum ColumnChoice: Hashable {
        case automatic
        case from(UUID)
    }

    @State private var phase: Phase = .setup
    @State private var runOfShow: [SourceDocument] = []
    @State private var clientDocuments: [SourceDocument] = []
    @State private var candidates: [StyleCandidate] = []
    @State private var selectedExamples: Set<UUID> = []
    @State private var columnChoice: ColumnChoice = .automatic
    @State private var stackName = ""
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var pasteSlot: DocumentSlot?
    @State private var workbookQueue: [PendingWorkbook] = []
    @State private var currentWorkbook: PendingWorkbook?
    @State private var showConsent = false
    @State private var task: Task<Void, Never>?

    @State private var hasKey = false
    @State private var keyDraft = ""
    @AppStorage("ai.consentGiven") private var consentGiven = false

    private let keyStore: AnthropicKeyStore = KeychainAnthropicKeyStore()

    init(currentStacks: [CueStack], onAdd: @escaping (CueStack) -> Void, onClose: @escaping () -> Void) {
        self.currentStacks = currentStacks
        self.onAdd = onAdd
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(systemImage: "sparkles",
                        title: "New Cue Stack from Documents",
                        subtitle: "Claude reads the run of show and client notes and writes a stack the way you write yours.",
                        tint: .purple)
            switch phase {
            case .setup:
                setupForm
            case .working(let cues):
                workingView(cues: cues)
            case .review(let result):
                reviewView(result)
            }
            footer
        }
        .frame(width: 680, height: 720)
        .onAppear(perform: prepare)
        .onDisappear { task?.cancel() }
        .sheet(item: $pasteSlot) { slot in
            PasteSourceSheet(title: slot.title) { document in
                add([document], to: slot)
                pasteSlot = nil
            } onCancel: {
                pasteSlot = nil
            }
        }
        .sheet(item: $currentWorkbook, onDismiss: showNextWorkbook) { workbook in
            SheetPicker(workbook: workbook) { chosen in
                add(chosen.map { SourceDocumentReader.document(fileName: workbook.fileName, sheet: $0) }, to: workbook.slot)
                currentWorkbook = nil
            } onCancel: {
                currentWorkbook = nil
            }
        }
        .alert("Send these documents to Anthropic?", isPresented: $showConsent) {
            Button("Send") {
                consentGiven = true
                generate()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To write the stack, Cue to Cue sends the run of show, the client document and the example stacks you picked to Anthropic's Claude API, using your API key. Under Anthropic's commercial terms, API data isn't used to train models. Only send documents your client allows you to share with a service like this.")
        }
    }

    // MARK: Setup

    private var setupForm: some View {
        Form {
            if !hasKey { apiKeySection }

            documentSection(.runOfShow, documents: runOfShow,
                            emptyText: "Add the producer\u{2019}s run of show. Several files or sheets are fine.")
            documentSection(.client, documents: clientDocuments,
                            emptyText: "Optional: scripts, speakers, graphics, music.",
                            footer: "Excel (.xlsx) files are read sheet by sheet. From Google Sheets, choose File \u{25B8} Download \u{25B8} Microsoft Excel, or paste a link to a sheet shared with \u{201C}Anyone with the link\u{201D}.")

            Section {
                TextField("Name", text: $stackName, prompt: Text("Named from the run of show"))
                Picker("Columns", selection: $columnChoice) {
                    Text("Match my examples").tag(ColumnChoice.automatic)
                    if !selectedCandidates.isEmpty {
                        Divider()
                        ForEach(selectedCandidates) { candidate in
                            Text("Same as \u{201C}\(candidate.stack.name.replacingOccurrences(of: "\n", with: " "))\u{201D}")
                                .tag(ColumnChoice.from(candidate.id))
                        }
                    }
                }
                TextField("Notes for Claude", text: $notes,
                          prompt: Text("e.g. Cue numbers start at 300. No D3 on this show."),
                          axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("New Stack")
            }

            styleSection

            if hasKey { apiKeySection }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var styleSection: some View {
        Section {
            if candidates.isEmpty {
                Text("This show has no cue stacks yet. Add stacks from an earlier show file so Claude can learn your style.")
                    .foregroundStyle(.secondary)
            }
            ForEach(candidates) { candidate in
                Toggle(isOn: exampleBinding(candidate.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.stack.name.replacingOccurrences(of: "\n", with: " "))
                        Text(exampleDetail(candidate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            Button {
                addStacksFromFile()
            } label: {
                Label("Add Stacks from Another Show File…", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.borderless)
        } header: {
            HStack {
                Text("Your Style")
                Spacer()
                Text("\(selectedExamples.count) of \(CueStyleExamples.maxStacks) picked")
                    .monospacedDigit()
                    .foregroundStyle(selectedExamples.count > CueStyleExamples.maxStacks ? .red : .secondary)
            }
        } footer: {
            Text("Claude copies the columns, numbering, wording and timer habits of the stacks you pick. Two to four shows like this one work best.")
        }
    }

    private func documentSection(_ slot: DocumentSlot, documents: [SourceDocument],
                                 emptyText: String, footer: String? = nil) -> some View {
        Section {
            if documents.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(documents.enumerated()), id: \.offset) { index, document in
                HStack(spacing: 12) {
                    Image(systemName: document.name.lowercased().hasSuffix(".xlsx") ? "tablecells.fill" : "doc.text.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(documentDetail(document))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        remove(at: index, from: slot)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(document.name)")
                    .accessibilityLabel(Text("Remove \(document.name)"))
                }
                .padding(.vertical, 2)
            }
            HStack(spacing: 14) {
                Button {
                    chooseFiles(for: slot)
                } label: {
                    Label("Add Files\u{2026}", systemImage: "plus")
                }
                Button {
                    pasteSlot = slot
                } label: {
                    Label("Paste Link or Text\u{2026}", systemImage: "link")
                }
            }
            .buttonStyle(.borderless)
        } header: {
            HStack {
                Text(slot.plural)
                if slot == .runOfShow && documents.isEmpty {
                    Text("Required").foregroundStyle(.secondary)
                }
            }
        } footer: {
            if let footer { Text(footer) }
        }
    }

    private var apiKeySection: some View {
        Section {
            if hasKey {
                LabeledContent("API key") {
                    HStack(spacing: 8) {
                        Label("Saved in Keychain", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Remove") {
                            try? keyStore.writeKey(nil)
                            hasKey = false
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("API key", text: $keyDraft, prompt: Text("Paste your key (sk-ant-…)"))
                        .frame(minWidth: 320)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Link("Get a key at console.anthropic.com", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.callout)
            }
        } header: {
            Text("Anthropic API Key")
        } footer: {
            Text("Uses Claude Opus 5.5 and is billed to your Anthropic account. If Claude declines a request, Anthropic retries it on a backup model automatically.")
        }
    }

    // MARK: Working

    private func workingView(cues: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(cues == 0 ? "Reading your documents…" : "Writing cue \(cues)…")
                .font(.title3.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("This usually takes a minute or two for a full keynote.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .combine)
    }

    // MARK: Review

    private func reviewView(_ result: GeneratedCueStack) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.stack.name.isEmpty ? "New Cue Stack" : result.stack.name)
                    .font(.headline)
                Spacer()
                Text("\(result.stack.cues.count) cues · \(result.stack.columns.count) columns")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            GeneratedStackPreview(stack: result.stack)
                .frame(maxHeight: .infinity)

            if !result.notes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("Check before the show", systemImage: "questionmark.bubble")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(result.notes.enumerated()), id: \.offset) { _, note in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(note).fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.callout)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    }
                    .frame(maxHeight: 120)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                switch phase {
                case .setup:
                    Label("Sent to Anthropic to generate", systemImage: "lock.shield")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", action: onClose)
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.large)
                    Button("Build Cue Stack") {
                        if consentGiven { generate() } else { showConsent = true }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canGenerate)
                case .working:
                    Spacer()
                    Button("Stop") {
                        task?.cancel()
                        phase = .setup
                    }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                case .review(let result):
                    Button("Back") { phase = .setup }
                        .controlSize(.large)
                    Button("Try Again") { generate() }
                        .controlSize(.large)
                    Spacer()
                    Button("Cancel", action: onClose)
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.large)
                    Button("Add to Show") {
                        onAdd(result.stack)
                        onClose()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(result.stack.cues.isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    // MARK: Logic

    private var selectedCandidates: [StyleCandidate] {
        candidates.filter { selectedExamples.contains($0.id) }
    }

    private var canGenerate: Bool {
        guard runOfShow.contains(where: { !$0.isEmpty }), hasKey else { return false }
        return selectedExamples.count <= CueStyleExamples.maxStacks
    }

    private func prepare() {
        hasKey = keyStore.readKey() != nil
        guard candidates.isEmpty else { return }
        candidates = currentStacks
            .filter { !$0.cues.isEmpty }
            .map { StyleCandidate(stack: $0, sourceFile: nil) }
        // Start with the three most recent stacks (the end of the list).
        selectedExamples = Set(candidates.suffix(3).map(\.id))
    }

    private func exampleBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedExamples.contains(id) },
            set: { isOn in
                if isOn { selectedExamples.insert(id) } else { selectedExamples.remove(id) }
                if case .from(let chosen) = columnChoice, !selectedExamples.contains(chosen) {
                    columnChoice = .automatic
                }
            }
        )
    }

    private func exampleDetail(_ candidate: StyleCandidate) -> String {
        let columns = candidate.stack.columns.map(\.name).joined(separator: ", ")
        let source = candidate.sourceFile.map { " · \($0)" } ?? ""
        return "\(candidate.stack.cues.count) cues · \(columns)\(source)"
    }

    private func documentDetail(_ document: SourceDocument) -> String {
        "\(document.text.split(separator: "\n").count) rows"
    }

    private func add(_ documents: [SourceDocument], to slot: DocumentSlot) {
        errorMessage = nil
        switch slot {
        case .runOfShow: runOfShow += documents
        case .client: clientDocuments += documents
        }
    }

    /// Workbooks with several tabs are asked about one at a time.
    private func showNextWorkbook() {
        guard currentWorkbook == nil, !workbookQueue.isEmpty else { return }
        currentWorkbook = workbookQueue.removeFirst()
    }

    private func remove(at index: Int, from slot: DocumentSlot) {
        switch slot {
        case .runOfShow: if runOfShow.indices.contains(index) { runOfShow.remove(at: index) }
        case .client: if clientDocuments.indices.contains(index) { clientDocuments.remove(at: index) }
        }
    }

    private func chooseFiles(for slot: DocumentSlot) {
        let panel = NSOpenPanel()
        panel.title = "Add \(slot.plural)"
        panel.prompt = "Add"
        panel.allowedContentTypes = SourceDocumentReader.readableExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var added: [SourceDocument] = []
        var problems: [String] = []
        for url in panel.urls {
            do {
                if url.pathExtension.lowercased() == "xlsx" {
                    let sheets = try SourceDocumentReader.sheets(fileURL: url)
                    if sheets.isEmpty {
                        problems.append("\u{201C}\(url.lastPathComponent)\u{201D} has no tabs with anything in them.")
                    } else if sheets.count == 1 {
                        added.append(SourceDocumentReader.document(fileName: url.lastPathComponent, sheet: sheets[0]))
                    } else {
                        // Several tabs: ask which ones hold the show.
                        workbookQueue.append(PendingWorkbook(fileName: url.lastPathComponent, sheets: sheets, slot: slot))
                    }
                    continue
                }
                let document = try SourceDocumentReader.read(fileURL: url)
                if document.isEmpty {
                    problems.append("\u{201C}\(url.lastPathComponent)\u{201D} is empty.")
                } else {
                    added.append(document)
                }
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        add(added, to: slot)
        errorMessage = problems.isEmpty ? nil : problems.joined(separator: "\n")
        if currentWorkbook == nil { showNextWorkbook() }
    }

    private func addStacksFromFile() {
        let panel = NSOpenPanel()
        panel.title = "Add Stacks from a Show File"
        panel.message = "Pick one or more earlier show files. They are only read, never changed."
        panel.prompt = "Add"
        panel.allowedContentTypes = UTType.cueStackReadableTypes
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var added: [StyleCandidate] = []
        var failed: [String] = []
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url),
                  let saved = try? JSONDecoder().decode(SavedData.self, from: data) else {
                failed.append(url.lastPathComponent)
                continue
            }
            let name = url.deletingPathExtension().lastPathComponent
            added += saved.cueStacks.filter { !$0.cues.isEmpty }.map { StyleCandidate(stack: $0, sourceFile: name) }
        }
        candidates += added
        errorMessage = failed.isEmpty ? nil : "Couldn't read \(failed.joined(separator: ", ")) as a Cue to Cue show file."
    }

    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try keyStore.writeKey(key)
            keyDraft = ""
            hasKey = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generate() {
        let examples = selectedCandidates.map(\.stack)
        var columns: [String] = []
        if case .from(let id) = columnChoice, let source = candidates.first(where: { $0.id == id }) {
            columns = source.stack.columns.map(\.name)
        }
        let request = CueStackGenerationRequest(runOfShow: runOfShow,
                                                clientDocuments: clientDocuments,
                                                examples: examples,
                                                columns: columns,
                                                stackName: stackName,
                                                notes: notes)
        errorMessage = nil
        phase = .working(cues: 0)
        task?.cancel()
        task = Task {
            do {
                let result = try await CueStackGenerator(keyStore: keyStore).generate(request) { count in
                    Task { @MainActor in
                        if case .working = phase { phase = .working(cues: count) }
                    }
                }
                await MainActor.run { phase = .review(result) }
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    phase = .setup
                }
            }
        }
    }
}

// MARK: - Preview table

/// Read-only look at the generated stack, laid out like the cue sheet.
private struct GeneratedStackPreview: View {
    let stack: CueStack

    private func width(_ column: Column) -> CGFloat { min(max(column.width, 50), 360) }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(stack.cues.enumerated()), id: \.element.id) { index, cue in
                        HStack(spacing: 0) {
                            ForEach(Array(stack.columns.enumerated()), id: \.element.id) { columnIndex, column in
                                Text(columnIndex < cue.values.count ? cue.values[columnIndex] : "")
                                    .lineLimit(2)
                                    .frame(width: width(column), alignment: .leading)
                                    .padding(.horizontal, 6)
                            }
                            Text(cue.timerValue)
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                                .frame(width: 60, alignment: .leading)
                                .padding(.horizontal, 6)
                        }
                        .font(.system(size: 12))
                        .padding(.vertical, 5)
                        .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
                    }
                } header: {
                    HStack(spacing: 0) {
                        ForEach(stack.columns) { column in
                            Text(column.name)
                                .frame(width: width(column), alignment: .leading)
                                .padding(.horizontal, 6)
                        }
                        Text("Timer")
                            .frame(width: 60, alignment: .leading)
                            .padding(.horizontal, 6)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .background(.bar)
                }
            }
            .padding(.horizontal, 14)
        }
        .textSelection(.enabled)
    }
}

// MARK: - Paste sheet

/// Paste a Google Sheets link (downloaded as CSV) or the text itself.
private struct PasteSourceSheet: View {
    let title: String
    let onDone: (SourceDocument) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @State private var isLoading = false
    @State private var error: String?

    private var isLink: Bool {
        SourceDocumentReader.csvExportURL(forSheetsLink: text) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste the \(title)")
                .font(.title3.weight(.semibold))
            Text("Paste a Google Sheets link, or copy the cells in Google Sheets and paste them here.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if isLink {
                    Label("Google Sheets link", systemImage: "link")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isLink ? "Download" : "Use Text", action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
        }
        .padding(20)
        .frame(width: 520)
        .overlay { if isLoading { ProgressView() } }
    }

    private func submit() {
        if isLink {
            isLoading = true
            error = nil
            let link = text
            Task {
                do {
                    let document = try await SourceDocumentReader.read(sheetsLink: link)
                    await MainActor.run { onDone(document) }
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                        isLoading = false
                    }
                }
            }
        } else {
            // Cells copied from Google Sheets arrive tab-separated.
            let ext = text.contains("\t") ? "tsv" : "txt"
            onDone(SourceDocument(name: "Pasted text", text: SourceDocumentReader.normalize(text, fileExtension: ext)))
        }
    }
}

// MARK: - Workbook tabs

private struct PendingWorkbook: Identifiable {
    let id = UUID()
    var fileName: String
    var sheets: [XLSXReader.Sheet]
    var slot: AIImportView.DocumentSlot
}

/// Which tabs of a workbook to send. Starts with the tabs that look like the show flow.
private struct SheetPicker: View {
    let workbook: PendingWorkbook
    let onDone: ([XLSXReader.Sheet]) -> Void
    let onCancel: () -> Void

    @State private var chosen: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which tabs should Claude read?")
                .font(.title3.weight(.semibold))
            Text(workbook.fileName)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Form {
                ForEach(workbook.sheets, id: \.name) { sheet in
                    Toggle(isOn: Binding(
                        get: { chosen.contains(sheet.name) },
                        set: { if $0 { chosen.insert(sheet.name) } else { chosen.remove(sheet.name) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sheet.name)
                            Text("\(sheet.rows.filter { !$0.isEmpty }.count) rows")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .formStyle(.grouped)
            .frame(height: min(CGFloat(workbook.sheets.count) * 52 + 30, 340))
            Text("Hidden tabs are skipped. Leave out templates and examples so Claude only reads this show.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(chosen.count > 1 ? "Add \(chosen.count) Tabs" : "Add Tab") {
                    onDone(workbook.sheets.filter { chosen.contains($0.name) })
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { chosen = SourceDocumentReader.likelyShowSheets(workbook.sheets) }
    }
}
