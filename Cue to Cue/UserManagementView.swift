//
//  UserManagementView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 1/27/25.
//

import SwiftUI

struct UserManagementView: View {
    @ObservedObject var authManager: AuthenticationManager
    @State private var selectedTab: Tab = .login
    @State private var username = ""
    @State private var password = ""
    @State private var newUsername = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isAdmin = false
    @State private var selectedUser: User?
    @State private var showingAddUserForm = false
    @State private var showingDeleteAlert = false
    @State private var userToDelete: User?
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    @Binding var isPresented: Bool
    var cueStacks: [CueStack]
    
    enum Tab: String, CaseIterable {
        case login = "Login"
        case users = "Users"
        case permissions = "Permissions"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Clean Header
            headerView
            
            // Navigation Tabs
            navigationTabs
            
            // Main Content Area
            mainContentView
        }
        .frame(width: 900, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            autoLoginAdmin()
            authManager.createTestUserIfNeeded()
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .alert("Delete User", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let user = userToDelete {
                    deleteUser(user)
                }
            }
        } message: {
            Text("Are you sure you want to delete this user? This action cannot be undone.")
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("User Management")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(authManager.isAuthenticated ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    
                    Text(authManager.isAuthenticated ? "Connected" : "Not connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: {
                isPresented = false
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Navigation Tabs
    
    private var navigationTabs: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button(action: {
                    selectedTab = tab
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: tabIcon(for: tab))
                            .font(.system(size: 16, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(selectedTab == tab ? .white : .primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                
                if tab != Tab.allCases.last {
                    Spacer()
                        .frame(width: 8)
                }
            }
            
            Spacer()
            
            if authManager.isAuthenticated {
                Button(action: {
                    authManager.logout()
                    clearForm()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14))
                        Text("Logout")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Main Content View
    
    private var mainContentView: some View {
        Group {
            switch selectedTab {
            case .login:
                loginView
            case .users:
                usersView
            case .permissions:
                permissionsView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Login View
    
    private var loginView: some View {
        VStack(spacing: 32) {
            if authManager.isAuthenticated {
                // Success State
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.green)
                    
                    VStack(spacing: 8) {
                        Text("Admin Connected")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("You're logged in as administrator")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Manage Users") {
                        selectedTab = .users
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.top, 60)
            } else {
                // Login Form
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Text("Administrator Login")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Sign in to manage users and permissions")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.headline)
                                .foregroundColor(.primary)
                            TextField("Enter username", text: $username)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 300)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.headline)
                                .foregroundColor(.primary)
                            SecureField("Enter password", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 300)
                        }
                        
                        Button("Sign In") {
                            login()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(username.isEmpty || password.isEmpty)
                    }
                    
                    // Default credentials info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Default Credentials")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Username: admin")
                            Text("Password: admin123")
                        }
                        .font(.body)
                        .foregroundColor(.secondary)
                        
                        Text("Change these in production!")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(16)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(12)
                    .frame(maxWidth: 300)
                }
                .padding(.top, 40)
            }
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
    
    // MARK: - Users View
    
    private var usersView: some View {
        VStack(spacing: 24) {
            // Header with Add User Button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Users")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(authManager.users.count) user\(authManager.users.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if authManager.isAuthenticated && authManager.currentUser?.isAdmin == true {
                    Button(action: {
                        showingAddUserForm.toggle()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .medium))
                            Text("Add User")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            
            // Add User Form (if showing)
            if showingAddUserForm {
                addUserCard
                    .padding(.horizontal, 32)
            }
            
            // Users List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(authManager.users) { user in
                        userCard(for: user)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
    }
    
    // MARK: - Add User Card
    
    private var addUserCard: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Add New User")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    showingAddUserForm = false
                    clearForm()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("Enter username", text: $newUsername)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        SecureField("Enter password", text: $newPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        SecureField("Confirm password", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Admin")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Toggle("", isOn: $isAdmin)
                            .toggleStyle(SwitchToggleStyle())
                    }
                }
            }
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    showingAddUserForm = false
                    clearForm()
                }
                .buttonStyle(.bordered)
                
                Button("Create User") {
                    createUser()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newUsername.isEmpty || newPassword.isEmpty || newPassword != confirmPassword)
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - User Card
    
    private func userCard(for user: User) -> some View {
        HStack(spacing: 16) {
            // Avatar
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(
                    Text(String(user.username.prefix(1)).uppercased())
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                )
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(user.username)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if user.isAdmin {
                        Text("Admin")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    
                    if authManager.currentUser?.id == user.id {
                        Text("Current")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created: \(user.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let lastLogin = user.lastLoginAt {
                        Text("Last login: \(lastLogin.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Actions
            if authManager.currentUser?.id != user.id {
                Button(action: {
                    userToDelete = user
                    showingDeleteAlert = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Permissions View
    
    private var permissionsView: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Permissions")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Manage column editing permissions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            
            if authManager.isAuthenticated && authManager.currentUser?.isAdmin == true {
                VStack(spacing: 20) {
                    // User Selection Card
                    VStack(spacing: 16) {
                        HStack {
                            Text("Select User")
                                .font(.headline)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        
                        Picker("Select User", selection: $selectedUser) {
                            Text("Choose a user...").tag(nil as User?)
                            ForEach(authManager.users.filter { !$0.isAdmin }) { user in
                                Text(user.username).tag(user as User?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: 300)
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, 32)
                    
                    // Permission Editor
                    if let user = selectedUser {
                        PermissionEditorView(
                            user: user,
                            cueStacks: cueStacks,
                            authManager: authManager
                        )
                        .padding(.horizontal, 32)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("Admin Access Required")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("You need administrator privileges to manage permissions")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Helper Methods
    
    private func tabIcon(for tab: Tab) -> String {
        switch tab {
        case .login:
            return "person.circle"
        case .users:
            return "person.2"
        case .permissions:
            return "key"
        }
    }
    
    private func autoLoginAdmin() {
        // Try to log in with default admin credentials
        let result = authManager.login(username: "admin", password: "admin123")
        switch result {
        case .success(let response):
            if response.success {
                // Admin logged in successfully, switch to Users tab
                selectedTab = .users
            }
        case .failure:
            // If auto-login fails, stay on login tab
            break
        }
    }
    
    private func login() {
        let result = authManager.login(username: username, password: password)
        switch result {
        case .success(let response):
            if response.success {
                showAlert(title: "Success", message: "Logged in successfully!")
                clearForm()
                selectedTab = .users
            } else {
                showAlert(title: "Login Failed", message: response.message ?? "Unknown error")
            }
        case .failure(let error):
            showAlert(title: "Login Failed", message: error.localizedDescription)
        }
    }
    
    private func createUser() {
        guard newPassword == confirmPassword else {
            showAlert(title: "Error", message: "Passwords do not match")
            return
        }
        
        let result = authManager.createUser(
            username: newUsername,
            password: newPassword,
            isAdmin: isAdmin
        )
        
        switch result {
        case .success:
            showAlert(title: "Success", message: "User created successfully!")
            clearNewUserForm()
        case .failure(let error):
            showAlert(title: "Error", message: error.localizedDescription)
        }
    }
    
    private func deleteUser(_ user: User) {
        let result = authManager.deleteUser(user.id)
        switch result {
        case .success:
            showAlert(title: "Success", message: "User deleted successfully!")
        case .failure(let error):
            showAlert(title: "Error", message: error.localizedDescription)
        }
    }
    
    private func clearForm() {
        username = ""
        password = ""
    }
    
    private func clearNewUserForm() {
        newUsername = ""
        newPassword = ""
        confirmPassword = ""
        isAdmin = false
    }
    
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

// MARK: - User Row View

struct UserRowView: View {
    let user: User
    let isCurrentUser: Bool
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(user.username)
                    .font(.headline)
                
                HStack {
                    if user.isAdmin {
                        Text("Admin")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    if isCurrentUser {
                        Text("Current User")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Text("Created: \(user.createdAt, formatter: dateFormatter)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let lastLogin = user.lastLoginAt {
                    Text("Last login: \(lastLogin, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if !isCurrentUser {
                Button("Delete") {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Permission Editor View

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
