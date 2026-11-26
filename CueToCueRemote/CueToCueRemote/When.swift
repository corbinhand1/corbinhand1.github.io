import Foundation

/// The "[when]" part of a cue description, e.g. "Gloria Mic Hot [on welcome]".
/// This is the text crew edit after asking a speaker what they'll actually say.
enum When {
    private static let pattern = try! NSRegularExpression(pattern: "\\[([^\\]]*)\\]")

    /// The last bracketed segment's range (full match and inner text), if any.
    private static func last(in s: String) -> (full: Range<String.Index>, inner: Range<String.Index>)? {
        let ns = NSRange(s.startIndex..., in: s)
        guard let m = pattern.matches(in: s, range: ns).last,
              let full = Range(m.range, in: s), let inner = Range(m.range(at: 1), in: s) else { return nil }
        return (full, inner)
    }

    /// Text between the brackets, or nil when the description has none.
    static func text(in description: String) -> String? {
        last(in: description).map { String(description[$0.inner]) }
    }

    /// The description with the [when] removed, for display next to the when chip.
    static func stripped(_ description: String) -> String {
        guard let r = last(in: description) else { return description }
        var s = description
        s.removeSubrange(r.full)
        return s.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Rewrites only the bracketed text. Empty text removes the brackets;
    /// a description with no brackets gets " [text]" appended.
    static func replacing(in description: String, with newText: String) -> String {
        let t = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = last(in: description) {
            var s = description
            if t.isEmpty { s.removeSubrange(r.full); return s.trimmingCharacters(in: .whitespaces) }
            s.replaceSubrange(r.inner, with: t)
            return s
        }
        guard !t.isEmpty else { return description }
        let base = description.trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? "[\(t)]" : "\(base) [\(t)]"
    }
}

extension Sheet {
    /// Which column holds the description (the one with the [when] text).
    var descriptionColumn: Int {
        columns.firstIndex { $0.name.lowercased().contains("description") } ?? 1
    }
}
