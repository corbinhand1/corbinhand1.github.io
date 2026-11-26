//
//  FindReplaceView.swift
//  Cue to Cue
//
//  Edit ▸ Find and Replace… (⌥⌘F). Two ways to say what should change:
//  Smart — plain English ("change all references to preset 29 to preset
//  25"), which Claude turns into exact cell edits — or Exact text. Either
//  way you see every change, untick any you don't want, and Apply is one
//  undoable step.
//

import SwiftUI

// MARK: - Model

/// One proposed change to one cell (column -1 is the timer).
struct CueEdit: Identifiable, Equatable {
    let id = UUID()
    var stackID: UUID
    var cueID: UUID
    var column: Int
    var columnName: String
    var stackName: String
    var cueLabel: String
    var oldText: String
    var newText: String
}

enum CueFindReplace {
    static let timerColumn = -1

    static func cell(_ cue: Cue, _ column: Int) -> String {
        column == timerColumn ? cue.timerValue : (column < cue.values.count ? cue.values[column] : "")
    }

    /// A short label for the cue in previews: its number, else its row.
    static func label(for cue: Cue, at row: Int) -> String {
        let number = cue.values.first?.trimmingCharacters(in: .whitespaces) ?? ""
        return number.isEmpty ? "Row \(row + 1)" : "Cue \(number)"
    }

    // MARK: Exact text

    static func literal(find: String, replace: String, matchCase: Bool, wholeWord: Bool,
                        in stacks: [CueStack], scope: Set<UUID>) -> [CueEdit] {
        guard !find.isEmpty else { return [] }
        var pattern = NSRegularExpression.escapedPattern(for: find)
        if wholeWord { pattern = "(?<![\\p{L}\\p{N}])" + pattern + "(?![\\p{L}\\p{N}])" }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: matchCase ? [] : [.caseInsensitive]) else { return [] }
        let template = NSRegularExpression.escapedTemplate(for: replace)

        var edits: [CueEdit] = []
        for stack in stacks where scope.contains(stack.id) {
            for (row, cue) in stack.cues.enumerated() {
                for column in Array(stack.columns.indices) + [timerColumn] {
                    let old = cell(cue, column)
                    let range = NSRange(old.startIndex..., in: old)
                    guard regex.firstMatch(in: old, range: range) != nil else { continue }
                    let new = regex.stringByReplacingMatches(in: old, range: range, withTemplate: template)
                    guard new != old else { continue }
                    edits.append(CueEdit(stackID: stack.id, cueID: cue.id, column: column,
                                         columnName: column == timerColumn ? "Timer" : stack.columns[column].name,
                                         stackName: stack.name, cueLabel: label(for: cue, at: row),
                                         oldText: old, newText: new))
                }
            }
        }
        return edits
    }

    // MARK: Apply

    /// Applies edits whose cell still holds the text that was previewed.
    @discardableResult
    static func apply(_ edits: [CueEdit], to stacks: inout [CueStack]) -> Int {
        var applied = 0
        for edit in edits {
            guard let s = stacks.firstIndex(where: { $0.id == edit.stackID }),
                  let c = stacks[s].cues.firstIndex(where: { $0.id == edit.cueID }),
                  cell(stacks[s].cues[c], edit.column) == edit.oldText else { continue }
            if edit.column == timerColumn {
                stacks[s].cues[c].timerValue = edit.newText
            } else {
                guard edit.column < stacks[s].columns.count else { continue }
                while stacks[s].cues[c].values.count <= edit.column { stacks[s].cues[c].values.append("") }
                stacks[s].cues[c].values[edit.column] = edit.newText
            }
            applied += 1
        }
        return applied
    }

    // MARK: Smart (Claude)

    struct SmartRequest {
        var body: [String: Any]
        /// "R12" → (stack, cue)
        var refs: [String: (stack: UUID, cue: UUID)]
    }

    static let smartInstructions = """
    You edit cue stacks for a live-event show caller. Each stack is a table; \
    every row has a ref (R1, R2, …) and a Timer column.

    Carry out the show caller's instruction across the stacks shown. Return \
    every cell that must change, with the cell's complete new text. Change \
    only what the instruction asks: keep the rest of each cell exactly as it \
    is (other words, spacing, punctuation, capitalization habits).

    Read references the way a show caller means them. "Preset 29" covers \
    "Preset 29", "preset 29 & FLS", "P29" and a Preset column holding 29, \
    but not cue number 29, a time like 2:29, or preset 290. Keep the \
    original style when replacing (if a cell says "P29", write "P25"). If an \
    instruction is ambiguous for a cell, leave that cell alone and mention it \
    in the summary.

    summary is one or two plain sentences on what you changed and anything \
    you deliberately left alone. If nothing matches, return no edits and say so.
    """

    static let smartSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["summary", "edits"],
        "properties": [
            "summary": ["type": "string"],
            "edits": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["ref", "column", "newText"],
                    "properties": [
                        "ref": ["type": "string"],
                        "column": ["type": "string"],
                        "newText": ["type": "string"],
                    ],
                ],
            ],
        ],
    ]

    static func smartRequest(instruction: String, stacks: [CueStack], scope: Set<UUID>) -> SmartRequest {
        var refs: [String: (UUID, UUID)] = [:]
        var blocks: [String] = []
        var counter = 0
        for stack in stacks where scope.contains(stack.id) {
            let columns = stack.columns.map(\.name) + ["Timer"]
            var lines = ["<stack name=\"\(stack.name.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " "))\">",
                         "Ref | " + columns.joined(separator: " | ")]
            for cue in stack.cues {
                counter += 1
                let ref = "R\(counter)"
                refs[ref] = (stack.id, cue.id)
                let cells = (Array(stack.columns.indices) + [timerColumn]).map {
                    cell(cue, $0).replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "|", with: "¦")
                }
                lines.append(ref + " | " + cells.joined(separator: " | "))
            }
            lines.append("</stack>")
            blocks.append(lines.joined(separator: "\n"))
        }
        let body: [String: Any] = [
            "model": CueStackGenerationRequest.model,
            "max_tokens": 16000,
            "stream": true,
            "fallbacks": "default",
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": smartSchema],
            ],
            "system": [
                ["type": "text", "text": smartInstructions],
                // Stacks are cached so a second instruction on the same show is cheaper.
                ["type": "text", "text": blocks.joined(separator: "\n\n"), "cache_control": ["type": "ephemeral"]],
            ],
            "messages": [["role": "user", "content": "Instruction: \(instruction)"]],
        ]
        return SmartRequest(body: body, refs: refs)
    }

    struct SmartAnswer: Decodable {
        struct Edit: Decodable { var ref: String; var column: String; var newText: String }
        var summary: String
        var edits: [Edit]
    }

    /// Turns Claude's answer into edits, dropping anything that doesn't
    /// point at a real cell or doesn't actually change it.
    static func edits(from answer: SmartAnswer, refs: [String: (stack: UUID, cue: UUID)],
                      stacks: [CueStack]) -> [CueEdit] {
        var result: [CueEdit] = []
        var seen = Set<String>()
        for edit in answer.edits {
            guard let target = refs[edit.ref.trimmingCharacters(in: .whitespaces)],
                  let stack = stacks.first(where: { $0.id == target.stack }),
                  let row = stack.cues.firstIndex(where: { $0.id == target.cue }) else { continue }
            let wanted = edit.column.trimmingCharacters(in: .whitespaces).lowercased()
            let column: Int
            if wanted == "timer" {
                column = timerColumn
            } else if let index = stack.columns.firstIndex(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == wanted }) {
                column = index
            } else {
                continue
            }
            let cue = stack.cues[row]
            let old = cell(cue, column)
            let new = edit.newText.replacingOccurrences(of: "⏎", with: "\n").replacingOccurrences(of: "¦", with: "|")
            guard new != old, seen.insert("\(cue.id)-\(column)").inserted else { continue }
            result.append(CueEdit(stackID: stack.id, cueID: cue.id, column: column,
                                  columnName: column == timerColumn ? "Timer" : stack.columns[column].name,
                                  stackName: stack.name, cueLabel: label(for: cue, at: row),
                                  oldText: old, newText: new))
        }
        return result
    }

    static func smartEdits(instruction: String, stacks: [CueStack], scope: Set<UUID>,
                           generator: CueStackGenerator) async throws -> (edits: [CueEdit], summary: String) {
        let request = smartRequest(instruction: instruction, stacks: stacks, scope: scope)
        let stream = try await generator.send(body: request.body)
        if let error = stream.error { throw error }
        switch stream.stopReason {
        case "refusal": throw CueStackGenerationError.refused
        case "max_tokens": throw CueStackGenerationError.badResponse("too many changes for one pass; narrow the instruction or pick one stack")
        case nil: throw CueStackGenerationError.badResponse("the answer ended early")
        default: break
        }
        guard let data = stream.text.data(using: .utf8),
              let answer = try? JSONDecoder().decode(SmartAnswer.self, from: data) else {
            throw CueStackGenerationError.badResponse("not valid JSON")
        }
        return (edits(from: answer, refs: request.refs, stacks: stacks), answer.summary)
    }
}

// MARK: - View

struct FindReplaceView: View {
    let stacks: [CueStack]
    let selectedStackIndex: Int
    /// Returns how many changes were applied.
    let onApply: ([CueEdit]) -> Int
    let onClose: () -> Void

    private enum Mode: String, CaseIterable, Identifiable {
        case smart = "Smart", exact = "Exact Text"
        var id: String { rawValue }
    }

    private enum Scope: Hashable { case current, all }

    @AppStorage("findReplace.mode") private var modeRaw = Mode.smart.rawValue
    @State private var scope: Scope = .all
    @State private var instruction = ""
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var matchCase = false
    @State private var wholeWord = true

    @State private var edits: [CueEdit] = []
    @State private var included: Set<UUID> = []
    @State private var summary: String?
    @State private var hasSearched = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?
    @AppStorage("ai.consentGiven") private var consentGiven = false
    @State private var showConsent = false

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .smart }
    private let keyStore: AnthropicKeyStore = KeychainAnthropicKeyStore()

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(systemImage: "text.magnifyingglass",
                        title: "Find and Replace",
                        subtitle: "Say what should change, check every edit, then apply. Undo puts it all back.",
                        tint: .orange)
            Form {
                Section {
                    Picker("Mode", selection: $modeRaw) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: modeRaw) { _, _ in reset() }

                    if mode == .smart {
                        TextField("What should change?", text: $instruction,
                                  prompt: Text("e.g. change all references to preset 29 to preset 25"),
                                  axis: .vertical)
                            .lineLimit(2...4)
                            .onSubmit(search)
                    } else {
                        TextField("Find", text: $findText)
                            .onSubmit(search)
                        TextField("Replace with", text: $replaceText)
                            .onSubmit(search)
                        Toggle("Match case", isOn: $matchCase)
                        Toggle("Whole words only", isOn: $wholeWord)
                    }
                    Picker("Look in", selection: $scope) {
                        Text("All cue stacks").tag(Scope.all)
                        Text("This cue stack").tag(Scope.current)
                    }
                } footer: {
                    if mode == .smart {
                        Text("Claude reads the stacks and finds every way you wrote it: \u{201C}Preset 29\u{201D}, \u{201C}P29\u{201D}, a 29 in the Preset column, but not cue 29. The cue sheet is sent to Anthropic with your API key.")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if hasSearched && !isWorking { resultsSection }
            }
            .formStyle(.grouped)
            .overlay {
                if isWorking {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.large)
                        Text("Reading your cue sheet…").foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            footer
        }
        .frame(width: 640, height: 640)
        .onDisappear { task?.cancel() }
        .alert("Send this cue sheet to Anthropic?", isPresented: $showConsent) {
            Button("Send") { consentGiven = true; search() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Smart mode sends the cue stacks you're searching to Anthropic's Claude API, using your API key. Under Anthropic's commercial terms, API data isn't used to train models.")
        }
    }

    // MARK: Results

    private var resultsSection: some View {
        Section {
            if edits.isEmpty {
                Text(mode == .smart ? "No changes needed." : "No matches.")
                    .foregroundStyle(.secondary)
            }
            ForEach(edits) { edit in
                Toggle(isOn: Binding(
                    get: { included.contains(edit.id) },
                    set: { if $0 { included.insert(edit.id) } else { included.remove(edit.id) } }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(location(edit))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(edit.oldText.isEmpty ? "(empty)" : edit.oldText)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        Text(edit.newText.isEmpty ? "(empty)" : edit.newText)
                            .fontWeight(.medium)
                    }
                    .textSelection(.enabled)
                }
                .toggleStyle(.checkbox)
            }
        } header: {
            HStack {
                Text(edits.isEmpty ? "Changes" : "\(edits.count) Change\(edits.count == 1 ? "" : "s")")
                Spacer()
                if edits.count > 1 {
                    Button(included.count == edits.count ? "Select None" : "Select All") {
                        included = included.count == edits.count ? [] : Set(edits.map(\.id))
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
            }
        } footer: {
            if let summary, !summary.isEmpty { Text(summary) }
        }
    }

    private func location(_ edit: CueEdit) -> String {
        let stackPart = scope == .all ? edit.stackName.replacingOccurrences(of: "\n", with: " ") + " \u{00B7} " : ""
        return stackPart + edit.cueLabel + " \u{00B7} " + edit.columnName
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Button("Cancel") {
                    task?.cancel()
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
                Spacer()
                Button(mode == .smart ? "Find Changes" : "Find") { search() }
                    .controlSize(.large)
                    .disabled(!canSearch || isWorking)
                Button(included.isEmpty ? "Apply" : "Apply \(included.count) Change\(included.count == 1 ? "" : "s")") {
                    let chosen = edits.filter { included.contains($0.id) }
                    _ = onApply(chosen)
                    onClose()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(included.isEmpty || isWorking)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    // MARK: Logic

    private var scopeIDs: Set<UUID> {
        switch scope {
        case .all: return Set(stacks.map(\.id))
        case .current:
            return stacks.indices.contains(selectedStackIndex) ? [stacks[selectedStackIndex].id] : []
        }
    }

    private var canSearch: Bool {
        mode == .smart ? !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : !findText.isEmpty
    }

    private func reset() {
        edits = []
        included = []
        summary = nil
        hasSearched = false
        errorMessage = nil
    }

    private func show(_ found: [CueEdit], summary: String?) {
        edits = found
        included = Set(found.map(\.id))
        self.summary = summary
        hasSearched = true
    }

    private func search() {
        guard canSearch, !isWorking else { return }
        reset()
        if mode == .exact {
            show(CueFindReplace.literal(find: findText, replace: replaceText, matchCase: matchCase,
                                        wholeWord: wholeWord, in: stacks, scope: scopeIDs), summary: nil)
            return
        }
        guard keyStore.readKey() != nil else {
            errorMessage = "Smart mode needs your Anthropic API key. Add it in File \u{25B8} New Cue Stack from Documents\u{2026}, or use Exact Text."
            return
        }
        guard consentGiven else { showConsent = true; return }
        isWorking = true
        let instruction = instruction
        let stacks = stacks
        let scopeIDs = scopeIDs
        task = Task {
            do {
                let result = try await CueFindReplace.smartEdits(instruction: instruction, stacks: stacks, scope: scopeIDs,
                                                                 generator: CueStackGenerator(keyStore: keyStore))
                await MainActor.run {
                    isWorking = false
                    show(result.edits, summary: result.summary)
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                await MainActor.run {
                    isWorking = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
