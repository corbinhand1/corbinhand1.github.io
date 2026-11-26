import SwiftUI

/// Jump straight to a demo (or any highlighted group) by number or name, or to a cue by its number.
struct JumpView: View {
    @EnvironmentObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let onJump: (String) -> Void

    @State private var query = ""
    @State private var ruleIndex = 0
    @FocusState private var focused: Bool

    private var sheet: Sheet? { store.sheet }
    private var rules: [HighlightRule] { sheet?.highlightColors ?? [] }
    private var groups: [CueGroup] { sheet.map { Jump.groups(sheet: $0, ruleIndex: ruleIndex) } ?? [] }
    private var result: Jump.Result {
        guard let sheet else { return .init(groups: [], cue: nil) }
        return Jump.search(query, groups: groups, sheet: sheet)
    }
    private var color: Color {
        rules.indices.contains(ruleIndex) ? .highlight(hex: rules[ruleIndex].color, darkMode: scheme == .dark) : Theme.accent
    }
    private var label: String { rules.indices.contains(ruleIndex) ? rules[ruleIndex].keyword.capitalized : "Group" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if query.isEmpty && !groups.isEmpty { quickButtons }
                        resultsList
                    }
                    .padding(12)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Jump to").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.frame(minHeight: 44) }
                if rules.count > 1 {
                    ToolbarItem(placement: .confirmationAction) {
                        Menu {
                            Picker("Group by", selection: $ruleIndex) {
                                ForEach(Array(rules.enumerated()), id: \.offset) { i, r in Text(r.keyword.capitalized).tag(i) }
                            }
                        } label: { Label(label, systemImage: "line.3.horizontal.decrease.circle").frame(minHeight: 44) }
                    }
                }
            }
            .onAppear {
                // Default to the "demo" group when the show has one, else the first highlight.
                ruleIndex = rules.firstIndex { $0.keyword.lowercased().contains("demo") } ?? 0
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Pieces

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "number").foregroundStyle(Theme.textMuted).accessibilityHidden(true)
            TextField("\(label) number or name, or cue #", text: $query)
                .focused($focused)
                .keyboardType(.numbersAndPunctuation)       // numbers first; switch to ABC for names
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { jumpToFirst() }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textMuted).frame(width: 44, height: 44) }
                    .accessibilityLabel("Clear")
            }
        }
        .font(.title3).padding(.leading, 14)
        .frame(minHeight: Theme.minTarget)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.7), lineWidth: 1.5))
        .padding(12)
    }

    /// One tap per group: the fastest path on stage.
    private var quickButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(label.uppercased())S").font(.caption.weight(.bold)).foregroundStyle(Theme.textMuted)
            FlowLayout(spacing: 8) {
                ForEach(groups) { g in
                    Button { go(g.firstCueID) } label: {
                        Text("\(g.number)").font(.title3.weight(.bold)).monospacedDigit()
                            .foregroundStyle(color)
                            .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.7), lineWidth: 1.5))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(label) \(g.number), \(g.name)")
                }
            }
        }
    }

    @ViewBuilder private var resultsList: some View {
        let r = result
        if let cue = r.cue {
            row(title: "Cue \(cue.values.first ?? "")",
                detail: When.stripped(sheet.map { $0.descriptionColumn < cue.values.count ? cue.values[$0.descriptionColumn] : "" } ?? ""),
                badge: "CUE", tint: Theme.accent) { go(cue.id) }
        }
        ForEach(r.groups) { g in
            row(title: "\(label) \(g.number) · \(g.name)",
                detail: "\(g.cueIDs.count) cue\(g.cueIDs.count == 1 ? "" : "s")" + (g.cueNumber.isEmpty ? "" : " · from cue \(g.cueNumber)"),
                badge: "\(g.number)", tint: color) { go(g.firstCueID) }
        }
        if r.groups.isEmpty && r.cue == nil {
            ContentUnavailableView(query.isEmpty ? "No \(label.lowercased())s found" : "No match",
                                   systemImage: "magnifyingglass",
                                   description: Text(query.isEmpty ? "This show has no cues with the “\(label.lowercased())” highlight." : "Try a number or part of a name."))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private func row(title: String, detail: String, badge: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(badge).font(.headline.monospacedDigit()).foregroundStyle(tint)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(tint).multilineTextAlignment(.leading)
                    if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(Theme.textMuted).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").foregroundStyle(Theme.textMuted).accessibilityHidden(true)
            }
            .padding(10).frame(maxWidth: .infinity, minHeight: Theme.minTarget, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressStyle())
    }

    private func jumpToFirst() {
        let r = result
        if let g = r.groups.first { go(g.firstCueID) } else if let c = r.cue { go(c.id) }
    }

    private func go(_ cueID: String) {
        Haptics.tap()
        dismiss()
        onJump(cueID)
    }
}
