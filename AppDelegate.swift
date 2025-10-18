//
//  AppDelegate.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/28/24.
//

import SwiftUI
import Cocoa
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var contentView: ContentView?
    var webServer: WebServer?

    // If you share the same SettingsManager for all windows:
    @Published var settingsManager = SettingsManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // WebServer is now created by ContentView with shared DataSyncManager
        // No need to create it here
        
        if let ipAddress = webServer?.getLocalIPAddress() {
            let url = "http://\(ipAddress):8080"
            print("Web server accessible at: \(url)")
            DispatchQueue.main.async {
                self.showLocalURL(url)
            }
        } else {
            print("Unable to determine local IP address")
        }
        
        // Create the main window if none exists
        if contentView == nil {
            // 1) Create a raw ContentView (type is exactly ContentView)
            let rawContentView = ContentView(currentFileName: .constant("Untitled"))
            
            // 2) Assign it to self.contentView so we can call methods on it
            self.contentView = rawContentView
            
            // 3) Wrap the raw ContentView with environment objects for SwiftUI
            let environmentWrappedView = rawContentView
                .environmentObject(self)
                .environmentObject(settingsManager)
            
            // 4) Create a HostingView for display
            let hostingView = NSHostingView(rootView: environmentWrappedView)
            
            // 5) Create the main NSWindow
            let mainWindow = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 1200, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            mainWindow.center()
            mainWindow.title = "Untitled"
            mainWindow.contentView = hostingView
            mainWindow.makeKeyAndOrderFront(nil)
        }
        
        // Perform initial update of web clients
        updateWebClients()
        
        // Request Apple Events access (if needed for Keynote or similar)
        requestAppleEventsAccess()
    }
    
    // MARK: - Request Apple Events Access (Keynote, etc.)
    func requestAppleEventsAccess() {
        let script = """
        tell application "Keynote"
            if it is running then
                get name of every document
            else
                return "Keynote is not running"
            end if
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            
            if let error = error {
                let errorCode = error[NSAppleScript.errorNumber] as? Int ?? 0
                print("Error requesting Apple Events access: \(error)")
                
                if errorCode == -1743 {
                    DispatchQueue.main.async {
                        self.showAppleEventsPermissionAlert()
                    }
                } else {
                    print("Unexpected error: \(error)")
                }
            } else {
                print("Apple Events access request successful. Output: \(output.stringValue ?? "No output")")
            }
        } else {
            print("Failed to create AppleScript object")
        }
    }

    private func showAppleEventsPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Permission Required"
        alert.informativeText = "This app needs permission to control Keynote. Please grant permission in System Settings > Privacy & Security > Automation."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
        }
    }
    
    // MARK: - Show Local URL
    func showLocalURL(_ url: String) {
        let alert = NSAlert()
        alert.messageText = "Web Viewer URL"
        alert.informativeText = "Your web viewer is now accessible on your local network at:\n\(url)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Copy URL")
        alert.addButton(withTitle: "OK")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url, forType: .string)
        }
    }
    
    // MARK: - Menu Action Methods
    @objc func saveFile() {
        contentView?.saveFile()
    }

    @objc func saveFileAs() {
        DispatchQueue.main.async {
            self.contentView?.saveFileAs()
        }
    }

    @objc func openFile() {
        contentView?.openFile()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateWebClients()
        }
    }
    
    @objc func importCSV() {
        contentView?.importCSV()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updateWebClients()
        }
    }

    @objc func undo() {
        contentView?.undo()
        updateWebClients()
    }

    @objc func redo() {
        contentView?.redo()
        updateWebClients()
    }
    
    /// Called when the user clicks "New" in the menu.
    @objc func newFile() {
        guard let contentView = contentView else {
            // If there's no main contentView, just open a new window
            closeCurrentWindowAndOpenNewFile(skipSave: true)
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to the current document?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")       // .alertFirstButtonReturn
        alert.addButton(withTitle: "Don't Save") // .alertSecondButtonReturn
        alert.addButton(withTitle: "Cancel")     // .alertThirdButtonReturn

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            // "Save"
            contentView.saveFile()
            closeCurrentWindowAndOpenNewFile(skipSave: true)
            
        case .alertSecondButtonReturn:
            // "Don't Save"
            closeCurrentWindowAndOpenNewFile(skipSave: true)
            
        default:
            // "Cancel" => Do nothing
            return
        }
    }
    
    /// Closes the *current* key window, then launches a new file.
    private func closeCurrentWindowAndOpenNewFile(skipSave: Bool) {
        // Close the old window (the current key window)
        if let oldWindow = NSApp.keyWindow {
            oldWindow.close()
        }
        // Then open a brand-new window
        createNewWindow()
    }

    /// Creates a new window with a fresh ContentView
    private func createNewWindow() {
        // 1) Create a raw ContentView
        let rawContentView = ContentView(currentFileName: .constant("Untitled"))
        
        // 2) Make it the new main contentView for the app
        self.contentView = rawContentView
        
        // 3) Wrap the raw ContentView with environment objects
        let environmentWrappedView = rawContentView
            .environmentObject(self)
            .environmentObject(settingsManager)
        
        // 4) Create a hosting view and window
        let hostingView = NSHostingView(rootView: environmentWrappedView)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.center()
        newWindow.title = "Untitled"
        newWindow.contentView = hostingView
        newWindow.makeKeyAndOrderFront(nil)
    }
    
    // MARK: - Additional code for Keynote or PDF is commented out ...
    //         ...
    
    private func showConversionErrorAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Conversion Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
        
    @objc func handleAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        // Handle any Apple Events here if needed
    }

    func updateFileName(_ name: String) {
        contentView?.currentFileName = name
    }

    func updateWebClients() {
        guard let contentView = contentView else {
            print("ContentView not initialized")
            return
        }
        let updateInfo = contentView.getWebUpdateInfo()
        webServer?.updateCues(
            cueStacks: updateInfo.cueStacks,
            selectedCueStackIndex: updateInfo.selectedIndex,
            activeCueIndex: updateInfo.activeIndex,
            selectedCueIndex: updateInfo.activeIndex
        )
    }

    // MARK: - Preferences, CSV Export, etc.
    @objc func showPreferences() {
        // Implement preferences window
    }

    @objc func exportCSV() {
        guard let contentView = contentView else {
            print("ContentView not initialized")
            return
        }
        
        let updateInfo = contentView.getWebUpdateInfo()
        guard updateInfo.cueStacks.indices.contains(updateInfo.selectedIndex) else {
            print("No valid cue stack selected")
            return
        }
        
        let cueStack = updateInfo.cueStacks[updateInfo.selectedIndex]
        
        // Build CSV rows.
        var csvRows: [String] = []
        let headerRow = cueStack.columns.map { escapeCSVField($0.name) }.joined(separator: ",")
        csvRows.append(headerRow)
        
        for cue in cueStack.cues {
            let row = cue.values.map { escapeCSVField($0) }.joined(separator: ",")
            csvRows.append(row)
        }
        
        let csvString = csvRows.joined(separator: "\n")
        guard let csvData = csvString.data(using: .utf8) else {
            print("Failed to convert CSV string to data")
            return
        }
        
        FileHelper.saveFile(data: csvData, allowedContentTypes: [.commaSeparatedText], defaultFilename: "Export.csv") { result in
            switch result {
            case .success(let url):
                print("CSV exported successfully to \(url)")
            case .failure(let error):
                print("Error exporting CSV: \(error.localizedDescription)")
            }
        }
    }
    
    private func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        } else {
            return field
        }
    }

    // MARK: - Standard Edit Menu
    @objc func cut() {
        let didCut = NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
        if !didCut {
            guard let window = NSApp.keyWindow,
                  let firstResponder = window.firstResponder as? NSTextField else { return }
            
            let text = firstResponder.stringValue
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            firstResponder.stringValue = ""
            
            let notif = Notification(name: NSControl.textDidChangeNotification, object: firstResponder)
            firstResponder.delegate?.controlTextDidChange?(notif)
        }
    }

    @objc func performCopy() {
        let didCopy = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        if !didCopy {
            guard let window = NSApp.keyWindow,
                  let firstResponder = window.firstResponder as? NSTextField else { return }
            
            let text = firstResponder.stringValue
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    @objc func paste() {
        let didPaste = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        if !didPaste {
            guard let window = NSApp.keyWindow,
                  let firstResponder = window.firstResponder as? NSTextField,
                  let pastedValue = NSPasteboard.general.string(forType: .string) else { return }
            
            firstResponder.stringValue = pastedValue
            
            let notif = Notification(name: NSControl.textDidChangeNotification, object: firstResponder)
            firstResponder.delegate?.controlTextDidChange?(notif)
        }
    }

    @objc func delete() {
        NSApp.sendAction(#selector(NSText.delete(_:)), to: nil, from: nil)
    }

    @objc func selectAll() {
        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
    }
    
    @objc func toggleStrikeThrough() {
        // Delegate to ContentView to handle strike-through toggle
        contentView?.toggleStrikeThrough()
    }

    @objc func toggleFullScreen() {
        if let window = NSApp.windows.first {
            window.toggleFullScreen(nil)
        }
    }

    @objc func showHelp() {
        // Implement help functionality
    }
    
    // MARK: - App Termination
    func applicationWillTerminate(_ aNotification: Notification) {
        // Save the currently open file to UserDefaults so it reopens next time
        if let contentView = contentView,
           let currentFileURL = contentView.currentFileURL {
            UserDefaults.standard.set(currentFileURL, forKey: "LastSavedURL")
            print("💾 Saved current file for next launch: \(currentFileURL.path)")
        }
        
        // Clean up web server
        webServer?.stop()
    }
}
