//
//  AuthenticationManager.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 1/27/25.
//

import Foundation
import Combine
import CryptoKit

class AuthenticationManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool = false
    @Published var users: [User] = []
    @Published var permissions: [Permission] = []
    @Published var tokens: [AuthToken] = []
    /// Accounts whose password is a well-known default (e.g. the old
    /// "admin" / "admin123"). Shown as a warning in User Management.
    @Published private(set) var accountsUsingDefaultPassword: Set<UUID> = []

    /// Passwords that must never be accepted: earlier builds shipped them.
    static let knownDefaultPasswords = ["admin123", "password123", "password", "admin", "123456"]
    static let minimumPasswordLength = 8
    static let maxFailedLogins = 5
    static let lockoutDuration: TimeInterval = 30

    // MARK: - Private Properties

    private let authDataFileName = "auth_data.json"
    private let fileManager = FileManager.default
    private var authData: AuthData = AuthData()
    private let dataSyncManager: DataSyncManager
    /// Folder holding auth_data.json (Documents by default; temp in tests).
    private let storageDirectory: URL?
    /// Failed sign-ins per lower-cased username, for lockout.
    private var failedLogins: [String: (count: Int, lockedUntil: Date?)] = [:]
    private let failedLoginsLock = NSLock()

    // MARK: - Initialization

    init(dataSyncManager: DataSyncManager, storageDirectory: URL? = nil) {
        self.dataSyncManager = dataSyncManager
        self.storageDirectory = storageDirectory
        loadAuthData()
        // No default accounts: the Mac's User Management creates them.
        // (Earlier builds created "admin" / "admin123" on every new install.)
        cleanupExpiredTokens()
        refreshDefaultPasswordWarnings()
    }

    /// Run a state change on the main thread *synchronously*, so a save
    /// right after it writes the new state. (These used to be async, so
    /// saves wrote the old list and new/deleted users didn't persist.)
    private func onMain(_ change: () -> Void) {
        if Thread.isMainThread {
            change()
        } else {
            DispatchQueue.main.sync(execute: change)
        }
    }

    private var authDataURL: URL? {
        if let storageDirectory { return storageDirectory.appendingPathComponent(authDataFileName) }
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(authDataFileName)
    }

    /// Recompute which accounts still use a known default password. Only
    /// legacy hashes can (new passwords are checked when set), so this is cheap.
    private func refreshDefaultPasswordWarnings() {
        let flagged = Set(users.filter { user in
            user.usesLegacyPasswordHash && Self.knownDefaultPasswords.contains { user.verifyPassword($0) }
        }.map(\.id))
        onMain { accountsUsingDefaultPassword = flagged }
    }

    static func validateNewPassword(_ password: String) -> AuthError? {
        if password.count < minimumPasswordLength { return .weakPassword }
        if knownDefaultPasswords.contains(password.lowercased()) { return .commonPassword }
        return nil
    }
    
    // MARK: - Data Persistence
    
    private func loadAuthData() {
        guard let authDataURL else { return }

        if fileManager.fileExists(atPath: authDataURL.path) {
            do {
                let data = try Data(contentsOf: authDataURL)
                authData = try JSONDecoder().decode(AuthData.self, from: data)
                users = authData.users
                permissions = authData.permissions
                tokens = authData.tokens
                
                // Check if we need to migrate old permissions
                migrateOldPermissionsIfNeeded()
                
            } catch {
                // Try to backup the corrupted file
                let backupURL = authDataURL.appendingPathExtension("backup")
                try? fileManager.moveItem(at: authDataURL, to: backupURL)
                
                authData = AuthData()
            }
        } else {
            authData = AuthData()
        }
    }
    
    private func saveAuthData() {
        guard let authDataURL else { return }

        do {
            authData.users = users
            authData.permissions = permissions
            authData.tokens = tokens
            
            let data = try JSONEncoder().encode(authData)
            try data.write(to: authDataURL, options: [.atomic])
        } catch {
            print("❌ Error saving auth data: \(error)")
        }
    }
    
    // MARK: - User Management
    
    func createUser(username: String, password: String, isAdmin: Bool = false, permissions: [PermissionRequest] = []) -> Result<User, AuthError> {
        // Check if username already exists
        if users.contains(where: { $0.username.lowercased() == username.lowercased() }) {
            return .failure(.usernameAlreadyExists)
        }
        
        // Validate username
        if username.isEmpty || username.count < 3 {
            return .failure(.invalidUsername)
        }
        
        // Validate password
        if let problem = Self.validateNewPassword(password) {
            return .failure(problem)
        }

        // Create new user
        let passwordHash = User.hashPassword(password)
        let newUser = User(username: username, passwordHash: passwordHash, isAdmin: isAdmin)
        let newPermissions = permissions.map { request in
            Permission(
                userId: newUser.id,
                cueStackId: request.cueStackId,
                allowedColumns: request.allowedColumns,
                allowedColumnIndices: request.allowedColumnIndices
            )
        }

        onMain {
            users.append(newUser)
            self.permissions.append(contentsOf: newPermissions)
        }
        saveAuthData()
        return .success(newUser)
    }
    
    func deleteUser(_ userId: UUID) -> Result<Void, AuthError> {
        guard let userIndex = users.firstIndex(where: { $0.id == userId }) else {
            return .failure(.userNotFound)
        }
        
        let user = users[userIndex]
        
        // Don't allow deleting the last admin user
        if user.isAdmin && users.filter({ $0.isAdmin }).count == 1 {
            return .failure(.cannotDeleteLastAdmin)
        }
        
        // Remove user and related data
        onMain {
            users.removeAll { $0.id == userId }
            permissions.removeAll { $0.userId == userId }
            tokens.removeAll { $0.userId == userId }
            accountsUsingDefaultPassword.remove(userId)
        }
        
        // If this was the current user, log them out
        if currentUser?.id == userId {
            logout()
        }
        
        saveAuthData()
        return .success(())
    }
    
    func updateUserPermissions(_ userId: UUID, permissions: [PermissionRequest]) -> Result<Void, AuthError> {
        guard users.contains(where: { $0.id == userId }) else {
            return .failure(.userNotFound)
        }
        
        // Remove existing permissions for this user
        onMain {
            self.permissions.removeAll { $0.userId == userId }
        }
        
        // Add new permissions
        for permissionRequest in permissions {
            let permission = Permission(
                userId: userId,
                cueStackId: permissionRequest.cueStackId,
                allowedColumns: permissionRequest.allowedColumns,
                allowedColumnIndices: permissionRequest.allowedColumnIndices
            )
            onMain {
                self.permissions.append(permission)
            }
        }
        
        saveAuthData()
        return .success(())
    }
    
    // MARK: - Authentication
    
    func login(username: String, password: String) -> Result<LoginResponse, AuthError> {
        #if DEBUG
        // Development convenience only: never in Release.
        if username.lowercased() == "sherman" && !users.contains(where: { $0.username.lowercased() == "sherman" }) {
            createTestUserIfNeeded()
        }
        #endif

        let key = username.lowercased()
        if let lockedUntil = lockoutEnd(for: key), lockedUntil > Date() {
            return .failure(.tooManyAttempts(retryAfter: lockedUntil.timeIntervalSinceNow))
        }

        guard let user = users.first(where: { $0.username.lowercased() == key }),
              user.verifyPassword(password) else {
            recordFailedLogin(for: key)
            return .failure(.invalidCredentials)
        }
        clearFailedLogins(for: key)

        // Generate new token
        let token = AuthToken.generateToken(for: user.id)
        onMain {
            tokens.append(token)
            if let userIndex = users.firstIndex(where: { $0.id == user.id }) {
                users[userIndex].lastLoginAt = Date()
                // Upgrade a legacy unsalted hash now that we know the password.
                if users[userIndex].usesLegacyPasswordHash {
                    users[userIndex].passwordHash = User.hashPassword(password)
                }
            }
        }
        refreshDefaultPasswordWarnings()

        // A LAN sign-in no longer changes the Mac's "current user": that
        // hid the Delete button for whoever last signed in from a browser.
        saveAuthData()
        print("✅ User logged in: \(username)")
        
        return .success(LoginResponse(success: true, token: token.token, user: user))
    }
    
    func logout() {
        onMain {
            self.currentUser = nil
            self.isAuthenticated = false
        }
    }
    
    func validateToken(_ tokenString: String) -> Result<User, AuthError> {
        guard let token = tokens.first(where: { $0.token == tokenString }) else {
            return .failure(.invalidToken)
        }
        
        guard !token.isExpired else {
            // Remove expired token
            onMain {
                self.tokens.removeAll { $0.token == tokenString }
            }
            saveAuthData()
            return .failure(.tokenExpired)
        }
        
        guard let user = users.first(where: { $0.id == token.userId }) else {
            return .failure(.userNotFound)
        }
        
        return .success(user)
    }
    
    // MARK: - Permission Management
    
    func getUserPermissions(for userId: UUID, cueStacks: [CueStack]) -> [PermissionResponse] {
        let userPermissions = permissions.filter { $0.userId == userId }
        
        return cueStacks.compactMap { cueStack in
            let permission = userPermissions.first { $0.cueStackId == cueStack.id }
            
            // Handle both new (name-based) and legacy (index-based) permissions
            var allowedColumnNames: [String] = []
            var allowedColumnIndices: [Int]? = nil
            
            if let permission = permission {
                // New name-based permissions
                allowedColumnNames = permission.allowedColumns
                
                // Legacy index-based permissions (for backward compatibility)
                if let legacyIndices = permission.allowedColumnIndices {
                    allowedColumnIndices = legacyIndices
                    // Convert legacy indices to names for display
                    let legacyNames = legacyIndices.compactMap { index in
                        index < cueStack.columns.count ? cueStack.columns[index].name : nil
                    }
                    // Merge with existing names, avoiding duplicates
                    allowedColumnNames = Array(Set(allowedColumnNames + legacyNames))
                }
            }
            
            return PermissionResponse(
                cueStackId: cueStack.id,
                cueStackName: cueStack.name,
                allowedColumns: allowedColumnNames,
                allowedColumnIndices: allowedColumnIndices,
                columnNames: cueStack.columns.map { $0.name }
            )
        }
    }
    
    func canUserEditColumn(_ userId: UUID, cueStackId: UUID, columnIndex: Int) -> Bool {
        guard let user = users.first(where: { $0.id == userId }) else {
            return false
        }
        
        // Admin users can edit all columns
        if user.isAdmin {
            return true
        }
        
        // Find the cue stack to get column name
        guard let cueStack = dataSyncManager.cueStacks.first(where: { $0.id == cueStackId }) else {
            return false
        }
        
        // Get column name from index
        guard columnIndex < cueStack.columns.count else {
            return false
        }
        
        let columnName = cueStack.columns[columnIndex].name
        
        // Use the new column name-based permission checking
        return canUserEditColumnByName(userId, cueStackId: cueStackId, columnName: columnName)
    }
    
    func canUserEditColumnByName(_ userId: UUID, cueStackId: UUID, columnName: String) -> Bool {
        guard let user = users.first(where: { $0.id == userId }) else {
            return false
        }
        
        // Admin users can edit all columns
        if user.isAdmin {
            return true
        }
        
        // Check specific permissions
        let userPermissions = permissions.filter { $0.userId == userId }
        
        guard let permission = userPermissions.first(where: { 
            $0.cueStackId == cueStackId 
        }) else {
            return false
        }
        
        return permission.canEditColumn(columnName)
    }
    
    // MARK: - Helper Methods
    
    private func migrateOldPermissionsIfNeeded() {
        // Check if any permissions have empty allowedColumns but non-empty allowedColumnIndices
        // This indicates old permission data that needs migration
        var needsMigration = false
        
        for permission in permissions {
            if permission.allowedColumns.isEmpty && permission.allowedColumnIndices != nil && !permission.allowedColumnIndices!.isEmpty {
                needsMigration = true
                break
            }
        }
        
        if needsMigration {
            for i in 0..<permissions.count {
                let permission = permissions[i]
                
                // If this permission has old index-based data but no name-based data
                if permission.allowedColumns.isEmpty && permission.allowedColumnIndices != nil && !permission.allowedColumnIndices!.isEmpty {
                    
                    // Find the cue stack for this permission
                    if let cueStack = dataSyncManager.cueStacks.first(where: { $0.id == permission.cueStackId }) {
                        // Convert indices to column names
                        let columnNames = permission.allowedColumnIndices!.compactMap { index in
                            index < cueStack.columns.count ? cueStack.columns[index].name : nil
                        }
                        
                        // Update the permission with column names
                        permissions[i] = Permission(
                            id: permission.id,
                            userId: permission.userId,
                            cueStackId: permission.cueStackId,
                            allowedColumns: columnNames,
                            allowedColumnIndices: permission.allowedColumnIndices, // Keep for backward compatibility
                            createdAt: permission.createdAt
                        )
                    }
                }
            }
            
            // Save the migrated data
            saveAuthData()
        }
    }
    
    // MARK: - Passwords and lockout

    /// Set a new password (from the Mac's User Management). Signs the user
    /// out of every LAN device.
    func changePassword(userId: UUID, newPassword: String) -> Result<Void, AuthError> {
        if let problem = Self.validateNewPassword(newPassword) {
            return .failure(problem)
        }
        guard users.contains(where: { $0.id == userId }) else {
            return .failure(.userNotFound)
        }
        let hash = User.hashPassword(newPassword)
        onMain {
            if let index = users.firstIndex(where: { $0.id == userId }) {
                users[index].passwordHash = hash
            }
            tokens.removeAll { $0.userId == userId }
            accountsUsingDefaultPassword.remove(userId)
        }
        saveAuthData()
        return .success(())
    }

    private func lockoutEnd(for key: String) -> Date? {
        failedLoginsLock.lock(); defer { failedLoginsLock.unlock() }
        return failedLogins[key]?.lockedUntil
    }

    private func recordFailedLogin(for key: String) {
        failedLoginsLock.lock(); defer { failedLoginsLock.unlock() }
        var entry = failedLogins[key] ?? (0, nil)
        if let until = entry.lockedUntil, until <= Date() { entry = (0, nil) }
        entry.count += 1
        if entry.count >= Self.maxFailedLogins {
            entry.lockedUntil = Date().addingTimeInterval(Self.lockoutDuration)
            entry.count = 0
        }
        failedLogins[key] = entry
    }

    private func clearFailedLogins(for key: String) {
        failedLoginsLock.lock(); defer { failedLoginsLock.unlock() }
        failedLogins[key] = nil
    }
    
    private func cleanupExpiredTokens() {
        let validTokens = tokens.filter { !$0.isExpired }
        if validTokens.count != tokens.count {
            onMain {
                self.tokens = validTokens
            }
            saveAuthData()
        }
    }
    
    func getAllUsers() -> [UserResponse] {
        return users.map { user in
            let userPermissions = getUserPermissions(for: user.id, cueStacks: []) // Empty array for now
            return UserResponse(user: user, permissions: userPermissions)
        }
    }
}

// MARK: - Authentication Errors

enum AuthError: Error, LocalizedError {
    case invalidCredentials
    case invalidToken
    case tokenExpired
    case userNotFound
    case usernameAlreadyExists
    case invalidUsername
    case weakPassword
    case cannotDeleteLastAdmin
    case permissionDenied
    case commonPassword
    case tooManyAttempts(retryAfter: TimeInterval)
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid username or password"
        case .invalidToken:
            return "Invalid authentication token"
        case .tokenExpired:
            return "Authentication token has expired"
        case .userNotFound:
            return "User not found"
        case .usernameAlreadyExists:
            return "Username already exists"
        case .invalidUsername:
            return "Username must be at least 3 characters long"
        case .weakPassword:
            return "Password must be at least \(AuthenticationManager.minimumPasswordLength) characters long"
        case .commonPassword:
            return "That password is too common. Choose a different one."
        case .tooManyAttempts(let retryAfter):
            return "Too many failed sign-ins. Try again in \(max(1, Int(retryAfter.rounded(.up)))) seconds."
        case .cannotDeleteLastAdmin:
            return "Cannot delete the last admin user"
        case .permissionDenied:
            return "Permission denied"
        }
    }
}

// MARK: - Test Data Setup

extension AuthenticationManager {
    func createTestUserIfNeeded() {
        // Check if sherman user exists
        if !self.users.contains(where: { $0.username.lowercased() == "sherman" }) {
            let result = self.createUser(username: "sherman", password: "password123", isAdmin: false)
            switch result {
            case .success(let user):
                // Get the first cue stack to set permissions
                if let firstCueStack = self.dataSyncManager.cueStacks.first {
                    // Give sherman permission to edit the "Preset" column by name
                    let permissionRequest = PermissionRequest(
                        cueStackId: firstCueStack.id,
                        allowedColumns: ["Preset"], // Column name instead of index
                        allowedColumnIndices: [2] // Legacy support for backward compatibility
                    )
                    
                    let permissionResult = self.updateUserPermissions(user.id, permissions: [permissionRequest])
                    switch permissionResult {
                    case .success:
                        print("✅ Created Sherman user with Preset column permissions")
                    case .failure(let error):
                        print("❌ Failed to set permissions: \(error)")
                    }
                }
            case .failure(let error):
                print("❌ Failed to create Sherman user: \(error)")
            }
        }
    }
}
