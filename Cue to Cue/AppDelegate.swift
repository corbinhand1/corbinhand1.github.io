//
//  AppDelegate.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 5/31/24.
//

import Cocoa
import SwiftUI
import Combine

// MARK: - Notification Names
extension Notification.Name {
    static let appDelegateShowPreferences = Notification.Name("appDelegateShowPreferences")
    static let appDelegateNewFile = Notification.Name("appDelegateNewFile")
    static let appDelegateOpenFile = Notification.Name("appDelegateOpenFile")
    static let appDelegateSaveFile = Notification.Name("appDelegateSaveFile")
    static let appDelegateSaveFileAs = Notification.Name("appDelegateSaveFileAs")
    static let appDelegateImportCSV = Notification.Name("appDelegateImportCSV")
    static let appDelegateExportCSV = Notification.Name("appDelegateExportCSV")
    static let appDelegateUndo = Notification.Name("appDelegateUndo")
    static let appDelegateRedo = Notification.Name("appDelegateRedo")
    static let appDelegateCut = Notification.Name("appDelegateCut")
    static let appDelegateCopy = Notification.Name("appDelegateCopy")
    static let appDelegatePaste = Notification.Name("appDelegatePaste")
    static let appDelegateDelete = Notification.Name("appDelegateDelete")
    static let appDelegateSelectAll = Notification.Name("appDelegateSelectAll")
    static let appDelegateToggleStrikeThrough = Notification.Name("appDelegateToggleStrikeThrough")
    static let appDelegateToggleFullScreen = Notification.Name("appDelegateToggleFullScreen")
    static let appDelegateUpdateWebClients = Notification.Name("appDelegateUpdateWebClients")
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    // Published properties for SwiftUI integration
    @Published var shouldShowPreferences = false
    @Published var showAbout = false
    
    // File handling
    var pendingFileToOpen: URL? // Made internal so ContentView can check if a file was explicitly opened

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Note: Window creation is handled by SwiftUI's WindowGroup
        // WebServer is managed by ContentView to share the same DataSyncManager instance
        
        // Start intercepting print statements to capture console output
        PrintInterceptor.shared.startIntercepting()
        
        // Log app launch
        LogManager.shared.addLog("Cue to Cue app launched", level: .info)
        
        // Handle any pending file to open
        if let pendingFile = pendingFileToOpen {
            openFileAtURL(pendingFile)
            pendingFileToOpen = nil
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Cleanup is handled by ContentView's WebServer
    }
    
    // MARK: - File Operations
    
    func newFile() {
        // Post notification for ContentView to handle
        NotificationCenter.default.post(name: .appDelegateNewFile, object: nil)
    }
    
    func openFile() {
        // Post notification to trigger ContentView's showOpenPanel
        NotificationCenter.default.post(name: .appDelegateOpenFile, object: nil)
    }
    
    func saveFile() {
        // Post notification to trigger ContentView's showSavePanel
        NotificationCenter.default.post(name: .appDelegateSaveFile, object: nil)
    }
    
    func saveFileAs() {
        // Post notification to trigger ContentView's saveFileAs
        NotificationCenter.default.post(name: .appDelegateSaveFileAs, object: nil)
    }
    
    func importCSV() {
        // Post notification to trigger ContentView's showImportCSVPanel
        NotificationCenter.default.post(name: .appDelegateImportCSV, object: nil)
    }
    
    func exportCSV() {
        // Post notification for ContentView to handle
        NotificationCenter.default.post(name: .appDelegateExportCSV, object: nil)
    }
    
    func openFileAtURL(_ url: URL) {
        // This will be handled by ContentView through file opening mechanisms
        pendingFileToOpen = url
        NotificationCenter.default.post(name: .appDelegateOpenFile, object: url)
    }
    
    // MARK: - Edit Operations
    
    func undo() {
        NotificationCenter.default.post(name: .appDelegateUndo, object: nil)
    }
    
    func redo() {
        NotificationCenter.default.post(name: .appDelegateRedo, object: nil)
    }
    
    func cut() {
        // First try standard text field cut, then fall back to cue cut
        if let firstResponder = NSApp.keyWindow?.firstResponder,
           let textView = firstResponder as? NSTextView {
            textView.cut(nil)
        } else {
            NotificationCenter.default.post(name: .appDelegateCut, object: nil)
        }
    }
    
    func performCopy() {
        // First try standard text field copy, then fall back to cue copy
        if let firstResponder = NSApp.keyWindow?.firstResponder,
           let textView = firstResponder as? NSTextView {
            textView.copy(nil)
        } else {
            NotificationCenter.default.post(name: .appDelegateCopy, object: nil)
        }
    }
    
    func paste() {
        // First try standard text field paste, then fall back to cue paste
        if let firstResponder = NSApp.keyWindow?.firstResponder,
           let textView = firstResponder as? NSTextView {
            textView.paste(nil)
        } else {
            NotificationCenter.default.post(name: .appDelegatePaste, object: nil)
        }
    }
    
    func delete() {
        // First try standard text field delete, then fall back to cue delete
        if let firstResponder = NSApp.keyWindow?.firstResponder,
           let textView = firstResponder as? NSTextView {
            textView.delete(nil)
        } else {
            NotificationCenter.default.post(name: .appDelegateDelete, object: nil)
        }
    }
    
    func selectAll() {
        // First try standard text field select all, then fall back to cue select all
        if let firstResponder = NSApp.keyWindow?.firstResponder,
           let textView = firstResponder as? NSTextView {
            textView.selectAll(nil)
        } else {
            NotificationCenter.default.post(name: .appDelegateSelectAll, object: nil)
        }
    }
    
    func toggleStrikeThrough() {
        NotificationCenter.default.post(name: .appDelegateToggleStrikeThrough, object: nil)
    }
    
    // MARK: - View Operations
    
    func showPreferences() {
        // Set the published property to trigger SwiftUI updates
        shouldShowPreferences = true
        // Also post notification for ContentView to handle
        NotificationCenter.default.post(name: .appDelegateShowPreferences, object: nil)
    }
    
    func toggleFullScreen() {
        if let window = NSApp.keyWindow {
            window.toggleFullScreen(nil)
        } else if let window = NSApp.windows.first {
            window.toggleFullScreen(nil)
        }
    }
    
    // MARK: - Web Server Operations
    
    func updateWebClients() {
        NotificationCenter.default.post(name: .appDelegateUpdateWebClients, object: nil)
    }
    
    // MARK: - Debug Window Operations
    
    private var debugWindow: NSWindow?
    
    func showDebugWindow() {
        // Check if window already exists
        if let existingWindow = debugWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create new debug window
        let contentView = NSHostingView(rootView: DebugWindowView())
        contentView.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = contentView
        window.title = "Debug Console"
        window.identifier = NSUserInterfaceItemIdentifier("debug-console")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        debugWindow = window
        
        // Clean up when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.debugWindow = nil
        }
    }
    
    // MARK: - Application Delegate Methods
    
    func application(_ application: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        pendingFileToOpen = url
        openFileAtURL(url)
        return true
    }
    
    func application(_ application: NSApplication, openFiles filenames: [String]) {
        if let firstFile = filenames.first {
            let url = URL(fileURLWithPath: firstFile)
            pendingFileToOpen = url
            openFileAtURL(url)
        }
    }
}
