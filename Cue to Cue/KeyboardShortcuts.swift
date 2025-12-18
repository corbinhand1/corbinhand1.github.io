//
//  KeyboardShortcuts.swift
//  Cue to Cue
//
//  Created for customizable keyboard shortcuts
//

import SwiftUI
import AppKit

// MARK: - Keyboard Shortcut Model

struct KeyboardShortcut: Codable, Identifiable, Equatable {
    let id: String // Unique identifier for the command
    var key: String // The key character (e.g., "s", "n", "o")
    var modifiers: [String] // Modifier keys: "command", "shift", "option", "control"
    let command: String // Human-readable command name
    let category: String // Category (File, Edit, View, etc.)
    
    enum CodingKeys: String, CodingKey {
        case id, key, modifiers, command, category
    }
    
    init(id: String, key: String, modifiers: [String] = ["command"], command: String, category: String) {
        self.id = id
        self.key = key
        self.modifiers = modifiers
        self.command = command
        self.category = category
    }
    
    // Convert to SwiftUI KeyboardShortcut
    func toSwiftUI() -> KeyEquivalent? {
        guard let keyChar = key.first else { return nil }
        return KeyEquivalent(keyChar)
    }
    
    // Convert modifiers to EventModifiers
    func toEventModifiers() -> EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains("command") {
            result.insert(.command)
        }
        if modifiers.contains("shift") {
            result.insert(.shift)
        }
        if modifiers.contains("option") {
            result.insert(.option)
        }
        if modifiers.contains("control") {
            result.insert(.control)
        }
        return result
    }
    
    // Format for display - fixed to properly show modifiers
    func displayString() -> String {
        var parts: [String] = []
        if modifiers.contains("command") {
            parts.append("⌘")
        }
        if modifiers.contains("shift") {
            parts.append("⇧")
        }
        if modifiers.contains("option") {
            parts.append("⌥")
        }
        if modifiers.contains("control") {
            parts.append("⌃")
        }
        if !key.isEmpty {
            parts.append(key.uppercased())
        }
        return parts.joined(separator: "")
    }
}

// MARK: - Keyboard Shortcuts Manager

class KeyboardShortcutsManager: ObservableObject {
    @Published var shortcuts: [KeyboardShortcut] = []
    
    private let userDefaultsKey = "KeyboardShortcuts"
    
    init() {
        loadShortcuts()
        if shortcuts.isEmpty {
            createDefaultShortcuts()
        } else {
            // Merge any missing default shortcuts (for updates)
            mergeMissingDefaults()
        }
    }
    
    private func mergeMissingDefaults() {
        let defaultShortcuts = getAllDefaultShortcuts()
        var updated = false
        
        for defaultShortcut in defaultShortcuts {
            if !shortcuts.contains(where: { $0.id == defaultShortcut.id }) {
                shortcuts.append(defaultShortcut)
                updated = true
            }
        }
        
        if updated {
            saveShortcuts()
        }
    }
    
    private func getAllDefaultShortcuts() -> [KeyboardShortcut] {
        return [
            // File Menu
            KeyboardShortcut(id: "new", key: "n", modifiers: ["command"], command: "New", category: "File"),
            KeyboardShortcut(id: "open", key: "o", modifiers: ["command"], command: "Open...", category: "File"),
            KeyboardShortcut(id: "save", key: "s", modifiers: ["command"], command: "Save", category: "File"),
            KeyboardShortcut(id: "saveAs", key: "s", modifiers: ["command", "shift"], command: "Save As...", category: "File"),
            KeyboardShortcut(id: "importCSV", key: "i", modifiers: ["command"], command: "Import CSV...", category: "File"),
            KeyboardShortcut(id: "exportCSV", key: "e", modifiers: ["command"], command: "Export CSV...", category: "File"),
            KeyboardShortcut(id: "print", key: "p", modifiers: ["command"], command: "Print", category: "File"),
            
            // Edit Menu
            KeyboardShortcut(id: "undo", key: "z", modifiers: ["command"], command: "Undo", category: "Edit"),
            KeyboardShortcut(id: "redo", key: "z", modifiers: ["command", "shift"], command: "Redo", category: "Edit"),
            KeyboardShortcut(id: "cut", key: "x", modifiers: ["command"], command: "Cut", category: "Edit"),
            KeyboardShortcut(id: "copy", key: "c", modifiers: ["command"], command: "Copy", category: "Edit"),
            KeyboardShortcut(id: "paste", key: "v", modifiers: ["command"], command: "Paste", category: "Edit"),
            KeyboardShortcut(id: "delete", key: "", modifiers: [], command: "Delete", category: "Edit"),
            KeyboardShortcut(id: "selectAll", key: "a", modifiers: ["command"], command: "Select All", category: "Edit"),
            KeyboardShortcut(id: "toggleStrikeThrough", key: "t", modifiers: ["command", "shift"], command: "Toggle Strike-Through", category: "Edit"),
            
            // View Menu
            KeyboardShortcut(id: "toggleFullScreen", key: "f", modifiers: ["command"], command: "Toggle Full Screen", category: "View"),
            
            // App Menu
            KeyboardShortcut(id: "preferences", key: ",", modifiers: ["command"], command: "Preferences...", category: "App"),
            KeyboardShortcut(id: "quit", key: "q", modifiers: ["command"], command: "Quit", category: "App"),
            
            // Timer Controls - Countdown
            KeyboardShortcut(id: "countdownStart", key: "1", modifiers: ["command"], command: "Countdown Start", category: "Timer"),
            KeyboardShortcut(id: "countdownPause", key: "2", modifiers: ["command"], command: "Countdown Pause", category: "Timer"),
            KeyboardShortcut(id: "countdownReset", key: "0", modifiers: ["command"], command: "Countdown Reset", category: "Timer"),
            KeyboardShortcut(id: "countdownPlus1Min", key: "=", modifiers: ["command"], command: "Countdown +1 Min", category: "Timer"),
            KeyboardShortcut(id: "countdownMinus1Min", key: "-", modifiers: ["command"], command: "Countdown -1 Min", category: "Timer"),
            
            // Timer Controls - Countdown to Time
            KeyboardShortcut(id: "countdownToTimeStart", key: "3", modifiers: ["command"], command: "Countdown to Time Start", category: "Timer"),
            KeyboardShortcut(id: "countdownToTimePause", key: "4", modifiers: ["command"], command: "Countdown to Time Pause", category: "Timer"),
            KeyboardShortcut(id: "countdownToTimeNext", key: "5", modifiers: ["command"], command: "Countdown to Time Next", category: "Timer"),
            
            // Playlist
            KeyboardShortcut(id: "countdownPlaylist", key: "p", modifiers: ["command", "shift"], command: "Countdown Playlist", category: "Timer"),
            
            // Cue Navigation
            KeyboardShortcut(id: "addCue", key: "n", modifiers: ["command", "shift"], command: "Add Cue", category: "Cues"),
            KeyboardShortcut(id: "nextCue", key: "]", modifiers: ["command"], command: "Next Cue", category: "Cues"),
            KeyboardShortcut(id: "previousCue", key: "[", modifiers: ["command"], command: "Previous Cue", category: "Cues")
        ]
    }
    
    private func createDefaultShortcuts() {
        shortcuts = getAllDefaultShortcuts()
        saveShortcuts()
    }
    
    func getShortcut(for id: String) -> KeyboardShortcut? {
        return shortcuts.first { $0.id == id }
    }
    
    func updateShortcut(id: String, key: String, modifiers: [String]) {
        if let index = shortcuts.firstIndex(where: { $0.id == id }) {
            shortcuts[index].key = key
            shortcuts[index].modifiers = modifiers
            saveShortcuts()
        }
    }
    
    func resetToDefaults() {
        shortcuts.removeAll()
        createDefaultShortcuts()
    }
    
    private func loadShortcuts() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([KeyboardShortcut].self, from: data) {
            shortcuts = decoded
        }
    }
    
    private func saveShortcuts() {
        if let encoded = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    var shortcutsByCategory: [String: [KeyboardShortcut]] {
        Dictionary(grouping: shortcuts, by: { $0.category })
    }
}

