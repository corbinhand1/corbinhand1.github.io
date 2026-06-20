//
//  Settings.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/28/24.
//

import SwiftUI

struct Settings: Codable {
    var fontSize: CGFloat
    var fontColor: Color
    var backgroundColor: Color
    var countdownColor: Color
    var dateTimeColor: Color
    var tableBackgroundColor: Color
    var clockFontSize: CGFloat
    var stopAtZero: Bool
    var highlightColors: [HighlightColorSetting]
    
    enum CodingKeys: String, CodingKey {
        case fontSize, fontColor, backgroundColor, countdownColor, dateTimeColor, tableBackgroundColor, clockFontSize, stopAtZero, highlightColors
    }
    
    init() {
        self.fontSize = 14
        self.fontColor = .white
        self.backgroundColor = Color(NSColor.darkGray)
        self.countdownColor = .red
        self.dateTimeColor = .green
        self.tableBackgroundColor = Color(NSColor.darkGray)
        self.clockFontSize = 80
        self.stopAtZero = true
        self.highlightColors = [
            HighlightColorSetting(keyword: "video", color: .blue),
            HighlightColorSetting(keyword: "demo", color: .red)
        ]
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        fontColor = Color(hex: try container.decode(String.self, forKey: .fontColor))
        backgroundColor = Color(hex: try container.decode(String.self, forKey: .backgroundColor))
        countdownColor = Color(hex: try container.decode(String.self, forKey: .countdownColor))
        dateTimeColor = Color(hex: try container.decode(String.self, forKey: .dateTimeColor))
        tableBackgroundColor = Color(hex: try container.decode(String.self, forKey: .tableBackgroundColor))
        clockFontSize = try container.decode(CGFloat.self, forKey: .clockFontSize)
        stopAtZero = try container.decode(Bool.self, forKey: .stopAtZero)
        highlightColors = try container.decode([HighlightColorSetting].self, forKey: .highlightColors)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontColor.toHex(), forKey: .fontColor)
        try container.encode(backgroundColor.toHex(), forKey: .backgroundColor)
        try container.encode(countdownColor.toHex(), forKey: .countdownColor)
        try container.encode(dateTimeColor.toHex(), forKey: .dateTimeColor)
        try container.encode(tableBackgroundColor.toHex(), forKey: .tableBackgroundColor)
        try container.encode(clockFontSize, forKey: .clockFontSize)
        try container.encode(stopAtZero, forKey: .stopAtZero)
        try container.encode(highlightColors, forKey: .highlightColors)
    }
}

struct HighlightColorSetting: Codable, Identifiable, Equatable {
    let id: UUID
    var keyword: String
    var color: Color
    
    enum CodingKeys: String, CodingKey {
        case id, keyword, color
    }
    
    init(id: UUID = UUID(), keyword: String, color: Color) {
        self.id = id
        self.keyword = keyword
        self.color = color
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyword = try container.decode(String.self, forKey: .keyword)
        color = Color(hex: try container.decode(String.self, forKey: .color))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(keyword, forKey: .keyword)
        try container.encode(color.toHex(), forKey: .color)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    func toHex() -> String {
        let uic = NSColor(self).usingColorSpace(.sRGB)!
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return "000000"
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        if components.count >= 4 {
            a = Float(components[3])
        }

        if a != Float(1.0) {
            return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}

