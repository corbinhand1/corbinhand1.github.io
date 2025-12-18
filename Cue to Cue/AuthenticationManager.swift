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
    
    // MARK: - Private Properties
    
    private let authDataFileName = "auth_data.json"
    private let fileManager = FileManager.default
    private var authData: AuthData = AuthData()
    private let dataSyncManager: DataSyncManager
    
    // MARK: - Initialization
    
    init(dataSyncManager: DataSyncManager) {
        self.dataSyncManager = dataSyncManager
        loadAuthData()
        createDefaultAdminUserIfNeeded()
        cleanupExpiredTokens()
    }
    
    // MARK: - Data Persistence
    
    private func loadAuthData() {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let authDataURL = documentsDirectory.appendingPathComponent(authDataFileName)
        
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
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let authDataURL = documentsDirectory.appendingPathComponent(authDataFileName)
        
        do {
            authData.users = users
            authData.permissions = permissions
            authData.tokens = tokens
            
            let data = try JSONEncoder().encode(authData)
            try data.write(to: authDataURL)
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
        if password.isEmpty || password.count < 6 {
            return .failure(.weakPassword)
        }
        
        // Create new user
        let passwordHash = User.hashPassword(password)
        let newUser = User(username: username, passwordHash: passwordHash, isAdmin: isAdmin)
        
        DispatchQueue.main.async {
            self.users.append(newUser)
        }
        
        // Add permissions
        for permissionRequest in permissions {
            let permission = Permission(
                userId: newUser.id,
                cueStackId: permissionRequest.cueStackId,
                allowedColumns: permissionRequest.allowedColumns,
                allowedColumnIndices: permissionRequest.allowedColumnIndices
            )
            DispatchQueue.main.async {
                self.permissions.append(permission)
            }
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
        DispatchQueue.main.async {
            self.users.remove(at: userIndex)
            self.permissions.removeAll { $0.userId == userId }
            self.tokens.removeAll { $0.userId == userId }
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
        DispatchQueue.main.async {
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
            DispatchQueue.main.async {
                self.permissions.append(permission)
            }
        }
        
        saveAuthData()
        return .success(())
    }
    
    // MARK: - Authentication
    
    func login(username: String, password: String) -> Result<LoginResponse, AuthError> {
        // If sherman user doesn't exist, try to create it now
        if username.lowercased() == "sherman" && !users.contains(where: { $0.username.lowercased() == "sherman" }) {
            createTestUserIfNeeded()
        }
        
        guard let user = users.first(where: { $0.username.lowercased() == username.lowercased() }) else {
            return .failure(.invalidCredentials)
        }
        
        guard user.verifyPassword(password) else {
            return .failure(.invalidCredentials)
        }
        
        // Generate new token
        let token = AuthToken.generateToken(for: user.id)
        // Add token
        DispatchQueue.main.async {
            self.tokens.append(token)
        }
        
        // Update last login time
        if let userIndex = users.firstIndex(where: { $0.id == user.id }) {
            users[userIndex].lastLoginAt = Date()
        }
        
        // Set current user on main thread
        DispatchQueue.main.async {
            self.currentUser = user
            self.isAuthenticated = true
        }
        
        saveAuthData()
        print("✅ User logged in: \(username)")
        
        return .success(LoginResponse(success: true, token: token.token, user: user))
    }
    
    func logout() {
        DispatchQueue.main.async {
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
            DispatchQueue.main.async {
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
    
    private func createDefaultAdminUserIfNeeded() {
        if users.isEmpty {
            let adminPassword = "admin123" // Change this in production!
            let adminUser = User(username: "admin", passwordHash: User.hashPassword(adminPassword), isAdmin: true)
            DispatchQueue.main.async {
                self.users.append(adminUser)
            }
            saveAuthData()
        }
    }
    
    private func cleanupExpiredTokens() {
        let validTokens = tokens.filter { !$0.isExpired }
        if validTokens.count != tokens.count {
            DispatchQueue.main.async {
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
            return "Password must be at least 6 characters long"
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
