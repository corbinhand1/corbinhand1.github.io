import SwiftUI

extension Color {
    /// "FA7E7B" -> color. In light mode the pastel highlight colors are darkened so text stays readable.
    static func highlight(hex: String, darkMode: Bool) -> Color {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return Theme.text }
        var r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        if !darkMode { r *= 0.55; g *= 0.55; b *= 0.55 }
        return Color(red: r, green: g, blue: b)
    }
}

/// Same rule as the Mac: a cue takes the first highlight rule whose keyword appears in any cell.
enum Highlight {
    static func ruleIndex(for cue: SheetCue, rules: [HighlightRule]) -> Int? {
        for (i, rule) in rules.enumerated() where !rule.keyword.isEmpty {
            let k = rule.keyword.lowercased()
            if cue.values.contains(where: { $0.lowercased().contains(k) }) { return i }
        }
        return nil
    }
}

/// A run of consecutive cues sharing one highlight rule, e.g. one demo.
struct CueGroup: Identifiable, Equatable {
    let number: Int              // 1-based position among groups of this rule
    let ruleIndex: Int
    let cueIDs: [String]
    let name: String             // "Cars 1"
    let cueNumber: String        // the show's cue number where the group starts, e.g. "138"
    var id: Int { number }
    var firstCueID: String { cueIDs[0] }
}

enum Jump {
    /// Consecutive cues matching `ruleIndex`, in show order.
    static func groups(sheet: Sheet, ruleIndex: Int) -> [CueGroup] {
        let rules = sheet.highlightColors ?? []
        guard rules.indices.contains(ruleIndex) else { return [] }
        let keyword = rules[ruleIndex].keyword
        let descCol = sheet.descriptionColumn
        var groups: [CueGroup] = []
        var run: [SheetCue] = []
        var lastNumber = ""

        func flush(startNumber: String) {
            guard let first = run.first else { return }
            let own = run.first(where: { !($0.values.first ?? "").isEmpty })?.values.first ?? ""
            groups.append(CueGroup(number: groups.count + 1, ruleIndex: ruleIndex, cueIDs: run.map(\.id),
                                   name: name(for: first, descCol: descCol, keyword: keyword),
                                   cueNumber: own.isEmpty ? startNumber : own))
            run = []
        }

        var startNumber = ""
        for cue in sheet.cues {
            let matches = Highlight.ruleIndex(for: cue, rules: rules) == ruleIndex
            if matches {
                if run.isEmpty { startNumber = lastNumber }
                run.append(cue)
            } else if !run.isEmpty { flush(startNumber: startNumber) }
            if let n = cue.values.first, !n.isEmpty { lastNumber = n }
        }
        flush(startNumber: startNumber)
        return groups
    }

    /// "DEMO: Cars 1 [when]" -> "Cars 1".
    static func name(for cue: SheetCue, descCol: Int, keyword: String) -> String {
        var text = descCol < cue.values.count ? When.stripped(cue.values[descCol]) : ""
        if let r = text.range(of: keyword, options: [.caseInsensitive, .anchored]) {
            text.removeSubrange(r)
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: ": -–—").union(.whitespaces))
        }
        return text.isEmpty ? "Group" : text
    }

    struct Result {
        var groups: [CueGroup]
        var cue: SheetCue?           // a cue whose number matches what was typed
    }

    /// A number matches the group number and a cue number; text matches names and any cell in the group.
    static func search(_ query: String, groups: [CueGroup], sheet: Sheet) -> Result {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Result(groups: groups, cue: nil) }
        let cueMatch = sheet.cues.first { ($0.values.first ?? "").lowercased() == q }
        if let n = Int(q) {
            let byNumber = groups.filter { $0.number == n }
            let byCue = groups.filter { $0.cueNumber == q }
            return Result(groups: byNumber + byCue.filter { g in !byNumber.contains(g) }, cue: cueMatch)
        }
        let byText = groups.filter { g in
            g.name.lowercased().contains(q) ||
            g.cueIDs.contains { id in sheet.cues.first { $0.id == id }?.values.contains { $0.lowercased().contains(q) } ?? false }
        }
        return Result(groups: byText, cue: cueMatch)
    }
}
