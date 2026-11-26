import SwiftUI

/// Dark-first palette for use in dark booths: near-black surfaces, one warm
/// "spotlight" accent, and text pairs that stay above 4.5:1.
enum Theme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.071)   // #0B0B12
    static let card       = Color(red: 0.086, green: 0.086, blue: 0.122)   // #16161F
    static let cardRaised = Color(red: 0.133, green: 0.133, blue: 0.180)   // #222230
    static let accent     = Color(red: 0.961, green: 0.718, blue: 0.000)   // #F5B700
    static let onAccent   = Color(red: 0.059, green: 0.090, blue: 0.165)   // #0F172A
    static let text       = Color(red: 0.973, green: 0.980, blue: 0.988)   // #F8FAFC
    static let textMuted  = Color(red: 0.667, green: 0.714, blue: 0.784)   // #AAB6C8
    static let danger     = Color(red: 1.000, green: 0.384, blue: 0.384)

    static let minTarget: CGFloat = 48
}

/// Wraps its children onto new lines instead of shrinking or scrolling sideways.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 320, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (i, frame) in result.frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                              proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let w = min(s.width, width)
            if x > 0 && x + w > width { x = 0; y += rowH + spacing; rowH = 0 }
            frames.append(CGRect(x: x, y: y, width: w, height: s.height))
            x += w + spacing; rowH = max(rowH, s.height); maxW = max(maxW, x - spacing)
        }
        return (CGSize(width: maxW, height: y + rowH), frames)
    }
}
