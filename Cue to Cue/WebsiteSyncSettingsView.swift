//
//  WebsiteSyncSettingsView.swift
//  Cue to Cue
//
//  The Website panel: publishing status, Publish Now, the library of
//  published show files, and the GitHub connection settings. Shown as a
//  Settings tab and as its own window (File › Website…).
//

import SwiftUI
import AppKit

struct WebsiteSyncSettingsView: View {
    @EnvironmentObject private var websiteSyncManager: WebsiteSyncManager

    /// Publishes the open show. Nil where no show is available (Settings).
    var publishCurrentShow: (() -> Void)? = nil
    /// File name of the open show, for the Publish button.
    var currentShowName: String? = nil
    var onClose: (() -> Void)? = nil

    @State private var tokenDraft = ""
    @State private var isEditingToken = false
    @State private var tokenError: String?
    @State private var ownerDraft = ""
    @State private var repoDraft = ""
    @State private var renamingSlug: String?
    @State private var renameDraft = ""
    @State private var pendingRemoval: ShowLibraryEntry?
    @State private var actionError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statusCard
                    librarySection
                    connectionSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear {
            let repo = websiteSyncManager.repository
            ownerDraft = repo.owner
            repoDraft = repo.name
            if case .unknown = websiteSyncManager.connection {
                Task { await websiteSyncManager.checkConnection() }
            }
        }
        .confirmationDialog(
            "Remove \u{201C}\(pendingRemoval?.name ?? "")\u{201D} from the website?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove from Website", role: .destructive) {
                if let entry = pendingRemoval { remove(entry) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("The show disappears from the website's show list. Your show file on this Mac isn't touched, and you can publish it again any time.")
        }
        .alert("Couldn't Update the Website", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK") {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Website").font(.title2.weight(.semibold))
                Link(WebsiteSyncSettingsKeys.siteURL.absoluteString.replacingOccurrences(of: "https://", with: ""),
                     destination: WebsiteSyncSettingsKeys.siteURL)
                    .font(.callout)
            }
            Spacer()
            if let onClose {
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                statusIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle).font(.headline)
                    Text(statusDetail)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let url = websiteSyncManager.lastCommitURL, case .success = websiteSyncManager.syncStatus {
                        Link("View the change on GitHub", destination: url).font(.callout)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                if let publishCurrentShow {
                    Button {
                        publishCurrentShow()
                    } label: {
                        Label(publishButtonTitle, systemImage: "icloud.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(websiteSyncManager.isSyncing || !websiteSyncManager.hasToken)
                    .help("File › Publish to Website (⇧⌘U)")
                }
                Button("Check Connection") {
                    Task { await websiteSyncManager.checkConnection() }
                }
                .disabled(websiteSyncManager.isSyncing || !websiteSyncManager.hasToken)
                Button("Open Website") { NSWorkspace.shared.open(WebsiteSyncSettingsKeys.siteURL) }
                if websiteSyncManager.isSyncing { ProgressView().controlSize(.small) }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
    }

    private var publishButtonTitle: String {
        if let name = currentShowName, !name.isEmpty { return "Publish \u{201C}\(name)\u{201D}" }
        return "Publish Now"
    }

    @ViewBuilder
    private var statusIcon: some View {
        let (symbol, color): (String, Color) = {
            switch websiteSyncManager.syncStatus {
            case .syncing: return ("arrow.triangle.2.circlepath", .accentColor)
            case .failed: return ("exclamationmark.triangle.fill", .orange)
            case .success: return ("checkmark.circle.fill", .green)
            case .idle:
                switch websiteSyncManager.connection {
                case .connected: return ("checkmark.circle.fill", .green)
                case .failed: return ("exclamationmark.triangle.fill", .orange)
                case .notConfigured: return ("key.fill", .secondary)
                case .checking, .unknown: return ("network", .secondary)
                }
            }
        }()
        Image(systemName: symbol)
            .font(.system(size: 24))
            .foregroundColor(color)
            .frame(width: 30)
            .accessibilityHidden(true)
    }

    private var statusTitle: String {
        switch websiteSyncManager.syncStatus {
        case .syncing: return "Publishing…"
        case .failed: return "Publishing failed"
        case .success: return "Published"
        case .idle:
            switch websiteSyncManager.connection {
            case .connected: return "Connected"
            case .checking: return "Checking connection…"
            case .notConfigured: return "Set up publishing"
            case .failed: return "Can't connect"
            case .unknown: return "Website"
            }
        }
    }

    private var statusDetail: String {
        var lines: [String] = []
        switch websiteSyncManager.syncStatus {
        case .failed(let message): lines.append(message)
        default: break
        }
        switch websiteSyncManager.connection {
        case .connected(let login): lines.append("Signed in to GitHub as \(login) · \(websiteSyncManager.repository)")
        case .failed(let message): if case .failed = websiteSyncManager.syncStatus {} else { lines.append(message) }
        case .notConfigured: lines.append("Add a GitHub token below to publish your show to the website.")
        default: break
        }
        if let time = websiteSyncManager.lastSyncTime, let file = websiteSyncManager.lastSyncFilename {
            lines.append("Last published \(file) \(time.formatted(.relative(presentation: .named))).")
        } else if websiteSyncManager.hasToken {
            lines.append("Nothing published from this Mac yet.")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Show Files on the Website").font(.headline)
                Spacer()
                if websiteSyncManager.isLoadingLibrary { ProgressView().controlSize(.small) }
                Button {
                    Task { await websiteSyncManager.refreshLibrary() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload the list from GitHub")
                .accessibilityLabel(Text("Reload show list"))
                .disabled(!websiteSyncManager.hasToken)
            }
            Text("Every show you publish is kept here, so viewers can switch to earlier shows. The current show is the one the website opens by default.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = websiteSyncManager.libraryError {
                Text(error).font(.callout).foregroundColor(.orange)
            }

            if websiteSyncManager.library.shows.isEmpty {
                Text(websiteSyncManager.hasToken
                     ? "No shows in the library yet. Publish a show to start it."
                     : "Connect to GitHub to see published shows.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4])))
            } else {
                VStack(spacing: 0) {
                    ForEach(websiteSyncManager.library.shows) { entry in
                        libraryRow(entry)
                        if entry.id != websiteSyncManager.library.shows.last?.id { Divider() }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            }
        }
    }

    private func libraryRow(_ entry: ShowLibraryEntry) -> some View {
        let isCurrent = entry.slug == websiteSyncManager.library.current
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if renamingSlug == entry.slug {
                        TextField("Show name", text: $renameDraft, onCommit: { commitRename(entry) })
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                    } else {
                        Text(entry.name).font(.body.weight(.semibold))
                    }
                    if isCurrent {
                        Text("CURRENT")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                            .foregroundColor(.green)
                    }
                }
                Text("\(entry.filename) · \(entry.stackCount) stacks · \(entry.cueCount) cues · \(publishedText(entry))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            if renamingSlug == entry.slug {
                Button("Save") { commitRename(entry) }
                Button("Cancel") { renamingSlug = nil }
            } else {
                Button {
                    NSWorkspace.shared.open(siteURL(for: entry))
                } label: { Image(systemName: "safari") }
                    .buttonStyle(.borderless)
                    .help("Open this show on the website")
                    .accessibilityLabel(Text("Open \(entry.name) on the website"))
                Button {
                    renameDraft = entry.name
                    renamingSlug = entry.slug
                } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .help("Rename on the website")
                    .accessibilityLabel(Text("Rename \(entry.name)"))
                Button {
                    pendingRemoval = entry
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(isCurrent)
                    .help(isCurrent ? "Publish a different show before removing the current one" : "Remove from the website")
                    .accessibilityLabel(Text("Remove \(entry.name) from the website"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .disabled(websiteSyncManager.isSyncing)
    }

    private func publishedText(_ entry: ShowLibraryEntry) -> String {
        guard let date = entry.lastPublishedDate else { return entry.lastPublished }
        return "published " + date.formatted(date: .abbreviated, time: .shortened)
    }

    private func siteURL(for entry: ShowLibraryEntry) -> URL {
        var components = URLComponents(url: WebsiteSyncSettingsKeys.siteURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "show", value: entry.slug)]
        return components.url ?? WebsiteSyncSettingsKeys.siteURL
    }

    private func commitRename(_ entry: ShowLibraryEntry) {
        let name = renameDraft
        renamingSlug = nil
        guard name.trimmingCharacters(in: .whitespaces) != entry.name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            do { try await websiteSyncManager.renameShow(slug: entry.slug, to: name) }
            catch { actionError = error.localizedDescription }
        }
    }

    private func remove(_ entry: ShowLibraryEntry) {
        Task {
            do { try await websiteSyncManager.removeShow(slug: entry.slug) }
            catch { actionError = error.localizedDescription }
        }
    }

    // MARK: - Connection settings

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub Connection").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Token").font(.subheadline.weight(.medium))
                if isEditingToken || !websiteSyncManager.hasToken {
                    HStack {
                        SecureField("Paste a GitHub token (starts with ghp_ or github_pat_)", text: $tokenDraft)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") { saveToken() }
                            .disabled(tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        if websiteSyncManager.hasToken {
                            Button("Cancel") { isEditingToken = false; tokenDraft = "" }
                        }
                    }
                } else {
                    HStack {
                        Label("Token saved in your Keychain", systemImage: "lock.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Replace…") { isEditingToken = true }
                        Button("Remove", role: .destructive) {
                            try? websiteSyncManager.setToken(nil)
                        }
                    }
                }
                if let tokenError {
                    Text(tokenError).font(.caption).foregroundColor(.red)
                }
                if websiteSyncManager.hasLegacyPlainTextToken {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.shield").foregroundColor(.orange).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("A plain-text copy of the token is still in this app's preferences file. Older copies of Cue to Cue on this Mac use it to publish; removing it makes them stop publishing.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Remove Plain-Text Copy") { websiteSyncManager.removeLegacyPlainTextToken() }
                                .controlSize(.small)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                }
                Text("Create a classic token with the \u{201C}repo\u{201D} scope, or a fine-grained token with Contents: Read and write on the website repository.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Create a token on GitHub", destination: URL(string: "https://github.com/settings/tokens")!)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Repository").font(.subheadline.weight(.medium))
                HStack {
                    TextField("Owner", text: $ownerDraft).textFieldStyle(.roundedBorder)
                    Text("/").foregroundColor(.secondary)
                    TextField("Repository", text: $repoDraft).textFieldStyle(.roundedBorder)
                    Button("Apply") {
                        websiteSyncManager.repository = GitHubRepository(owner: ownerDraft, name: repoDraft)
                        Task { await websiteSyncManager.checkConnection() }
                    }
                    .disabled(ownerDraft == websiteSyncManager.repository.owner && repoDraft == websiteSyncManager.repository.name)
                }
                Text("Files go in the repository's cuetocue folder: the current show, its details, and the shows library.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Toggle("Publish automatically when I open a show", isOn: Binding(
                get: { websiteSyncManager.isAutoSyncEnabled },
                set: { websiteSyncManager.isAutoSyncEnabled = $0 }))
            Text("Opening a show file replaces the website's current show. Leave this off to publish only when you choose to.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveToken() {
        do {
            try websiteSyncManager.setToken(tokenDraft)
            tokenDraft = ""
            tokenError = nil
            isEditingToken = false
            Task { await websiteSyncManager.checkConnection() }
        } catch {
            tokenError = error.localizedDescription
        }
    }
}
