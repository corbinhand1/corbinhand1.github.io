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
    
    // MARK: - Automatic File Loading
    // The app now automatically loads the last opened file when it starts.
    // This is especially useful for troubleshooting and development.
    // The file path is stored in UserDefaults and persists between app launches.

    var body: some Scene {
        WindowGroup {
            ContentView()
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
                .onChange(of: currentFileName) { oldValue, newValue in
                    updateWindowTitle(to: newValue)
                }
        }
        .commands {
            // App Menu remains the same.
            CommandGroup(before: .appInfo) {
                Button("About Cue to Cue") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }
            CommandGroup(after: .appSettings) {
                Button("Preferences...") {
                    appDelegate.showPreferencesAction()
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
            }
            // Print Command
            CommandGroup(replacing: .printItem) {
                Button("Print") {
                    // Post a notification that ContentView listens for to trigger printing.
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
                    // Placeholder - implement when ContentView has this method
                    print("Delete requested")
                }
                .keyboardShortcut(.delete)
                Divider()
                Button("Select All") {
                    appDelegate.selectAll()
                }
                .keyboardShortcut("a")
            }
            
            // Custom View Menu – this will be the only View menu now.
            CommandMenu("View") {
                Button("Toggle Full Screen") {
                    // Placeholder - implement when AppDelegate has this method
                    print("Toggle full screen requested")
                }
                .keyboardShortcut("f")
            }
            
            // Window Menu (optional – system default remains if this block is commented out)
            // CommandMenu("Window") {
            //     Button("Minimize") {
            //         NSApp.keyWindow?.miniaturize(nil)
            //     }
            //     .keyboardShortcut("m")
            //     Button("Zoom") {
            //         NSApp.keyWindow?.zoom(nil)
            //     }
            // }
        }
    }

    // Function to update the window title.
    private func updateWindowTitle(to title: String) {
        if let window = NSApplication.shared.windows.first {
            window.title = title
        }
    }
}
