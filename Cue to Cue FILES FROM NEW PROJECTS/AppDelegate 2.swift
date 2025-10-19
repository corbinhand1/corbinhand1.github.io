//
//  AppDelegate 2.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 11/14/24.
//


//
//  AppDelegate.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/28/24.
//

import SwiftUI
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var contentView: ContentView?
    var webServer: WebServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up application
        webServer = WebServer()
        
        let port: UInt16 = 8080
        webServer?.start(port: port)
        
        if let ipAddress = webServer?.getLocalIPAddress() {
            let url = "http://\(ipAddress):\(port)"
            print("Web server accessible at: \(url)")
            DispatchQueue.main.async {
                self.showLocalURL(url)
            }
        } else {
            print("Unable to determine local IP address")
        }
        
        // Initialize ContentView if it hasn't been set
        if contentView == nil {
            contentView = ContentView(currentFileName: .constant("Untitled"))
        }
        
        // Perform initial update of web clients
        updateWebClients()
        
        // Request Apple Events access
        requestAppleEventsAccess()
    }

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
    
    // Menu actions
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
    
    @objc func openKeynotePreview() {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true // Ensure we can choose files
            
            let keynoteTypes = [
                UTType(filenameExtension: "key"),
                UTType(filenameExtension: "keynote"),
                UTType(filenameExtension: "pdf") // Allow PDFs as well
            ].compactMap { $0 }
            
            panel.allowedContentTypes = keynoteTypes
            
            panel.beginSheetModal(for: NSApp.keyWindow!) { response in
                if response == .OK, let url = panel.url {
                    if url.pathExtension.lowercased() == "pdf" {
                        // Directly show the PDF
                        DispatchQueue.main.async {
                            self.showKeynotePreviewWindow(pdfURL: url)
                        }
                    } else {
                        // Convert Keynote file to PDF
                        self.convertKeynoteWithPermissionCheck(keynoteURL: url)
                    }
                }
            }
        }
    }
        
    private func convertKeynoteWithPermissionCheck(keynoteURL: URL) {
        let appleEventManager = NSAppleEventManager.shared()
        let keynoteSignature = AEEventClass(kCoreEventClass)
        let keynoteID = AEEventID(kAEOpenDocuments)
        
        appleEventManager.setEventHandler(self, andSelector: #selector(handleAppleEvent(_:withReplyEvent:)), forEventClass: keynoteSignature, andEventID: keynoteID)
        
        KeynoteConverter.convertToPDF(keynoteURL: keynoteURL) { result in
            switch result {
            case .success(let pdfURL):
                DispatchQueue.main.async {
                    self.showKeynotePreviewWindow(pdfURL: pdfURL)
                }
            case .failure(let error):
                if (error as NSError).code == -1743 {
                    DispatchQueue.main.async {
                        self.showAppleEventsPermissionAlert()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.showConversionErrorAlert(error: error)
                    }
                }
            }
        }
    }
        
    private func showKeynotePreviewWindow(pdfURL: URL) {
        // Get notes for this PDF file
        let pdfFileName = pdfURL.lastPathComponent
        let notesForPDF = contentView?.pdfNotes[pdfFileName] ?? [:]
        
        let previewWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let keynotePreviewView = KeynotePreviewWindow(pdfURL: pdfURL, initialNotes: notesForPDF) { updatedNotes in
            // Save the updated notes back to ContentView
            self.contentView?.pdfNotes[pdfFileName] = updatedNotes
            // Ensure that the ContentView saves the state with the updated notes
            self.contentView?.saveState()
        }
        let hostingView = NSHostingView(rootView: keynotePreviewView)
        previewWindow.contentView = hostingView
        previewWindow.makeKeyAndOrderFront(nil)
    }
        
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
        
        // Use the new function that updates both cues and clock state
        contentView.updateWebClientsWithClockState()
    }

    // Menu action methods
    @objc func showPreferences() {
        // Implement preferences window
    }

    @objc func newFile() {
        // Implement new file creation
    }

    @objc func exportCSV() {
        // Implement CSV export
    }

    @objc func cut() {
        NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
    }

    @objc func performCopy() {
        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
    }

    @objc func paste() {
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    }

    @objc func delete() {
        NSApp.sendAction(#selector(NSText.delete(_:)), to: nil, from: nil)
    }

    @objc func selectAll() {
        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
    }

    @objc func toggleFullScreen() {
        if let window = NSApp.windows.first {
            window.toggleFullScreen(nil)
        }
    }

    @objc func showHelp() {
        // Implement help functionality
    }
}