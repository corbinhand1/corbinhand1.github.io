//
//  SettingsManager.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/28/24.
//

import SwiftUI

class SettingsManager: ObservableObject {
    @Published var settings: Settings {
        didSet {
            save()
        }
    }
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "AppSettings"),
           let decodedSettings = try? JSONDecoder().decode(Settings.self, from: data) {
            self.settings = decodedSettings
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
