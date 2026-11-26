//
//  DemoJumpBar.swift
//  Cue to Cue
//
//  One-click buttons in the bottom bar for every demo (or any other
//  highlighted group) in the current cue stack. They build themselves from
//  the highlight keywords in Settings, the same way the iPhone remote's
//  Jump sheet does.
//

import SwiftUI

/// A run of consecutive cues that share one highlight rule, e.g. one demo.
struct CueJumpGroup: Identifiable, Equatable {
    let number: Int              // 1-based position among groups of this rule
    let cueIndices: [Int]
    let name: String             // "Cars 1"
    let cueNumber: String        // the show's cue number where the group starts
    var id: Int { number }
    var firstIndex: Int { cueIndices[0] }
    /// First word of the name, for the button: "Adecco 1 & Mac 1" -> "Adecco".
    var shortName: String {
        let word = name.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        return word.trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "&")))
    }
}

enum CueJumpGroups {
    /// Same rule as the cue colors: a cue takes the first highlight whose keyword appears in any cell.
    static func ruleIndex(for cue: Cue, rules: [HighlightColorSetting]) -> Int? {
        for (i, rule) in rules.enumerated() where !rule.keyword.isEmpty {
            let k = rule.keyword.lowercased()
            if cue.values.contains(where: { $0.lowercased().contains(k) }) { return i }
        }
        return nil
    }

    static func descriptionColumn(_ columns: [Column]) -> Int {
        columns.firstIndex { $0.name.lowercased().contains("description") } ?? min(1, max(columns.count - 1, 0))
    }

    /// Consecutive cues matching `ruleIndex`, in show order. Struck-through cues
    /// don't break a run, but a run made only of struck cues is left out.
    static func groups(stack: CueStack, rules: [HighlightColorSetting], ruleIndex: Int) -> [CueJumpGroup] {
        guard rules.indices.contains(ruleIndex) else { return [] }
        let keyword = rules[ruleIndex].keyword
        let descCol = descriptionColumn(stack.columns)
        var groups: [CueJumpGroup] = []
        var run: [Int] = []
        var startNumber = ""
        var lastNumber = ""

        func flush() {
            guard let first = run.first else { return }
            defer { run = [] }
            guard run.contains(where: { !stack.cues[$0].isStruckThrough }) else { return }
            let own = run.lazy.map { stack.cues[$0].values.first ?? "" }.first { !$0.isEmpty } ?? ""
            groups.append(CueJumpGroup(number: groups.count + 1, cueIndices: run,
                                       name: name(for: stack.cues[first], descCol: descCol, keyword: keyword),
                                       cueNumber: own.isEmpty ? startNumber : own))
        }

        for (i, cue) in stack.cues.enumerated() {
            if Self.ruleIndex(for: cue, rules: rules) == ruleIndex {
                if run.isEmpty { startNumber = lastNumber }
                run.append(i)
            } else if !run.isEmpty {
                flush()
            }
            if let n = cue.values.first, !n.isEmpty { lastNumber = n }
        }
        flush()
        return groups
    }

    /// "DEMO: Cars 1 [when]" -> "Cars 1".
    static func name(for cue: Cue, descCol: Int, keyword: String) -> String {
        var text = descCol < cue.values.count ? cue.values[descCol] : ""
        if let r = text.range(of: #"\[[^\]]*\]\s*$"#, options: .regularExpression) { text.removeSubrange(r) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = text.range(of: keyword, options: [.caseInsensitive, .anchored]) {
            text.removeSubrange(r)
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: ":-–—#").union(.whitespaces))
        }
        return text
    }

    /// The highlight to group by: the saved choice, else one named "demo", else
    /// the first highlight that has any groups in this stack.
    static func defaultRule(stack: CueStack, rules: [HighlightColorSetting], saved: String) -> Int? {
        let withGroups = rules.indices.filter { !groups(stack: stack, rules: rules, ruleIndex: $0).isEmpty }
        if let i = withGroups.first(where: { rules[$0].keyword.lowercased() == saved.lowercased() }) { return i }
        if let i = withGroups.first(where: { rules[$0].keyword.lowercased().contains("demo") }) { return i }
        return withGroups.first
    }
}

/// The row of jump buttons. Hidden when the stack has no highlighted groups.
struct DemoJumpBar: View {
    let cueStack: CueStack
    let rules: [HighlightColorSetting]
    let selectedCueIndex: Int?
    let onJump: (Int) -> Void

    @AppStorage("jumpBar.ruleKeyword") private var savedKeyword = "demo"

    private var ruleIndex: Int? { CueJumpGroups.defaultRule(stack: cueStack, rules: rules, saved: savedKeyword) }
    private var groups: [CueJumpGroup] {
        ruleIndex.map { CueJumpGroups.groups(stack: cueStack, rules: rules, ruleIndex: $0) } ?? []
    }
    private var rulesWithGroups: [Int] {
        rules.indices.filter { !CueJumpGroups.groups(stack: cueStack, rules: rules, ruleIndex: $0).isEmpty }
    }
    private var label: String {
        guard let i = ruleIndex else { return "Groups" }
        return rules[i].keyword.capitalized
    }
    private var color: Color { ruleIndex.map { rules[$0].color } ?? .white }
    /// The group the selected cue is in, or the last one before it.
    private var currentGroup: Int? {
        guard let sel = selectedCueIndex else { return nil }
        return groups.last { $0.firstIndex <= sel }?.number
    }

    var body: some View {
        let groups = groups
        if !groups.isEmpty {
            HStack(spacing: 8) {
                groupPicker
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(groups) { g in chip(g).id(g.number) }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: currentGroup) { _, n in
                        guard let n else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(n, anchor: .center) }
                    }
                }
            }
            .frame(minWidth: 120)
        }
    }

    /// Label for the row; a menu to switch highlights when more than one has groups.
    @ViewBuilder private var groupPicker: some View {
        let options = rulesWithGroups
        let title = Text(label.uppercased() + "S")
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundColor(.white.opacity(0.55))
        if options.count > 1 {
            Menu {
                ForEach(options, id: \.self) { i in
                    Button {
                        savedKeyword = rules[i].keyword
                    } label: {
                        if i == ruleIndex { Label(rules[i].keyword.capitalized, systemImage: "checkmark") }
                        else { Text(rules[i].keyword.capitalized) }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    title
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.55))
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Choose which highlight these buttons jump to")
        } else {
            title.fixedSize()
        }
    }

    private func chip(_ g: CueJumpGroup) -> some View {
        let isCurrent = g.number == currentGroup
        let title = g.name.isEmpty ? "\(label) \(g.number)" : g.name
        return Button { onJump(g.firstIndex) } label: {
            HStack(spacing: 5) {
                Text("\(g.number)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                if !g.shortName.isEmpty {
                    Text(g.shortName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 120, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundColor(isCurrent ? .black : color)
            .padding(.horizontal, 10)
            .frame(minWidth: 32, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrent ? color : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(isCurrent ? 0 : 0.6), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(DigitShortcut(number: g.number))
        .help(helpText(g, title: title))
        .accessibilityLabel("Go to \(label) \(g.number)" + (g.name.isEmpty ? "" : ", \(g.name)"))
    }

    private func helpText(_ g: CueJumpGroup, title: String) -> String {
        var s = "Go to \(label) \(g.number)"
        if !g.name.isEmpty { s += ": \(g.name)" }
        if !g.cueNumber.isEmpty { s += " (cue \(g.cueNumber))" }
        if g.number <= 9 { s += "  ⌃\(g.number)" }
        return s
    }
}

/// ⌃1–⌃9 for the first nine buttons (⌘1–⌘5 are the timer keys).
private struct DigitShortcut: ViewModifier {
    let number: Int
    func body(content: Content) -> some View {
        if (1...9).contains(number), let c = "\(number)".first {
            content.keyboardShortcut(KeyEquivalent(c), modifiers: .control)
        } else {
            content
        }
    }
}
