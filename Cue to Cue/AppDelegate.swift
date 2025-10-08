//
//  AppDelegate.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 5/31/24.
//

import Cocoa
import SwiftUI
import Combine

@main
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
        webServer?.start(port: 8080)
        
        // Create the SwiftUI view that provides the window contents.
        let contentView = ContentView().environmentObject(self)

        // Create the window and set the content view.
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Clean up web server
        webServer?.stop()
    }
}
