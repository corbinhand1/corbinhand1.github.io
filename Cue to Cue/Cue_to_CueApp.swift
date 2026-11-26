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
                .onAppear {
                    // Hide the system-generated View menu so only our custom one appears.
                    if let mainMenu = NSApplication.shared.mainMenu,
                       let systemViewMenu = mainMenu.item(withTitle: "View") {
                        systemViewMenu.isHidden = true
                    }
                }
        }
        .commands {
            // App Menu
            CommandGroup(before: .appInfo) {
                Button("About Cue to Cue") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }
            CommandGroup(after: .appSettings) {
                Button("Preferences...") {
                    appDelegate.showPreferences()
                }
                .keyboardShortcut(",")
            }
            CommandGroup(after: .appTermination) {
                Button("Quit Cue to Cue") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    appDelegate.newFile()
                }
                .keyboardShortcut("n")
                Button("Open...") {
                    appDelegate.openFile()
                }
                .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appDelegate.saveFile()
                }
                .keyboardShortcut("s")
                Button("Save As...") {
                    appDelegate.saveFileAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Duplicate...") {
                    appDelegate.duplicateFile()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Import CSV...") {
                    appDelegate.importCSV()
                }
                .keyboardShortcut("i")
                Button("Export CSV...") {
                    appDelegate.exportCSV()
                }
                .keyboardShortcut("e")
                Divider()
                Button("Publish to Website") {
                    appDelegate.publishToWebsite()
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                Button("Website…") {
                    appDelegate.showWebsitePanel()
                }
                Divider()
                Button("Restore from Backup…") {
                    appDelegate.restoreFromBackup()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Reveal Backups in Finder…") {
                    appDelegate.revealBackupsInFinder()
                }
                Divider()
            }
            CommandGroup(replacing: .printItem) {
                Button("Print") {
                    NotificationCenter.default.post(name: Notification.Name("TriggerPrint"), object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command])
            }
            
            // Edit Menu
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    appDelegate.undo()
                }
                .keyboardShortcut("z")
                Button("Redo") {
                    appDelegate.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    appDelegate.cut()
                }
                .keyboardShortcut("x")
                Button("Copy") {
                    appDelegate.performCopy()
                }
                .keyboardShortcut("c")
                Button("Paste") {
                    appDelegate.paste()
                }
                .keyboardShortcut("v")
                Button("Delete") {
                    appDelegate.delete()
                }
                .keyboardShortcut(.delete)
                Divider()
                Button("Select All") {
                    appDelegate.selectAll()
                }
                .keyboardShortcut("a")
                Divider()
                Button("Toggle Strike-Through") {
                    appDelegate.toggleStrikeThrough()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                // Cue-only command: grey it out when no cue is selected.
                // (Cut/Copy/Paste/Delete/Undo stay enabled: text fields
                // being edited rely on those same menu items.)
                .disabled(!(editor?.hasCueSelection ?? false))
            }
            
            // View and Window Menus
            Group {
                CommandMenu("View") {
                    Button("Toggle Full Screen") {
                        appDelegate.toggleFullScreen()
                    }
                    // Standard macOS shortcut (Cmd-F is reserved for Find).
                    .keyboardShortcut("f", modifiers: [.command, .control])
                }
                
                CommandGroup(after: .windowArrangement) {
                    Divider()
                    Button("Debug Console") {
                        appDelegate.showDebugWindow()
                    }
                    // Cmd-Shift-D belongs to File > Duplicate.
                    .keyboardShortcut("d", modifiers: [.command, .option])
                }
            }
        }
    }

}
