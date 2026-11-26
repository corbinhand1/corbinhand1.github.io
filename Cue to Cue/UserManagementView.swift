//
//  UserManagementView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 1/27/25.
//

import SwiftUI

struct UserManagementView: View {
    @ObservedObject var authManager: AuthenticationManager
    @Binding var isPresented: Bool
    var cueStacks: [CueStack]

    @State private var showingAddUser = false
    @State private var passwordChangeUser: User?
    @State private var permissionsUser: User?
    @State private var userToDelete: User?
    @State private var alert: PanelAlert?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(systemImage: "person.2.fill",
                        title: "Users & Permissions",
                        subtitle: "Viewing the show never needs an account. Accounts let specific people edit chosen columns from the web viewer.",
                        tint: .indigo)
            Form {
                defaultPasswordSection
                accountsSection
            }
            .formStyle(.grouped)
            PanelFooter(leading: {
                Button {
                    showingAddUser = true
                } label: {
                    Label("Add Account…", systemImage: "plus")
                }
            }, done: { isPresented = false })
        }
        .frame(width: 600, height: 560)
        .sheet(isPresented: $showingAddUser) {
            AddAccountSheet(authManager: authManager) { result in
                showingAddUser = false
                if case .created(let user) = result {
                    alert = PanelAlert(title: "Account Created",
                                       message: "\(user.username) can now sign in from the web viewer." +
                                       (user.isAdmin ? "" : " Use Edit Permissions to choose which columns they can change."))
                }
            }
        }
        .sheet(item: $passwordChangeUser) { user in
            ChangePasswordSheet(user: user, authManager: authManager) { changed in
                passwordChangeUser = nil
                if changed {
                    alert = PanelAlert(title: "Password Changed",
                                       message: "\(user.username) has been signed out on every device and must use the new password.")
                }
            }
        }
        .sheet(item: $permissionsUser) { user in
            VStack(spacing: 0) {
                PermissionEditorView(user: user, cueStacks: cueStacks, authManager: authManager)
                    .frame(minHeight: 420)
                PanelFooter { permissionsUser = nil }
            }
            .frame(width: 620, height: 560)
        }
        .confirmationDialog(
            "Delete \u{201C}\(userToDelete?.username ?? "")\u{201D}?",
            isPresented: Binding(get: { userToDelete != nil }, set: { if !$0 { userToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                if let user = userToDelete { delete(user) }
                userToDelete = nil
            }
            Button("Cancel", role: .cancel) { userToDelete = nil }
        } message: {
            Text("They'll be signed out everywhere and lose any edit permissions. This can't be undone.")
        }
        .alert(alert?.title ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("OK") { alert = nil }
        } message: {
            Text(alert?.message ?? "")
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var defaultPasswordSection: some View {
        let flagged = authManager.users.filter { authManager.accountsUsingDefaultPassword.contains($0.id) }
        if let first = flagged.first {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(flagged.map(\.username).joined(separator: ", ")) \(flagged.count == 1 ? "uses" : "use") a default password")
                            .fontWeight(.semibold)
                        Text("Anyone on this network could sign in with it and edit your show. Choose a new password.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Change Password…") { passwordChangeUser = first }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var accountsSection: some View {
        Section {
            if authManager.users.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No accounts yet")
                        .fontWeight(.medium)
                    Text("Add one when someone needs to edit cues from a browser, for example a video operator updating the Video column.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(authManager.users.sorted(by: Self.accountOrder)) { user in
                    AccountRow(user: user,
                               access: accessSummary(for: user),
                               usesDefaultPassword: authManager.accountsUsingDefaultPassword.contains(user.id),
                               onChangePassword: { passwordChangeUser = user },
                               onEditPermissions: user.isAdmin ? nil : { permissionsUser = user },
                               onDelete: { userToDelete = user })
                }
            }
        } header: {
            Text("Accounts")
        } footer: {
            Text("Administrators can edit everything. Everyone else can edit only the columns you allow.")
        }
    }

    // MARK: Helpers

    private static func accountOrder(_ a: User, _ b: User) -> Bool {
        if a.isAdmin != b.isAdmin { return a.isAdmin }
        return a.username.localizedCaseInsensitiveCompare(b.username) == .orderedAscending
    }

    /// "Administrator", "Can edit Video and LX in 2 stacks", or "View only".
    private func accessSummary(for user: User) -> String {
        if user.isAdmin { return "Administrator · can edit everything" }
        let granted = authManager.permissions.filter { $0.userId == user.id && !$0.allowedColumns.isEmpty }
        guard !granted.isEmpty else { return "View only · no editable columns yet" }
        let columns = Array(Set(granted.flatMap(\.allowedColumns))).sorted()
        let columnText = columns.count <= 3
            ? ListFormatter.localizedString(byJoining: columns)
            : "\(columns.count) columns"
        let stackText = granted.count == 1 ? "1 stack" : "\(granted.count) stacks"
        return "Can edit \(columnText) in \(stackText)"
    }

    private func delete(_ user: User) {
        if case .failure(let error) = authManager.deleteUser(user.id) {
            alert = PanelAlert(title: "Couldn't Delete Account", message: error.localizedDescription)
        }
    }
}

struct PanelAlert {
    let title: String
    let message: String
}

// MARK: - Account row

private struct AccountRow: View {
    let user: User
    let access: String
    let usesDefaultPassword: Bool
    let onChangePassword: () -> Void
    let onEditPermissions: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(String(user.username.prefix(1)).uppercased())
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background((user.isAdmin ? Color.indigo : Color.gray).gradient, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.username).fontWeight(.medium)
                    if usesDefaultPassword {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(.orange)
                            .help("Uses a default password")
                    }
                }
                Text(access)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Group {
                    if let last = user.lastLoginAt {
                        Text("Last signed in ") + Text(last, format: .relative(presentation: .numeric))
                    } else {
                        Text("Never signed in")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            if let onEditPermissions {
                Button("Permissions…", action: onEditPermissions)
                    .controlSize(.small)
            }
            Menu {
                Button("Change Password…", action: onChangePassword)
                if let onEditPermissions {
                    Button("Edit Permissions…", action: onEditPermissions)
                }
                Divider()
                Button("Delete Account…", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Actions for \(user.username)")
            .accessibilityLabel(Text("Actions for \(user.username)"))
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Add account

private struct AddAccountSheet: View {
    enum Result { case created(User), cancelled }

    let authManager: AuthenticationManager
    let onFinish: (Result) -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var isAdmin = false
    @State private var errorMessage: String?

    private var canCreate: Bool {
        username.trimmingCharacters(in: .whitespaces).count >= 3 && !password.isEmpty && password == confirm
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(systemImage: "person.badge.plus", title: "New Account",
                        subtitle: "For someone who needs to edit cues from a browser.", tint: .indigo)
            Form {
                Section {
                    TextField("Name", text: $username, prompt: Text("e.g. video-op"))
                    SecureField("Password", text: $password, prompt: Text("At least \(AuthenticationManager.minimumPasswordLength) characters"))
                    SecureField("Confirm password", text: $confirm)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else if !confirm.isEmpty && password != confirm {
                        Text("Passwords don't match.").foregroundStyle(.red)
                    }
                }
                Section {
                    Toggle("Administrator", isOn: $isAdmin)
                } footer: {
                    Text(isAdmin
                         ? "Can edit every column and manage accounts from the web viewer."
                         : "Can edit only the columns you choose with Edit Permissions.")
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { onFinish(.cancelled) }
                    .keyboardShortcut(.cancelAction)
                Button("Create Account", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 440)
    }

    private func create() {
        switch authManager.createUser(username: username.trimmingCharacters(in: .whitespaces), password: password, isAdmin: isAdmin) {
        case .success(let user): onFinish(.created(user))
        case .failure(let error): errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Change password

private struct ChangePasswordSheet: View {
    let user: User
    let authManager: AuthenticationManager
    let onFinish: (Bool) -> Void

    @State private var password = ""
    @State private var confirm = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(systemImage: "key.fill", title: "Change Password",
                        subtitle: "For \u{201C}\(user.username)\u{201D}. They'll be signed out on every device.", tint: .indigo)
            Form {
                Section {
                    SecureField("New password", text: $password, prompt: Text("At least \(AuthenticationManager.minimumPasswordLength) characters"))
                    SecureField("Confirm new password", text: $confirm)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else if !confirm.isEmpty && password != confirm {
                        Text("Passwords don't match.").foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { onFinish(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Change Password", action: change)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || password != confirm)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 440)
    }

    private func change() {
        switch authManager.changePassword(userId: user.id, newPassword: password) {
        case .success: onFinish(true)
        case .failure(let error): errorMessage = error.localizedDescription
        }
    }
}

struct PermissionEditorView: View {
    let user: User
    let cueStacks: [CueStack]
    let authManager: AuthenticationManager
    
    @State private var userPermissions: [PermissionRequest] = []
    @State private var showingSaveConfirmation = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions for \(user.username)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Select which columns this user can edit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Save Changes") {
                    savePermissions()
                }
                .buttonStyle(.borderedProminent)
                .disabled(userPermissions.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            
            // Cue Stacks List
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(cueStacks, id: \.id) { cueStack in
                        cueStackPermissionCard(for: cueStack)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            loadUserPermissions()
        }
        .alert("Permissions Saved", isPresented: $showingSaveConfirmation) {
            Button("OK") { }
        } message: {
            Text("Permissions have been updated successfully.")
        }
    }
    
    // MARK: - Cue Stack Permission Card
    
    private func cueStackPermissionCard(for cueStack: CueStack) -> some View {
        VStack(spacing: 16) {
            // Cue Stack Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cueStack.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("\(cueStack.columns.count) columns")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Select All/None buttons
                HStack(spacing: 8) {
                    Button("Select All") {
                        selectAllColumns(for: cueStack.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Clear All") {
                        clearAllColumns(for: cueStack.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            // Columns Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(4, cueStack.columns.count)), spacing: 8) {
                ForEach(0..<cueStack.columns.count, id: \.self) { columnIndex in
                    let column = cueStack.columns[columnIndex]
                    let isSelected = userPermissions.first(where: { $0.cueStackId == cueStack.id })?.allowedColumns.contains(column.name) ?? false
                    
                    Button(action: {
                        togglePermission(cueStackId: cueStack.id, columnName: column.name)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundColor(isSelected ? .white : .secondary)
                            
                            Text(column.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .foregroundColor(isSelected ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Helper Methods
    
    private func selectAllColumns(for cueStackId: UUID) {
        if let cueStack = cueStacks.first(where: { $0.id == cueStackId }) {
            let allColumnNames = cueStack.columns.map { $0.name }
            
            if let index = userPermissions.firstIndex(where: { $0.cueStackId == cueStackId }) {
                userPermissions[index] = PermissionRequest(
                    cueStackId: cueStackId,
                    allowedColumns: allColumnNames,
                    allowedColumnIndices: nil
                )
            } else {
                userPermissions.append(PermissionRequest(
                    cueStackId: cueStackId,
                    allowedColumns: allColumnNames,
                    allowedColumnIndices: nil
                ))
            }
        }
    }
    
    private func clearAllColumns(for cueStackId: UUID) {
        if let index = userPermissions.firstIndex(where: { $0.cueStackId == cueStackId }) {
            userPermissions[index] = PermissionRequest(
                cueStackId: cueStackId,
                allowedColumns: [],
                allowedColumnIndices: nil
            )
        }
    }
    
    private func loadUserPermissions() {
        // Load existing permissions for this user
        let existingPermissions = authManager.permissions.filter { $0.userId == user.id }
        userPermissions = existingPermissions.map { permission in
            PermissionRequest(
                cueStackId: permission.cueStackId, 
                allowedColumns: permission.allowedColumns,
                allowedColumnIndices: permission.allowedColumnIndices
            )
        }
        
        // Add empty permissions for cue stacks that don't have permissions yet
        for cueStack in cueStacks {
            if !userPermissions.contains(where: { $0.cueStackId == cueStack.id }) {
                userPermissions.append(PermissionRequest(
                    cueStackId: cueStack.id, 
                    allowedColumns: [],
                    allowedColumnIndices: nil
                ))
            }
        }
    }
    
    private func togglePermission(cueStackId: UUID, columnName: String) {
        if let index = userPermissions.firstIndex(where: { $0.cueStackId == cueStackId }) {
            var allowedColumns = userPermissions[index].allowedColumns
            
            if allowedColumns.contains(columnName) {
                allowedColumns.removeAll { $0 == columnName }
            } else {
                allowedColumns.append(columnName)
            }
            
            userPermissions[index] = PermissionRequest(
                cueStackId: cueStackId, 
                allowedColumns: allowedColumns,
                allowedColumnIndices: nil
            )
        }
    }
    
    private func savePermissions() {
        let result = authManager.updateUserPermissions(user.id, permissions: userPermissions)
        switch result {
        case .success:
            showingSaveConfirmation = true
        case .failure(let error):
            print("Error updating permissions: \(error)")
        }
    }
}

#Preview {
    UserManagementView(
        authManager: AuthenticationManager(dataSyncManager: DataSyncManager()),
        isPresented: .constant(true),
        cueStacks: [
            CueStack(
                name: "Test Stack",
                cues: [],
                columns: [
                    Column(name: "Column 1", width: 100),
                    Column(name: "Column 2", width: 100),
                    Column(name: "Column 3", width: 100)
                ]
            )
        ]
    )
}
