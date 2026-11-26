//
//  CueToCueApp.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 5/26/24.
//

import SwiftUI

@main
struct CueToCueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settingsManager = SettingsManager()
    @State private var currentFileName: String = "Untitled"
    /// The main window's editor, for enabling cue-only menu commands.
    @FocusedObject private var editor: CueEditorController?

    var body: some Scene {
        // Single main window: every menu command and the LAN server are wired
        // to one document, so a second window would be disconnected.
        Window("Cue to Cue", id: "main") {
            ContentView(currentFileName: $currentFileName)
                .environmentObject(appDelegate)
                .environmentObject(settingsManager)
                .frame(minWidth: 1200, minHeight: 600)
        }
        .commands {
            FileMenuCommands(appDelegate: appDelegate)
            EditMenuCommands(appDelegate: appDelegate)
            ViewMenuCommands(appDelegate: appDelegate)
            ShowMenuCommands(appDelegate: appDelegate,
                             shortcuts: settingsManager.shortcutsManager,
                             hasCueSelection: editor?.hasCueSelection ?? false)
            WindowMenuCommands(appDelegate: appDelegate)
            HelpMenuCommands(appDelegate: appDelegate)
        }

        // Standard macOS Settings window: adds Cue to Cue ▸ Settings… (⌘,).
        // (`SwiftUI.` because the app has its own `Settings` model.)
        SwiftUI.Settings {
            SettingsView(settingsManager: settingsManager)
                .environmentObject(settingsManager)
        }
    }
}

// MARK: - File menu

struct FileMenuCommands: Commands {
    let appDelegate: AppDelegate

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { appDelegate.newFile() }
                .keyboardShortcut("n")
            Button("New Cue Stack from Documents…") { appDelegate.showAIImport() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Open…") { appDelegate.openFile() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { appDelegate.saveFile() }
                .keyboardShortcut("s")
            Button("Save As…") { appDelegate.saveFileAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Duplicate…") { appDelegate.duplicateFile() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Import CSV…") { appDelegate.importCSV() }
                .keyboardShortcut("i")
            Button("Export CSV…") { appDelegate.exportCSV() }
                .keyboardShortcut("e")
            Divider()
            Button("Publish to Website") { appDelegate.publishToWebsite() }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Website…") { appDelegate.showWebsitePanel() }
            Divider()
            Button("Restore from Backup…") { appDelegate.restoreFromBackup() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Show Backups in Finder") { appDelegate.revealBackupsInFinder() }
        }
        CommandGroup(replacing: .printItem) {
            Button("Print…") {
                NotificationCenter.default.post(name: Notification.Name("TriggerPrint"), object: nil)
            }
            .keyboardShortcut("p")
        }
    }
}

// MARK: - Edit menu

struct EditMenuCommands: Commands {
    let appDelegate: AppDelegate

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { appDelegate.undo() }
                .keyboardShortcut("z")
            Button("Redo") { appDelegate.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .pasteboard) {
            // These stay enabled: a cell being edited uses the same items.
            Button("Cut") { appDelegate.cut() }
                .keyboardShortcut("x")
            Button("Copy") { appDelegate.performCopy() }
                .keyboardShortcut("c")
            Button("Paste") { appDelegate.paste() }
                .keyboardShortcut("v")
            Button("Delete") { appDelegate.delete() }
                .keyboardShortcut(.delete)
            Divider()
            Button("Select All") { appDelegate.selectAll() }
                .keyboardShortcut("a")
        }
        CommandGroup(replacing: .textEditing) {
            Button("Find and Replace…") {
                NotificationCenter.default.post(name: .appDelegateShowFindReplace, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
        }
    }
}

// MARK: - Cue and Timer menus

/// Show-running commands. Their shortcuts come from Settings ▸ Keyboard
/// Shortcuts, so a customized key shows (and works) here.
struct ShowMenuCommands: Commands {
    let appDelegate: AppDelegate
    @ObservedObject var shortcuts: KeyboardShortcutsManager
    let hasCueSelection: Bool

    var body: some Commands {
        CommandMenu("Cue") {
            item("Next Cue", "nextCue")
            item("Previous Cue", "previousCue")
            Divider()
            item("Add Cue", "addCue")
            Button("Strike Through") { appDelegate.toggleStrikeThrough() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!hasCueSelection)
        }
        CommandMenu("Timer") {
            item("Start Countdown", "countdownStart")
            item("Pause Countdown", "countdownPause")
            item("Reset Countdown", "countdownReset")
            item("Add 1 Minute", "countdownPlus1Min")
            item("Subtract 1 Minute", "countdownMinus1Min")
            Divider()
            item("Start Countdown to Time", "countdownToTimeStart")
            item("Pause Countdown to Time", "countdownToTimePause")
            item("Next Playlist Entry", "countdownToTimeNext")
            Divider()
            item("Edit Playlist…", "countdownPlaylist")
        }
    }

    @ViewBuilder
    private func item(_ title: String, _ id: String) -> some View {
        let button = Button(title) { appDelegate.runShowCommand(id) }
        if let shortcut = shortcuts.shortcuts.first(where: { $0.id == id }),
           let key = MenuShortcut.keyEquivalent(shortcut.key) {
            button.keyboardShortcut(key, modifiers: MenuShortcut.modifiers(shortcut.modifiers))
        } else {
            button
        }
    }
}

// MARK: - View menu

struct ViewMenuCommands: Commands {
    let appDelegate: AppDelegate

    var body: some Commands {
        // macOS's automatic full-screen item is turned off (AppDelegate), so
        // this is the only one.
        CommandGroup(after: .toolbar) {
            ToggleCueStacksMenuItem()
            Button("Toggle Full Screen") { appDelegate.toggleFullScreen() }
                .keyboardShortcut("f", modifiers: [.command, .control])
        }
    }
}

/// View ▸ Hide/Show Cue Stacks, titled for what it will do.
private struct ToggleCueStacksMenuItem: View {
    @AppStorage("layout.showCueStacks") private var showCueStacks = true

    var body: some View {
        Button(showCueStacks ? "Hide Cue Stacks" : "Show Cue Stacks") {
            NotificationCenter.default.post(name: .appDelegateToggleCueStacks, object: nil)
        }
        .keyboardShortcut("s", modifiers: [.command, .control])
    }
}

// MARK: - Window menu

struct WindowMenuCommands: Commands {
    let appDelegate: AppDelegate

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Connected Viewers…") { appDelegate.showConnectedViewers() }
            Button("Users & Permissions…") { appDelegate.showUserManagement() }
            Divider()
            Button("Debug Console") { appDelegate.showDebugWindow() }
                // Cmd-Shift-D belongs to File > Duplicate.
                .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }
}

// MARK: - Help menu

struct HelpMenuCommands: Commands {
    let appDelegate: AppDelegate

    var body: some Commands {
        // Replaces macOS's "Cue to Cue Help", which had no help book behind it.
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts…") { appDelegate.showKeyboardShortcuts() }
            Button("Cue to Cue Website") {
                if let url = URL(string: "https://nebulacreative.org/cuetocue/") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - Shortcut conversion

/// Converts a saved KeyboardShortcut ("1", ["command"]) into a menu shortcut.
enum MenuShortcut {
    static func keyEquivalent(_ key: String) -> KeyEquivalent? {
        switch key {
        case "": return nil
        case "↑": return .upArrow
        case "↓": return .downArrow
        case "←": return .leftArrow
        case "→": return .rightArrow
        default:
            guard key.count == 1, let character = key.lowercased().first else { return nil }
            return KeyEquivalent(character)
        }
    }

    static func modifiers(_ names: [String]) -> EventModifiers {
        var result: EventModifiers = []
        if names.contains("command") { result.insert(.command) }
        if names.contains("shift") { result.insert(.shift) }
        if names.contains("option") { result.insert(.option) }
        if names.contains("control") { result.insert(.control) }
        return result
    }
}
