//
//  AppDelegate.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 5/31/24.
//

import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var window: NSWindow!
    var contentView: ContentView?
    var webServer: WebServer?
    
    // Published properties for SwiftUI integration
    @Published var showPreferences = false
    @Published var showAbout = false
    
    // File handling
    private var pendingFileToOpen: URL?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Initialize web server
        webServer = WebServer()
        
        // Handle any pending file to open
        if let pendingFile = pendingFileToOpen {
            openFileAtURL(pendingFile)
            pendingFileToOpen = nil
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Clean up web server
        webServer?.stop()
    }
    
    // MARK: - File Operations
    
    func newFile() {
        // Placeholder - implement when ContentView has this method
        print("New file requested")
    }
    
    func openFile() {
        // Placeholder - implement when ContentView has this method
        print("Open file requested")
    }
    
    func saveFile() {
        // Placeholder - implement when ContentView has this method
        print("Save file requested")
    }
    
    func saveFileAs() {
        // Placeholder - implement when ContentView has this method
        print("Save file as requested")
    }
    
    func importCSV() {
        contentView?.importCSV()
    }
    
    func exportCSV() {
        // Placeholder - implement when ContentView has this method
        print("Export CSV requested")
    }
    
    func openFileAtURL(_ url: URL) {
        // This will be handled by ContentView
        print("Opening file at URL: \(url.path)")
    }
    
    // MARK: - Edit Operations
    
    func undo() {
        contentView?.undo()
    }
    
    func redo() {
        contentView?.redo()
    }
    
    func cut() {
        // Placeholder - implement when ContentView has this method
        print("Cut requested")
    }
    
    func performCopy() {
        contentView?.copyCues()
    }
    
    func paste() {
        contentView?.pasteCues()
    }
    
    func selectAll() {
        // Placeholder - implement when ContentView has this method
        print("Select all requested")
    }
    
    // MARK: - Menu Actions
    
    func showPreferencesAction() {
        showPreferences = true
    }
    
    func showAboutAction() {
        showAbout = true
    }
    
    // MARK: - Application Delegate Methods
    
    func application(_ application: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        pendingFileToOpen = url
        return true
    }
    
    func application(_ application: NSApplication, openFiles filenames: [String]) -> Bool {
        if let firstFile = filenames.first {
            let url = URL(fileURLWithPath: firstFile)
            pendingFileToOpen = url
        }
        return true
    }
    
    // MARK: - Web Server Integration
    
    func updateWebClients() {
        contentView?.updateWebClients()
    }
    
    func updateWebClientsWithClockState(_ clockState: Any) {
        // Handle clock state updates for web clients
        print("Updating web clients with clock state")
    }
}
