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
    @State private var passwordDraft = ""
    @State private var passwordConfirm = ""
    @State private var isEditingPassword = false
    @State private var passwordError: String?
    @State private var isSavingPassword = false

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(systemImage: "icloud.and.arrow.up",
                        title: "Website",
                        subtitle: "Publish your shows to nebulacreative.org/cuetocue so anyone can follow along from anywhere.",
                        tint: .blue)
            Form {
                currentShowSection
                viewerPasswordSection
                librarySection
                if websiteSyncManager.hasToken { publishingSection }
                accountSection
                if websiteSyncManager.hasLegacyPlainTextToken { legacyTokenSection }
            }
            .formStyle(.grouped)
            if let onClose {
                PanelFooter(leading: {
                    Button {
                        NSWorkspace.shared.open(WebsiteSyncSettingsKeys.siteURL)
                    } label: {
                        Label("Open Website", systemImage: "safari")
                    }
                }, done: onClose)
            }
        }
        .frame(minWidth: 600, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
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

    // MARK: - Current show

    private var currentShowSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                statusIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle).fontWeight(.semibold)
                    Text(statusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let url = websiteSyncManager.lastCommitURL, case .success = websiteSyncManager.syncStatus {
                        Link("View the change on GitHub", destination: url).font(.callout)
                    }
                }
                Spacer(minLength: 8)
                if websiteSyncManager.isSyncing {
                    ProgressView().controlSize(.small)
                }
                if let publishCurrentShow {
                    Button {
                        publishCurrentShow()
                    } label: {
                        Label("Publish", systemImage: "icloud.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(websiteSyncManager.isSyncing || !websiteSyncManager.hasToken || !websiteSyncManager.hasViewerPassword)
                    .help(publishButtonTitle + " (\u{21E7}\u{2318}U)")
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Current Show")
        } footer: {
            Text(!websiteSyncManager.hasViewerPassword
                 ? "Set a viewer password below before publishing."
                 : websiteSyncManager.hasToken
                 ? "Publishing makes this show the one the website opens by default. File \u{25B8} Publish to Website (\u{21E7}\u{2318}U) does the same."
                 : "Add a GitHub token under GitHub Account to start publishing.")
        }
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
                case .connected: return currentShowEntry != nil ? ("checkmark.circle.fill", .green) : ("doc.badge.arrow.up", .secondary)
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

    /// The library entry for the open show, matched by file name.
    private var currentShowEntry: ShowLibraryEntry? {
        guard let name = currentShowName, !name.isEmpty else { return nil }
        return websiteSyncManager.library.shows.first { $0.filename == name }
    }

    private var statusTitle: String {
        switch websiteSyncManager.syncStatus {
        case .syncing: return "Publishing…"
        case .failed: return "Publishing failed"
        case .success: return "Published"
        case .idle:
            switch websiteSyncManager.connection {
            case .connected:
                if let name = currentShowName, !name.isEmpty {
                    return (name as NSString).deletingPathExtension
                }
                return "Connected"
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
        case .connected:
            // Account details live in the GitHub Account section; here, say
            // whether this show is on the website.
            if let entry = currentShowEntry {
                let isCurrent = entry.slug == websiteSyncManager.library.current
                lines.append((isCurrent ? "On the website as the current show · " : "In the website library · ") + publishedText(entry))
            } else if currentShowName != nil, case .idle = websiteSyncManager.syncStatus {
                lines.append("Not on the website yet.")
            }
        case .failed(let message): if case .failed = websiteSyncManager.syncStatus {} else { lines.append(message) }
        case .notConfigured: lines.append("Add a GitHub token below to publish your show to the website.")
        default: break
        }
        if case .success = websiteSyncManager.syncStatus,
           let time = websiteSyncManager.lastSyncTime, let file = websiteSyncManager.lastSyncFilename {
            lines.append("Published \(file) \(time.formatted(.relative(presentation: .named))).")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Library

    private var librarySection: some View {
        Section {
            if let error = websiteSyncManager.libraryError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if websiteSyncManager.library.shows.isEmpty {
                Text(websiteSyncManager.hasToken
                     ? "No shows yet. Publish a show to start the library."
                     : "Connect to GitHub to see published shows.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(websiteSyncManager.library.shows) { entry in
                    libraryRow(entry)
                }
            }
        } header: {
            HStack {
                Text("Show Library")
                if !websiteSyncManager.library.shows.isEmpty {
                    Text("\(websiteSyncManager.library.shows.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if websiteSyncManager.isLoadingLibrary { ProgressView().controlSize(.mini) }
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
        } footer: {
            Text("Every show you publish stays here so viewers can switch to earlier shows from the website.")
        }
    }

    private func libraryRow(_ entry: ShowLibraryEntry) -> some View {
        let isCurrent = entry.slug == websiteSyncManager.library.current
        return HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundStyle(isCurrent ? Color.green : Color.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if renamingSlug == entry.slug {
                        TextField("Show name", text: $renameDraft, onCommit: { commitRename(entry) })
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                    } else {
                        Text(entry.name).fontWeight(.medium)
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
                Text("\(entry.stackCount) stacks · \(entry.cueCount) cues · \(publishedText(entry))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if renamingSlug == entry.slug {
                Button("Save") { commitRename(entry) }
                Button("Cancel") { renamingSlug = nil }
            } else {
                Menu {
                    Button("Open on Website") { NSWorkspace.shared.open(siteURL(for: entry)) }
                    Button("Rename\u{2026}") {
                        renameDraft = entry.name
                        renamingSlug = entry.slug
                    }
                    Divider()
                    Button("Remove from Website\u{2026}", role: .destructive) { pendingRemoval = entry }
                        .disabled(isCurrent)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(isCurrent ? "Publish a different show before removing this one" : "Actions for \(entry.name)")
                .accessibilityLabel(Text("Actions for \(entry.name)"))
            }
        }
        .padding(.vertical, 2)
        .disabled(websiteSyncManager.isSyncing)
        .help(entry.filename)
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

    // MARK: - Viewer password

    private var viewerPasswordSection: some View {
        Section {
            if isEditingPassword || !websiteSyncManager.hasViewerPassword {
                LabeledContent("New Password") {
                    SecureField("", text: $passwordDraft, prompt: Text("At least 8 characters"))
                        .frame(minWidth: 220)
                }
                LabeledContent("Confirm") {
                    SecureField("", text: $passwordConfirm, prompt: Text("Type it again"))
                        .frame(minWidth: 220)
                        .onSubmit(savePassword)
                }
                HStack {
                    if let passwordError {
                        Text(passwordError).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if isSavingPassword { ProgressView().controlSize(.small) }
                    if websiteSyncManager.hasViewerPassword {
                        Button("Cancel") { resetPasswordDrafts() }
                    }
                    Button(websiteSyncManager.hasViewerPassword ? "Change Password" : "Save Password", action: savePassword)
                        .buttonStyle(.borderedProminent)
                        .disabled(!passwordIsValid || isSavingPassword)
                }
            } else {
                LabeledContent("Password") {
                    HStack(spacing: 8) {
                        Label("Saved in Keychain", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                        Button("Change\u{2026}") { isEditingPassword = true }
                            .controlSize(.small)
                    }
                }
            }
        } header: {
            Text("Viewer Password")
        } footer: {
            Text(websiteSyncManager.hasViewerPassword && !isEditingPassword
                 ? "Your crew types this to open the website. Show files are encrypted with it before they're uploaded."
                 : websiteSyncManager.hasViewerPassword
                 ? "Changing it re-encrypts every show on the website. Anyone using the old password is asked for the new one."
                 : "Your crew types this to open the website. Show files are encrypted with it before they're uploaded, so without it the files on GitHub can't be read. If the website already has a password (set from another Mac), enter that one.")
        }
    }

    private var passwordIsValid: Bool {
        let trimmed = passwordDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 8 && trimmed == passwordConfirm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func savePassword() {
        guard passwordIsValid else {
            if !passwordConfirm.isEmpty && passwordDraft != passwordConfirm { passwordError = "The two passwords don't match." }
            return
        }
        isSavingPassword = true
        passwordError = nil
        let password = passwordDraft
        Task {
            do {
                try await websiteSyncManager.setViewerPassword(password)
                resetPasswordDrafts()
            } catch {
                passwordError = error.localizedDescription
            }
            isSavingPassword = false
        }
    }

    private func resetPasswordDrafts() {
        passwordDraft = ""
        passwordConfirm = ""
        isEditingPassword = false
    }

    // MARK: - Publishing options

    private var publishingSection: some View {
        Section {
            Toggle("Keep the website up to date as I edit", isOn: Binding(
                get: { websiteSyncManager.isPublishOnChangeEnabled },
                set: { websiteSyncManager.isPublishOnChangeEnabled = $0 }))
            Toggle("Publish automatically when I open a show", isOn: Binding(
                get: { websiteSyncManager.isAutoSyncEnabled },
                set: { websiteSyncManager.isAutoSyncEnabled = $0 }))
        } header: {
            Text("Publishing")
        } footer: {
            Text("With \u{201C}Keep up to date\u{201D} on, edits publish about 8 seconds after you stop typing, without interrupting you; viewers pick them up within a minute or so. The Publish button shows an orange dot when the website is behind, and a red one if a publish failed. Opening a show with the second option on replaces the website\u{2019}s current show.")
        }
    }

    // MARK: - GitHub account

    private var accountSection: some View {
        Section {
            LabeledContent("Status") {
                HStack(spacing: 8) {
                    Circle().fill(connectionColor).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(connectionText)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if websiteSyncManager.hasToken {
                        Button("Check Again") {
                            Task { await websiteSyncManager.checkConnection() }
                        }
                        .controlSize(.small)
                        .disabled(websiteSyncManager.isSyncing)
                    }
                }
            }

            if isEditingToken || !websiteSyncManager.hasToken {
                LabeledContent("Token") {
                    HStack {
                        SecureField("", text: $tokenDraft, prompt: Text("ghp_\u{2026} or github_pat_\u{2026}"))
                            .frame(minWidth: 220)
                        Button("Save") { saveToken() }
                            .disabled(tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        if websiteSyncManager.hasToken {
                            Button("Cancel") { isEditingToken = false; tokenDraft = "" }
                        }
                    }
                }
                if let tokenError {
                    Text(tokenError).font(.caption).foregroundStyle(.red)
                }
            } else {
                LabeledContent("Token") {
                    HStack(spacing: 8) {
                        Label("Saved in Keychain", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                        Button("Replace\u{2026}") { isEditingToken = true }
                            .controlSize(.small)
                        Button("Remove", role: .destructive) { try? websiteSyncManager.setToken(nil) }
                            .controlSize(.small)
                    }
                }
            }

            DisclosureGroup {
                HStack {
                    TextField("Owner", text: $ownerDraft)
                    Text("/").foregroundStyle(.secondary)
                    TextField("Repository", text: $repoDraft)
                    Button("Apply") {
                        websiteSyncManager.repository = GitHubRepository(owner: ownerDraft, name: repoDraft)
                        Task { await websiteSyncManager.checkConnection() }
                    }
                    .disabled(ownerDraft == websiteSyncManager.repository.owner && repoDraft == websiteSyncManager.repository.name)
                }
                .textFieldStyle(.roundedBorder)
                Text("Files go in the repository's cuetocue folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } label: {
                LabeledContent("Repository", value: "\(websiteSyncManager.repository)")
            }
        } header: {
            Text("GitHub Account")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Use a classic token with the \u{201C}repo\u{201D} scope, or a fine-grained token with Contents: Read and write on the website repository.")
                Link("Create a token on GitHub", destination: URL(string: "https://github.com/settings/tokens")!)
            }
        }
    }

    private var connectionText: String {
        switch websiteSyncManager.connection {
        case .connected(let login): return "Connected as \(login)"
        case .checking: return "Checking\u{2026}"
        case .notConfigured: return "Not set up"
        case .failed(let message): return message
        case .unknown: return websiteSyncManager.hasToken ? "Not checked yet" : "Not set up"
        }
    }

    private var connectionColor: Color {
        switch websiteSyncManager.connection {
        case .connected: return .green
        case .failed: return .orange
        default: return .secondary
        }
    }

    // MARK: - Legacy token

    private var legacyTokenSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("A plain-text copy of your token is still stored")
                        .fontWeight(.medium)
                    Text("Older copies of Cue to Cue on this Mac read it to publish. Removing it keeps the token only in your Keychain, and those older copies stop publishing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Remove Copy") { websiteSyncManager.removeLegacyPlainTextToken() }
            }
            .padding(.vertical, 4)
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
