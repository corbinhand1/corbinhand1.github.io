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
    
    // MARK: - File Management
    
    /// Updates the last opened file path
    func updateLastOpenedFile(_ filePath: String) {
        print("Updating last opened file path to: \(filePath)")
        settings.lastOpenedFile = filePath
        save()
        print("Last opened file path saved to settings")
    }
    
    /// Gets the last opened file path
    var lastOpenedFilePath: String? {
        let path = settings.lastOpenedFile
        print("Retrieved last opened file path: \(path ?? "nil")")
        return path
    }
    
    /// Clears the last opened file path (useful when creating new files)
    func clearLastOpenedFile() {
        print("Clearing last opened file path")
        settings.lastOpenedFile = nil
        save()
        print("Last opened file path cleared from settings")
    }
}
