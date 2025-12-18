//
//  DebugWindowView.swift
//  Cue to Cue
//
//  Professional debug console window view
//

import SwiftUI
import AppKit

struct DebugWindowView: View {
    @ObservedObject private var logManager = LogManager.shared
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var showInfoOnly = true
    @State private var showWarnings = true
    @State private var showErrors = true
    @State private var showDebug = false
    @FocusState private var isSearchFocused: Bool
    @State private var selectedLogId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Professional Toolbar
            toolbarView
            
            Divider()
            
            // Log Content Area
            logContentView
            
            // Professional Footer
            footerView
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            setupWindow()
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbarView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Search Bar
                searchBarView
                
                Spacer()
                
                // Filter Buttons Group
                filterButtonsGroup
                
                Divider()
                    .frame(height: 20)
                
                // Action Buttons
                actionButtonsGroup
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
    
    private var searchBarView: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            
            TextField("Search logs...", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit {
                    // Search submitted
                }
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .frame(maxWidth: 350)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSearchFocused ? Color.accentColor : Color.clear, lineWidth: 1)
        )
    }
    
    private var filterButtonsGroup: some View {
        HStack(spacing: 6) {
            FilterButton(
                title: "Info",
                icon: "info.circle.fill",
                isOn: $showInfoOnly,
                count: infoCount,
                color: .blue
            )
            
            FilterButton(
                title: "Warnings",
                icon: "exclamationmark.triangle.fill",
                isOn: $showWarnings,
                count: warningCount,
                color: .orange
            )
            
            FilterButton(
                title: "Errors",
                icon: "xmark.circle.fill",
                isOn: $showErrors,
                count: errorCount,
                color: .red
            )
            
            FilterButton(
                title: "Debug",
                icon: "ladybug.fill",
                isOn: $showDebug,
                count: debugCount,
                color: .purple
            )
        }
    }
    
    private var actionButtonsGroup: some View {
        HStack(spacing: 8) {
            // Pause/Resume button
            Button(action: {
                logManager.togglePause()
            }) {
                Image(systemName: logManager.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .foregroundColor(logManager.isPaused ? .orange : .accentColor)
            }
            .buttonStyle(.plain)
            .help(logManager.isPaused ? "Resume capturing logs" : "Pause capturing logs")
            .keyboardShortcut("p", modifiers: [.command, .shift])
            
            // Auto-scroll toggle
            Button(action: { autoScroll.toggle() }) {
                Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .foregroundColor(autoScroll ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Auto-scroll to bottom")
            .keyboardShortcut("a", modifiers: [.command, .shift])
            
            // Clear button
            Button(action: {
                withAnimation {
                    logManager.clearLogs()
                }
            }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("Clear all logs (⌘K)")
            .keyboardShortcut("k", modifiers: .command)
            
            // Export button
            Button(action: exportLogs) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .help("Export logs (⌘E)")
            .keyboardShortcut("e", modifiers: .command)
        }
    }
    
    // MARK: - Log Content
    
    private var logContentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filteredLogs.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(filteredLogs) { entry in
                            LogRowView(
                                entry: entry,
                                searchText: searchText,
                                isSelected: selectedLogId == entry.id
                            )
                            .id(entry.id)
                            .onTapGesture {
                                selectedLogId = entry.id
                            }
                            .contextMenu {
                                Button("Copy") {
                                    copyLog(entry)
                                }
                                .keyboardShortcut("c", modifiers: .command)
                                
                                Button("Copy All") {
                                    copyAllLogs()
                                }
                            }
                        }
                    }
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: filteredLogs.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: autoScroll) { oldValue, newValue in
                if newValue {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty ? "doc.text" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(searchText.isEmpty ? "No logs yet" : "No logs match your search")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            if !searchText.isEmpty {
                Text("Try adjusting your search or filters")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 120)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack(spacing: 12) {
            // Stats
            HStack(spacing: 16) {
                if !searchText.isEmpty {
                    Label("\(filteredLogs.count) results", systemImage: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Label("\(filteredLogs.count) of \(logManager.logs.count) logs", systemImage: "list.bullet")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 6) {
                if logManager.isPaused {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .shadow(color: Color.orange.opacity(0.5), radius: 3)
                    
                    Text("Paused")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                } else if logManager.isCapturing {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: Color.green.opacity(0.5), radius: 3)
                    
                    Text("Capturing")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Computed Properties
    
    var filteredLogs: [LogEntry] {
        var filtered = logManager.logs
        
        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.message.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Filter by log level
        filtered = filtered.filter { entry in
            switch entry.level {
            case .info: return showInfoOnly
            case .warning: return showWarnings
            case .error: return showErrors
            case .debug: return showDebug
            }
        }
        
        return filtered
    }
    
    private var infoCount: Int {
        logManager.logs.filter { $0.level == .info }.count
    }
    
    private var warningCount: Int {
        logManager.logs.filter { $0.level == .warning }.count
    }
    
    private var errorCount: Int {
        logManager.logs.filter { $0.level == .error }.count
    }
    
    private var debugCount: Int {
        logManager.logs.filter { $0.level == .debug }.count
    }
    
    // MARK: - Helper Methods
    
    private func setupWindow() {
        if !logManager.isCapturing {
            logManager.startCapturing()
        }
        logManager.addLog("Debug Console opened", level: .info)
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard autoScroll, let lastLog = filteredLogs.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastLog.id, anchor: .bottom)
        }
    }
    
    private func copySelectedLog() {
        if let selectedId = selectedLogId,
           let entry = logManager.logs.first(where: { $0.id == selectedId }) {
            copyLog(entry)
        }
    }
    
    private func copyLog(_ entry: LogEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.formattedString, forType: .string)
    }
    
    private func copyAllLogs() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logManager.exportLogs(), forType: .string)
    }
    
    private func exportLogs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text]
        savePanel.nameFieldStringValue = "CueToCue-Debug-\(formattedDateString()).txt"
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    let logText = logManager.exportLogs()
                    try logText.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    logManager.logError("Failed to export logs: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func formattedDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}

// MARK: - Filter Button

struct FilterButton: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    let count: Int
    let color: Color
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                
                if count > 0 {
                    Text("(\(count))")
                        .font(.system(size: 10))
                        .opacity(0.7)
                }
            }
            .foregroundColor(isOn ? .white : color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOn ? color : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isOn ? color : color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Log Row View

struct LogRowView: View {
    let entry: LogEntry
    let searchText: String
    let isSelected: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp (static string, pre-formatted at log creation - never updates)
            Text(verbatim: entry.formattedTimestamp)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 85, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            
            // Level Badge
            levelBadge
                .frame(width: 35, alignment: .leading)
            
            // Message with search highlighting
            messageView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(backgroundColor)
        .overlay(
            Rectangle()
                .frame(width: 3)
                .foregroundColor(levelColor)
                .opacity(isSelected ? 1 : 0),
            alignment: .leading
        )
    }
    
    private var levelBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(levelColor)
                .frame(width: 7, height: 7)
            
            Text(entry.level.emoji)
                .font(.system(size: 9))
        }
    }
    
    private var messageView: some View {
        highlightSearchText(entry.message)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func highlightSearchText(_ text: String) -> some View {
        if searchText.isEmpty {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(messageColor)
        } else {
            // Simple highlighting - show text with background color for matches
            // For complex highlighting, we'll use a simpler approach
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(messageColor)
                .background(
                    text.lowercased().contains(searchText.lowercased()) ?
                    Color.accentColor.opacity(0.15) : Color.clear
                )
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.1)
        } else if entry.level == .error {
            return Color.red.opacity(0.05)
        } else {
            return Color.clear
        }
    }
    
    private var levelColor: Color {
        switch entry.level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .debug: return .purple
        }
    }
    
    private var messageColor: Color {
        switch entry.level {
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        case .debug: return .secondary
        }
    }
}

