//
//  SettingsManager.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/28/24.
//

import SwiftUI

class SettingsManager: ObservableObject {
    static let clockFontSizeRange: ClosedRange<CGFloat> = 70...90

    @Published var settings: Settings {
        didSet {
            save()
        }
    }
    
    let shortcutsManager = KeyboardShortcutsManager()
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "AppSettings"),
           let decodedSettings = try? JSONDecoder().decode(Settings.self, from: data) {
            var normalized = decodedSettings
            normalized.clockFontSize = min(
                max(normalized.clockFontSize, Self.clockFontSizeRange.lowerBound),
                Self.clockFontSizeRange.upperBound
            )
            self.settings = normalized
            // `didSet` persists when clamping corrects an out-of-range saved value.
        } else {
            self.settings = Settings()
        }
    }
    
    func save() {
        if let encodedData = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encodedData, forKey: "AppSettings")
        }
    }
}
