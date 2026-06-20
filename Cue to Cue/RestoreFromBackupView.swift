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
        .frame(minWidth: 720, minHeight: 480)
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
                Text("Your current document will be saved to a recovery file first. Then \(s.url.lastPathComponent) (saved \(dateFormatter.string(from: s.date))) will be loaded.")
            } else {
                Text("Pick a backup to restore.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Restore from Backup")
                .font(.title2)
                .fontWeight(.semibold)
            Text(headerSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var headerSubtitle: String {
        if let url = mainFileURL {
            return "Showing every known backup of \(url.lastPathComponent) across all tiers, newest first. Your current document is preserved automatically when you restore."
        } else {
            return "No document is currently open. Showing backups from Application Support history."
        }
    }

    // MARK: - Content (the table)

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
                .width(min: 160, ideal: 180)

                TableColumn("Tier") { s in
                    Text(s.tierLabel)
                }
                .width(min: 140, ideal: 160)

                TableColumn("Size") { s in
                    Text(byteFormatter.string(fromByteCount: s.byteCount))
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 90)

                TableColumn("Validity") { s in
                    validityBadge(for: s)
                }
                .width(min: 130, ideal: 150)

                TableColumn("Path") { s in
                    Text(s.url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .help(s.url.path)
                }
            }
            .contextMenu(forSelectionType: BackupManager.Snapshot.ID.self) { ids in
                if let id = ids.first, let snap = snapshots.first(where: { $0.id == id }) {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([snap.url])
                    }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(snap.url.path, forType: .string)
                    }
                }
            }
        }
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
                Text("Decodes OK")
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Decode failed")
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
}

#Preview {
    RestoreFromBackupView(
        mainFileURL: nil,
        onRestore: { _ in },
        onCancel: {}
    )
}
