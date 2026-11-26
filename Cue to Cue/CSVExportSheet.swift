//
//  CSVExportSheet.swift
//  Cue to Cue
//

import SwiftUI

struct CSVExportSheet: View {
    @Binding var selectedIndices: Set<Int>
    let cueStacks: [CueStack]
    let sourceDocumentName: String
    let onExport: () -> Void
    let onCancel: () -> Void

    private var selectedStackCount: Int { selectedIndices.count }
    private var selectedCueCount: Int {
        selectedIndices.reduce(0) { total, index in
            guard cueStacks.indices.contains(index) else { return total }
            return total + cueStacks[index].cues.count
        }
    }
    private var primarySelectedIndex: Int? {
        selectedIndices.sorted().first ?? cueStacks.indices.first
    }
    private var selectedStack: CueStack? {
        guard let index = primarySelectedIndex, cueStacks.indices.contains(index) else { return nil }
        return cueStacks[index]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                summarySection

                HStack(alignment: .top, spacing: 16) {
                    exportOptionsColumn
                    stackBrowserColumn
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            footer
        }
        .frame(minWidth: 860, idealWidth: 920, minHeight: 620, idealHeight: 680)
        .onAppear {
            if selectedIndices.isEmpty {
                selectedIndices = Set(cueStacks.indices)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export CSV")
                    .font(.headline)
                Text(sourceDocumentName)
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
            summaryStat(title: "Selected stacks", value: "\(selectedStackCount) of \(cueStacks.count)")
            summaryStat(title: "Cues", value: "\(selectedCueCount)")
            Spacer()
            Text(exportSummary)
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
        }
    }

    private var exportOptionsColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export Options")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                exportOptionCard(
                    title: "Export Selected Stacks",
                    detail: "Choose exactly which cue stacks go into the CSV file."
                )

                exportOptionCard(
                    title: "Quick Selection",
                    detail: "Use Select All or Deselect All, then click stacks on the right to fine-tune."
                )

                exportOptionCard(
                    title: "Single-Stack Export",
                    detail: "Leave one stack selected to create a CSV you can move into another show."
                )
            }

            Spacer(minLength: 0)
        }
        .frame(width: 320, alignment: .topLeading)
    }

    private func exportOptionCard(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.accentColor)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private var stackBrowserColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cue Stacks")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Toggle the stacks to include in the CSV")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Select All") {
                    selectedIndices = Set(cueStacks.indices)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                Button("Deselect All") {
                    selectedIndices.removeAll()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            HStack(alignment: .top, spacing: 12) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(cueStacks.indices, id: \.self) { index in
                            let stack = cueStacks[index]
                            stackRow(stack, at: index)

                            if index != cueStacks.indices.last {
                                Divider()
                            }
                        }
                    }
                }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stackRow(_ stack: CueStack, at index: Int) -> some View {
        Toggle(isOn: Binding(
            get: { selectedIndices.contains(index) },
            set: { isSelected in
                if isSelected {
                    selectedIndices.insert(index)
                } else {
                    selectedIndices.remove(index)
                }
            }
        )) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stack.name)
                        .font(.body)
                        .fontWeight(selectedIndices.contains(index) ? .semibold : .regular)
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
            .padding(.vertical, 2)
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(selectedIndices.contains(index) ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }

    private var selectedStackDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Primary Selection")
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
                Text("Select at least one stack to export.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
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

    private var footer: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button(exportButtonTitle, action: onExport)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedIndices.isEmpty)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var exportButtonTitle: String {
        switch selectedStackCount {
        case 0:
            return "Export"
        case 1:
            return "Export 1 Stack"
        default:
            return "Export \(selectedStackCount) Stacks"
        }
    }

    private var exportSummary: String {
        if selectedStackCount == 0 {
            return "Choose one or more cue stacks to include in the CSV export."
        }
        if selectedStackCount == 1, let selectedStack {
            return "\"\(selectedStack.name)\" will be exported as a single-stack CSV."
        }
        return "\(selectedStackCount) stacks will be bundled into one CSV export."
    }

    private var selectionHelpText: String {
        if selectedStackCount == 1 {
            return "Only this stack is selected, so the exported CSV can be imported into another show as a single stack."
        }
        return "This panel shows the first selected stack. The export will include every checked stack in the list."
    }
}
