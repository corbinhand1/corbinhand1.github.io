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
    static let appDelegateDuplicateFile = Notification.Name("appDelegateDuplicateFile")
    static let appDelegateImportCSV = Notification.Name("appDelegateImportCSV")
    static let appDelegateExportCSV = Notification.Name("appDelegateExportCSV")
    static let appDelegatePublishWebsite = Notification.Name("appDelegatePublishWebsite")
    static let appDelegateShowWebsite = Notification.Name("appDelegateShowWebsite")
    static let appDelegateShowAIImport = Notification.Name("appDelegateShowAIImport")
    static let appDelegateShowFindReplace = Notification.Name("appDelegateShowFindReplace")
    static let appDelegateToggleCueStacks = Notification.Name("appDelegateToggleCueStacks")
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
    /// Menu: show-running command (object: KeyboardShortcut id, e.g. "countdownStart").
    static let appDelegateShowCommand = Notification.Name("appDelegateShowCommand")
    static let appDelegateShowViewers = Notification.Name("appDelegateShowViewers")
    static let appDelegateShowUsers = Notification.Name("appDelegateShowUsers")
    static let appDelegateShowShortcuts = Notification.Name("appDelegateShowShortcuts")
    /// Posted when the app becomes the frontmost app. ContentView observes
    /// this to re-check whether the current document was changed by another
    /// program while we were in the background. Phase 2 of the file-safety
    /// audit.
    static let appDelegateDidBecomeActive = Notification.Name("appDelegateDidBecomeActive")
    /// Phase 3: open the Restore-from-Backup sheet.
    static let appDelegateRestoreFromBackup = Notification.Name("appDelegateRestoreFromBackup")
    /// Phase 3: reveal the most useful backup folder for the current document
    /// in Finder.
    static let appDelegateRevealBackups = Notification.Name("appDelegateRevealBackups")
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
        
        // Single-window app: no "Show Tab Bar" / "Show All Tabs" in View.
        NSWindow.allowsAutomaticWindowTabbing = false
        // View ▸ Toggle Full Screen is our own item; don't let AppKit add a second.
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")

        // Start intercepting print statements to capture console output
        PrintInterceptor.shared.startIntercepting()
        
        // Log app launch (PrintInterceptor captures print() into the debug console)
        print("Cue to Cue app launched")
        
        // File opens from Finder are drained in ContentView.onAppear once
        // notification observers are registered (avoids a launch-time race).

        #if DEBUG
        WindowSnapshotter.scheduleIfRequested()
        #endif
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Cleanup is handled by ContentView's WebServer
    }

    // MARK: - Quit safety

    /// Installed by ContentView. Saves (or asks to save) unsaved changes and
    /// calls back with `true` when it is safe to quit.
    var prepareForTermination: ((@escaping (Bool) -> Void) -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let prepare = prepareForTermination else { return .terminateNow }
        // Reply asynchronously: replying from inside this call is not allowed.
        DispatchQueue.main.async {
            prepare { canQuit in
                sender.reply(toApplicationShouldTerminate: canQuit)
            }
        }
        return .terminateLater
    }

    /// Cue to Cue is a single-window app; closing the window quits (through
    /// the same unsaved-changes check as Cmd-Q).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Phase 2 of the file-safety audit: when the user comes back to the
        // app, we want to re-check whether anything changed our open file
        // while we were away (iCloud pulled down a server version, the user
        // edited the file in another app, restored from a backup, etc.).
        NotificationCenter.default.post(name: .appDelegateDidBecomeActive, object: nil)
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

    func duplicateFile() {
        NotificationCenter.default.post(name: .appDelegateDuplicateFile, object: nil)
    }
    
    func importCSV() {
        // Post notification to trigger ContentView's showImportCSVPanel
        NotificationCenter.default.post(name: .appDelegateImportCSV, object: nil)
    }
    
    func exportCSV() {
        // Post notification for ContentView to handle
        NotificationCenter.default.post(name: .appDelegateExportCSV, object: nil)
    }

    func publishToWebsite() {
        NotificationCenter.default.post(name: .appDelegatePublishWebsite, object: nil)
    }

    func showWebsitePanel() {
        NotificationCenter.default.post(name: .appDelegateShowWebsite, object: nil)
    }

    func showAIImport() {
        NotificationCenter.default.post(name: .appDelegateShowAIImport, object: nil)
    }

    /// Cue and Timer menu items (ids match Settings ▸ Keyboard Shortcuts).
    func runShowCommand(_ id: String) {
        NotificationCenter.default.post(name: .appDelegateShowCommand, object: id)
    }

    func showConnectedViewers() {
        NotificationCenter.default.post(name: .appDelegateShowViewers, object: nil)
    }

    func showUserManagement() {
        NotificationCenter.default.post(name: .appDelegateShowUsers, object: nil)
    }

    func showKeyboardShortcuts() {
        NotificationCenter.default.post(name: .appDelegateShowShortcuts, object: nil)
    }

    func restoreFromBackup() {
        NotificationCenter.default.post(name: .appDelegateRestoreFromBackup, object: nil)
    }

    func revealBackupsInFinder() {
        NotificationCenter.default.post(name: .appDelegateRevealBackups, object: nil)
    }
    
    func openFileAtURL(_ url: URL) {
        guard CueStackDocumentType.shouldOpen(at: url) else {
            print("Ignored open request for non-document file: \(url.lastPathComponent)")
            return
        }

        pendingFileToOpen = url
        if ContentViewLifecycleSetup.appDelegateNotificationsRegistered {
            NotificationCenter.default.post(name: .appDelegateOpenFile, object: url)
        }
    }
    
    // MARK: - Edit Operations
    
    private static let undoSelector = Selector(("undo:"))
    private static let redoSelector = Selector(("redo:"))

    func undo() {
        // When a cue cell is being edited, undo belongs to the text field,
        // not the cue-stack history.
        if isTextFieldEditing(),
           performStandardEditAction(Self.undoSelector) {
            return
        }
        NotificationCenter.default.post(name: .appDelegateUndo, object: nil)
    }
    
    func redo() {
        if isTextFieldEditing(),
           performStandardEditAction(Self.redoSelector) {
            return
        }
        NotificationCenter.default.post(name: .appDelegateRedo, object: nil)
    }

    /// Routes undo/redo/cut/copy/paste to the current text editor when one
    /// has focus. Returns true if the action was handled.
    @discardableResult
    private func performStandardEditAction(_ selector: Selector) -> Bool {
        if NSApp.sendAction(selector, to: NSApp.keyWindow?.firstResponder, from: nil) {
            return true
        }
        return NSApp.sendAction(selector, to: nil, from: nil)
    }

    private func isTextFieldEditing() -> Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder else { return false }
        if firstResponder is NSTextView {
            return true
        }
        if let textField = firstResponder as? NSTextField,
           textField.currentEditor() != nil {
            return true
        }
        return false
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
        openFileAtURL(url)
        return CueStackDocumentType.shouldOpen(at: url)
    }
    
    func application(_ application: NSApplication, openFiles filenames: [String]) {
        guard let firstFile = filenames.first else { return }
        let url = URL(fileURLWithPath: firstFile)
        openFileAtURL(url)
    }
}


// MARK: - Main window close button

/// Routes the main window's red close button through NSApp.terminate so the
/// unsaved-changes check runs *before* the window disappears. (If the window
/// closed first and the user then cancelled, the app would be left running
/// with no window and a stale document.)
struct MainWindowCloseInterceptor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = InterceptorView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class InterceptorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let closeButton = window?.standardWindowButton(.closeButton) else { return }
            closeButton.target = NSApp
            closeButton.action = #selector(NSApplication.terminate(_:))
        }
    }
}


#if DEBUG
extension Notification.Name {
    /// Debug snapshots: select the cue at this index (object: Int).
    static let debugSelectCue = Notification.Name("debugSelectCue")
}

/// Development aid: renders the app's own main window to a PNG, so UI
/// changes can be checked without screen-recording permission.
///
///   CUE_SNAPSHOT_PATH=/tmp/shot.png   where to write (required)
///   CUE_SNAPSHOT_DELAY=4              seconds after launch
///   CUE_SNAPSHOT_SIZE=1440x900        window content size
///   CUE_SNAPSHOT_QUIT=1               quit after writing
///   CUE_SNAPSHOT_SELECT_CUE=3         select this cue first (shows LIVE/NEXT)
enum WindowSnapshotter {
    /// True for a snapshot run: documents are opened read-only.
    static var isActive: Bool {
        !(ProcessInfo.processInfo.environment["CUE_SNAPSHOT_PATH"] ?? "").isEmpty
    }

    static func scheduleIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["CUE_SNAPSHOT_PATH"], !path.isEmpty else { return }
        let delay = Double(env["CUE_SNAPSHOT_DELAY"] ?? "") ?? 4
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let size = env["CUE_SNAPSHOT_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2,
               let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                window.setContentSize(NSSize(width: size[0], height: size[1]))
                window.center()
            }
        }
        if let perfPath = env["CUE_PERF_SCROLL"], !perfPath.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1, delay - 2.5)) {
                runScrollBenchmark(outputPath: perfPath)
            }
        }
        if let panel = env["CUE_SNAPSHOT_OPEN"], !panel.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1, delay - 2)) {
                let names: [String: Notification.Name] = [
                    "viewers": .appDelegateShowViewers, "users": .appDelegateShowUsers,
                    "settings": .appDelegateShowPreferences, "website": .appDelegateShowWebsite,
                    "ai": .appDelegateShowAIImport, "find": .appDelegateShowFindReplace,
                    "shortcuts": .appDelegateShowShortcuts,
                ]
                let commands: [String: (Notification.Name, Any?)] = [
                    "playlist": (.appDelegateShowCommand, "countdownPlaylist"),
                    "print": (Notification.Name("TriggerPrint"), nil),
                    "export": (.appDelegateExportCSV, nil),
                    "restore": (.appDelegateRestoreFromBackup, nil),
                ]
                if let name = names[panel] {
                    NotificationCenter.default.post(name: name, object: nil)
                } else if let (name, object) = commands[panel] {
                    NotificationCenter.default.post(name: name, object: object)
                }
            }
        }
        if let cue = env["CUE_SNAPSHOT_SELECT_CUE"].flatMap(Int.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1, delay - 1.5)) {
                NotificationCenter.default.post(name: .debugSelectCue, object: cue)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let menuPath = env["CUE_DUMP_MENUS"], !menuPath.isEmpty {
                try? dumpMenus().write(toFile: menuPath, atomically: true, encoding: .utf8)
            }
            write(to: URL(fileURLWithPath: path))
            if env["CUE_SNAPSHOT_QUIT"] == "1" {
                // Exit directly: a snapshot run is read-only and must never
                // stop at a save or conflict prompt (which left copies open).
                exit(0)
            }
        }
    }

    /// CUE_PERF_SCROLL=/tmp/out.txt: scroll the cue list top to bottom and
    /// back in 30-point steps, timing layout + draw for each step.
    static func runScrollBenchmark(outputPath: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let root = window.contentView else { return }
        func scrollViews(in view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(scrollViews)
        }
        let all = scrollViews(in: root)
        let inventory = all.map { sv in
            String(format: "%@ frame=%.0fx%.0f doc=%@ %.0fx%.0f", String(describing: type(of: sv)),
                   sv.frame.width, sv.frame.height,
                   String(describing: type(of: sv.documentView as Any)),
                   sv.documentView?.frame.width ?? 0, sv.documentView?.frame.height ?? 0)
        }.joined(separator: "\n")
        try? inventory.write(toFile: outputPath + ".inventory", atomically: true, encoding: .utf8)
        // The cue list is the tallest vertical scroller.
        guard let scroll = all
            .filter({ ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height })
            .max(by: { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }) else {
            try? "no scrollable list found".write(toFile: outputPath, atomically: true, encoding: .utf8)
            return
        }
        let clip = scroll.contentView
        let maxY = (scroll.documentView?.frame.height ?? 0) - clip.bounds.height
        var samples: [Double] = []
        var y: CGFloat = 0
        var direction: CGFloat = 1
        for _ in 0..<240 {
            y = min(max(0, y + 30 * direction), maxY)
            if y >= maxY || y <= 0 { direction *= -1 }
            let start = CACurrentMediaTime()
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            scroll.reflectScrolledClipView(clip)
            root.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date())   // let SwiftUI apply pending updates
            root.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            samples.append((CACurrentMediaTime() - start) * 1000)
        }
        let sorted = samples.sorted()
        let avg = samples.reduce(0, +) / Double(samples.count)
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        let over16 = samples.filter { $0 > 16.7 }.count
        let report = String(format: "steps=%d avg=%.2fms p95=%.2fms max=%.2fms frames>16.7ms=%d docHeight=%.0f",
                            samples.count, avg, p95, sorted.last ?? 0, over16, scroll.documentView?.frame.height ?? 0)
        try? report.write(toFile: outputPath, atomically: true, encoding: .utf8)
        NSLog("ScrollBenchmark: \(report)")
    }

    /// Text outline of the menu bar as macOS assembled it (CUE_DUMP_MENUS).
    static func dumpMenus() -> String {
        func describe(_ menu: NSMenu, depth: Int) -> [String] {
            menu.items.flatMap { item -> [String] in
                if item.isHidden { return [] }
                if item.isSeparatorItem { return [String(repeating: "  ", count: depth) + "----"] }
                var key = ""
                if !item.keyEquivalent.isEmpty {
                    let m = item.keyEquivalentModifierMask
                    key = (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "")
                        + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "")
                        + (item.keyEquivalent == "\u{8}" || item.keyEquivalent == "\u{7f}" ? "⌫" : item.keyEquivalent.uppercased())
                }
                let line = String(repeating: "  ", count: depth) + item.title
                    + (key.isEmpty ? "" : "   [\(key)]") + (item.isEnabled ? "" : "   (disabled)")
                return [line] + (item.submenu.map { describe($0, depth: depth + 1) } ?? [])
            }
        }
        guard let main = NSApp.mainMenu else { return "no main menu" }
        return describe(main, depth: 0).joined(separator: "\n")
    }

    static func write(to url: URL) {
        // Prefer an open sheet or settings window over the main window.
        let main = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.sheetParent == nil })
        let target = main?.attachedSheet
            ?? NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue.contains("Settings") == true })
            ?? main
        guard let window = target,
              let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            NSLog("WindowSnapshotter: no window to capture. Windows: %@",
                  NSApp.windows.map { "\(type(of: $0)) visible=\($0.isVisible) sheet=\($0.sheetParent != nil) frame=\($0.frame)" }.joined(separator: " | "))
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        NSLog("WindowSnapshotter: wrote \(url.path)")
    }
}
#endif
