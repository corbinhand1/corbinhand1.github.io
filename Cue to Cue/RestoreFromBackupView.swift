//
//  RestoreFromBackupView.swift
//  Cue to Cue
//
//  Phase 3 of the file-safety audit.
//
//  Lists every available backup of the current document across all tiers
//  (sibling backup, sibling history, Application Support history) with
//  timestamps, file sizes, decode validity, and — for Application Support
//  snapshots — manifest verification (sha256 + byte count).
//
//  Choosing "Restore" snapshots the current in-memory state into the
//  Recovery directory FIRST, then loads the chosen backup. Even the act
//  of restoring can't lose the user's current work.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RestoreFromBackupView: View {
    /// The currently-open document URL, or nil. Used to scope the snapshot
    /// search to the current file.
    let mainFileURL: URL?

    /// Called when the user successfully picks a backup to restore. The
    /// caller should reload the document from the provided URL.
    let onRestore: (URL) -> Void

    /// Called when the sheet is dismissed.
    let onCancel: () -> Void

    @State private var snapshots: [BackupManager.Snapshot] = []
    @State private var selected: BackupManager.Snapshot?
    @State private var isLoading: Bool = true
    @State private var includeOtherDocuments: Bool = false
    @State private var confirmRestore: Bool = false

    private let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 820, idealWidth: 900, minHeight: 560, idealHeight: 640)
        .onAppear { reload() }
        .alert("Restore this backup?", isPresented: $confirmRestore) {
            Button("Restore", role: .destructive) {
                if let s = selected {
                    onRestore(s.url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let s = selected {
                Text("Your current document will be saved to a recovery file first. Then \(s.displayFileName) (saved \(dateFormatter.string(from: s.date))) will be loaded from \(s.locationTitle.lowercased()).")
            } else {
                Text("Pick a backup to restore.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Restore from Backup")
                .font(.title2)
                .fontWeight(.semibold)

            Text(headerSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            backupLocationsLegend
        }
        .padding()
    }

    private var headerSubtitle: String {
        if let url = mainFileURL {
            return "Backups of \(url.lastPathComponent), newest first. Cue to Cue keeps one copy on your Desktop and one in its library. Older backup locations are shown for restore only."
        } else {
            return "No document is currently open. Showing backups from Cue to Cue's library."
        }
    }

    private var backupLocationsLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Where backups are stored")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                legendItem(
                    title: "Desktop backup folder",
                    detail: "~/Desktop/Cue to Cue Backups"
                )
                legendItem(
                    title: "App backup library",
                    detail: "~/Library/.../Cue to Cue/Backups"
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .cornerRadius(8)
    }

    private func legendItem(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack {
                ProgressView("Scanning backups…")
                    .padding()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if snapshots.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "tray.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No backups found")
                    .font(.headline)
                Text(noBackupsMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            VStack(spacing: 0) {
                Table(snapshots, selection: Binding(
                    get: { selected?.id },
                    set: { newID in
                        selected = snapshots.first(where: { $0.id == newID })
                    }
                )) {
                    TableColumn("Saved") { s in
                        Text(dateFormatter.string(from: s.date))
                            .font(.system(.body, design: .monospaced))
                    }
                    .width(min: 170, ideal: 190)

                    TableColumn("Where") { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.locationTitle)
                            Text(s.shortenedFolderPath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .width(min: 220, ideal: 260)

                    TableColumn("Backup File") { s in
                        Text(s.displayFileName)
                            .lineLimit(2)
                    }
                    .width(min: 180, ideal: 220)

                    TableColumn("Size") { s in
                        Text(byteFormatter.string(fromByteCount: s.byteCount))
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 70, ideal: 80)

                    TableColumn("Status") { s in
                        validityBadge(for: s)
                    }
                    .width(min: 110, ideal: 120)
                }
                .contextMenu(forSelectionType: BackupManager.Snapshot.ID.self) { ids in
                    if let id = ids.first, let snap = snapshots.first(where: { $0.id == id }) {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([snap.url])
                        }
                        Button("Copy Path") {
                            copyPath(snap.shortenedPath)
                        }
                    }
                }

                Divider()
                selectionDetail
            }
        }
    }

    private var selectionDetail: some View {
        Group {
            if let snapshot = selected {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snapshot.displayFileName)
                                .font(.headline)
                            Text(snapshot.locationTitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([snapshot.url])
                        }

                        Button("Copy Path") {
                            copyPath(snapshot.shortenedPath)
                        }
                    }

                    Text(snapshot.locationExplanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Full path")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        Text(snapshot.shortenedPath)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .padding(16)
            } else {
                Text("Select a backup above to see its full path and location.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
    }

    private var noBackupsMessage: String {
        if mainFileURL != nil {
            return "Cue to Cue creates backup files automatically every time you save. If you've never saved this document, there are no backups yet."
        } else {
            return "Open a document first to see its backups, or check Application Support → Cue to Cue → Backups in Finder."
        }
    }

    @ViewBuilder
    private func validityBadge(for s: BackupManager.Snapshot) -> some View {
        HStack(spacing: 6) {
            if s.isValid && s.manifestVerified == true {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Verified")
            } else if s.isValid {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                Text("OK")
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Bad file")
            }
        }
        .font(.caption)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Toggle("Include backups of other documents", isOn: $includeOtherDocuments)
                .onChange(of: includeOtherDocuments) { _, _ in reload() }
                .help("Lists every backup in Application Support, not just the current document.")

            Spacer()

            Button("Reveal Backups Folder") {
                if let url = BackupManager.shared.revealableBackupURL(forMainFile: mainFileURL) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }

            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button("Restore Selected…") {
                guard selected != nil else { return }
                confirmRestore = true
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selected == nil || (selected?.isValid == false))
        }
        .padding()
    }

    // MARK: - Loading

    private func reload() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result: [BackupManager.Snapshot]
            if includeOtherDocuments {
                result = BackupManager.shared.discoverAllAppSupportSnapshots()
            } else {
                result = BackupManager.shared.discoverSnapshots(forMainFile: mainFileURL)
            }
            DispatchQueue.main.async {
                self.snapshots = result
                self.selected = result.first
                self.isLoading = false
            }
        }
    }

    private func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}

#Preview {
    RestoreFromBackupView(
        mainFileURL: nil,
        onRestore: { _ in },
        onCancel: {}
    )
}
