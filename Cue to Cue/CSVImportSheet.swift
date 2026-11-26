//
//  CSVImportSheet.swift
//  Cue to Cue
//

import SwiftUI

enum CSVImportMode: String, CaseIterable, Identifiable {
    case importOneStack
    case addStacks
    case replaceAll
    case mergeIntoSelected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .importOneStack:
            return "Import One Stack"
        case .addStacks:
            return "Add All Stacks"
        case .replaceAll:
            return "Replace All Stacks"
        case .mergeIntoSelected:
            return "Merge into Selected Stack"
        }
    }

    var detail: String {
        switch self {
        case .importOneStack:
            return "Bring one stack from this CSV into the current document."
        case .addStacks:
            return "Append every stack from the CSV. Duplicate names are renamed automatically."
        case .replaceAll:
            return "Replace every stack in the current document with the imported stacks."
        case .mergeIntoSelected:
            return "Append cues from one imported stack into the currently selected stack."
        }
    }
}

struct CSVImportAction {
    enum Kind {
        case importOneStack(stackName: String)
        case addStacks
        case replaceAll
        case mergeIntoSelected(sourceStackName: String)
    }

    let kind: Kind
}

struct CSVImportSheet: View {
    let sourceName: String
    let importResult: CueCSVImportResult
    let targetStackName: String
    let canMergeIntoSelected: Bool
    let onImport: (CSVImportAction) -> Void
    let onCancel: () -> Void

    @State private var mode: CSVImportMode
    @State private var selectedStackName: String

    private var stackCount: Int { importResult.stacks.count }
    private var cueCount: Int { importResult.stacks.reduce(0) { $0 + $1.cues.count } }
    private var selectedStack: CueStack? {
        importResult.stacks.first(where: { $0.name == selectedStackName }) ?? importResult.stacks.first
    }
    private var availableModes: [CSVImportMode] {
        CSVImportMode.allCases.filter { option in
            option != .mergeIntoSelected || canMergeIntoSelected
        }
    }

    init(
        sourceName: String,
        importResult: CueCSVImportResult,
        targetStackName: String,
        canMergeIntoSelected: Bool,
        onImport: @escaping (CSVImportAction) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceName = sourceName
        self.importResult = importResult
        self.targetStackName = targetStackName
        self.canMergeIntoSelected = canMergeIntoSelected
        self.onImport = onImport
        self.onCancel = onCancel

        _mode = State(initialValue: .importOneStack)
        _selectedStackName = State(initialValue: importResult.stacks.first?.name ?? "")
    }

    private let contentHeight: CGFloat = 380

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                summarySection

                HStack(alignment: .top, spacing: 16) {
                    modeColumn
                        .frame(width: 320, height: contentHeight, alignment: .topLeading)
                    stackBrowserColumn
                        .frame(maxWidth: .infinity)
                        .frame(height: contentHeight, alignment: .topLeading)
                }

                if !importResult.warnings.isEmpty {
                    warningsSection
                }
            }
            .padding(20)

            Spacer(minLength: 0)

            Divider()
            footer
        }
        .frame(width: 920, height: 680)
        .onChange(of: mode) { _, newMode in
            if newMode == .mergeIntoSelected, !canMergeIntoSelected {
                mode = .importOneStack
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import CSV")
                    .font(.headline)
                Text(sourceName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .accessibilityLabel(Text("Close"))
                    .help("Close")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var summarySection: some View {
        HStack(spacing: 20) {
            summaryStat(title: "Stacks in file", value: "\(stackCount)")
            summaryStat(title: "Cues", value: "\(cueCount)")
            if canMergeIntoSelected {
                summaryStat(title: "Current stack", value: targetStackName)
            }
            Spacer()
            Text(modeSummary)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 280, alignment: .trailing)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .cornerRadius(10)
    }

    private func summaryStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(1)
        }
    }

    private var modeColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Import Action")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                ForEach(availableModes) { option in
                    modeRow(option)
                }
            }
        }
    }

    private func modeRow(_ option: CSVImportMode) -> some View {
        Button {
            mode = option
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: mode == option ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(.accentColor)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.body)
                        .fontWeight(mode == option ? .semibold : .regular)
                    Text(option.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(mode == option ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.35))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(mode == option ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var stackBrowserColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Stacks in CSV")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(stackBrowserHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(importResult.stacks) { stack in
                            stackRow(stack)

                            if stack.id != importResult.stacks.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

                selectedStackDetail
                    .frame(width: 250, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func stackRow(_ stack: CueStack) -> some View {
        Button {
            selectedStackName = stack.name
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedStackName == stack.name ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedStackName == stack.name ? .accentColor : .secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(stack.name)
                        .font(.body)
                        .fontWeight(selectedStackName == stack.name ? .semibold : .regular)
                    Text("\(stack.cues.count) cue\(stack.cues.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !stack.columns.isEmpty {
                        Text(stack.columns.map(\.name).joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selectedStackName == stack.name ? Color.accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var selectedStackDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected Stack")
                .font(.caption)
                .foregroundColor(.secondary)

            if let selectedStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedStack.name)
                        .font(.headline)
                        .lineLimit(2)

                    HStack(spacing: 16) {
                        detailStat(title: "Cues", value: "\(selectedStack.cues.count)")
                        detailStat(title: "Columns", value: "\(selectedStack.columns.count)")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Columns")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(selectedStack.columns.isEmpty ? "No columns" : selectedStack.columns.map(\.name).joined(separator: ", "))
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let firstCue = selectedStack.cues.first {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("First cue")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(firstCue.values.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? "Empty cue")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text(selectionHelpText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            } else {
                Text("No stack available.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func detailStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .fontWeight(.medium)
        }
    }

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(importResult.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
    }

    private var footer: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button(importButtonTitle, action: confirmImport)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedStack == nil)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var importButtonTitle: String {
        switch mode {
        case .importOneStack:
            if let stack = importResult.stacks.first(where: { $0.name == selectedStackName }) {
                return "Import \"\(stack.name)\""
            }
            return "Import Stack"
        case .addStacks:
            return stackCount == 1 ? "Add Stack" : "Add \(stackCount) Stacks"
        case .replaceAll:
            return "Replace All Stacks"
        case .mergeIntoSelected:
            return "Merge Cues"
        }
    }

    private var modeSummary: String {
        switch mode {
        case .importOneStack:
            return "Choose one stack from the CSV and add it to the current document."
        case .addStacks:
            return "Every stack shown on the right will be added to the current document."
        case .replaceAll:
            return "Every stack shown on the right will replace the current document."
        case .mergeIntoSelected:
            return "Select one imported stack to append its cues into \"\(targetStackName)\"."
        }
    }

    private var stackBrowserHint: String {
        switch mode {
        case .importOneStack:
            return "Click a stack to import it"
        case .addStacks:
            return "Preview all stacks being added"
        case .replaceAll:
            return "Preview all stacks replacing the document"
        case .mergeIntoSelected:
            return "Click a stack to merge from"
        }
    }

    private var selectionHelpText: String {
        switch mode {
        case .importOneStack:
            return "This stack will be added as its own cue stack."
        case .addStacks:
            return "This is a preview only. Add All Stacks imports the full CSV."
        case .replaceAll:
            return "This is a preview only. Replace All Stacks imports the full CSV."
        case .mergeIntoSelected:
            return "The cues from this stack will be appended to \"\(targetStackName)\"."
        }
    }

    private func confirmImport() {
        switch mode {
        case .importOneStack:
            onImport(CSVImportAction(kind: .importOneStack(stackName: selectedStackName)))
        case .addStacks:
            onImport(CSVImportAction(kind: .addStacks))
        case .replaceAll:
            onImport(CSVImportAction(kind: .replaceAll))
        case .mergeIntoSelected:
            onImport(CSVImportAction(kind: .mergeIntoSelected(sourceStackName: selectedStackName)))
        }
    }
}
