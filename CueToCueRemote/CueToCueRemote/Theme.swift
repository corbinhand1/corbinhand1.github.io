import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// A color that follows light/dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

/// Semantic tokens. Text/icon colors meet 4.5:1 on their surfaces in both appearances.
enum Theme {
    static let background = Color(light: 0xF2F2F7, dark: 0x0B0B12)
    static let card       = Color(light: 0xFFFFFF, dark: 0x16161F)
    static let cardRaised = Color(light: 0xE8E8EE, dark: 0x222230)
    /// Spotlight gold for fills (buttons, badges); always pair with `onAccent` text.
    static let accentFill = Color(light: 0xF5B700, dark: 0xF5B700)
    static let onAccent   = Color(light: 0x0F172A, dark: 0x0F172A)
    /// Gold for text, icons and outlines on surfaces (darker amber in light mode for contrast).
    static let accent     = Color(light: 0x8A5A00, dark: 0xF5B700)
    static let text       = Color(light: 0x0B0B12, dark: 0xF8FAFC)
    static let textMuted  = Color(light: 0x5B6472, dark: 0xAAB6C8)
    static let danger     = Color(light: 0xC62828, dark: 0xFF6B6B)
    static let success    = Color(light: 0x1B7F3B, dark: 0x4ADE80)

    /// Apple's minimum comfortable touch target is 44pt; we use 48 for dark booths.
    static let minTarget: CGFloat = 48
    static let radius: CGFloat = 16
}

/// Haptics that respect the in-app switch.
enum Haptics {
    private static var on: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }
    static func tap() { if on { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
    static func select() { if on { UISelectionFeedbackGenerator().selectionChanged() } }
    static func success() { if on { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func warning() { if on { UINotificationFeedbackGenerator().notificationOccurred(.warning) } }
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

/// Brief dim on press so every tap target gives immediate feedback.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
