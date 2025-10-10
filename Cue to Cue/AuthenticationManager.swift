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
            print("Could not access documents directory")
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
                print("✅ Loaded authentication data with \(users.count) users and \(permissions.count) permissions")
            } catch {
                print("❌ Error loading auth data: \(error)")
                authData = AuthData()
            }
        } else {
            print("📝 No existing auth data found, starting fresh")
            authData = AuthData()
        }
    }
    
    private func saveAuthData() {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Could not access documents directory")
            return
        }
        
        let authDataURL = documentsDirectory.appendingPathComponent(authDataFileName)
        
        do {
            authData.users = users
            authData.permissions = permissions
            authData.tokens = tokens
            
            let data = try JSONEncoder().encode(authData)
            try data.write(to: authDataURL)
            print("💾 Saved authentication data")
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
                allowedColumns: permissionRequest.allowedColumns
            )
            DispatchQueue.main.async {
                self.permissions.append(permission)
            }
        }
        
        saveAuthData()
        print("✅ Created user: \(username)")
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
        print("✅ Deleted user: \(user.username)")
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
                allowedColumns: permissionRequest.allowedColumns
            )
            DispatchQueue.main.async {
                self.permissions.append(permission)
            }
        }
        
        saveAuthData()
        print("✅ Updated permissions for user: \(userId)")
        return .success(())
    }
    
    // MARK: - Authentication
    
    func login(username: String, password: String) -> Result<LoginResponse, AuthError> {
        print("🔍 Attempting login for user: \(username)")
        print("🔍 Available users: \(users.map { $0.username })")
        
        guard let user = users.first(where: { $0.username.lowercased() == username.lowercased() }) else {
            print("❌ User not found: \(username)")
            return .failure(.invalidCredentials)
        }
        
        guard user.verifyPassword(password) else {
            print("❌ Invalid password for user: \(username)")
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
        print("✅ User logged out")
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
        print("🔍 Getting permissions for user ID: \(userId)")
        print("🔍 Available permissions: \(permissions.map { "\($0.userId) -> \($0.cueStackId): \($0.allowedColumns)" })")
        
        let userPermissions = permissions.filter { $0.userId == userId }
        print("🔍 User permissions found: \(userPermissions.count)")
        
        return cueStacks.compactMap { cueStack in
            let permission = userPermissions.first { $0.cueStackId == cueStack.id }
            let allowedColumns = permission?.allowedColumns ?? []
            let columnNames = allowedColumns.compactMap { index in
                index < cueStack.columns.count ? cueStack.columns[index].name : nil
            }
            
            print("🔍 CueStack \(cueStack.name): allowed columns \(allowedColumns) -> \(columnNames)")
            
            return PermissionResponse(
                cueStackId: cueStack.id,
                cueStackName: cueStack.name,
                allowedColumns: allowedColumns,
                columnNames: columnNames
            )
        }
    }
    
    func canUserEditColumn(_ userId: UUID, cueStackId: UUID, columnIndex: Int) -> Bool {
        print("🔍 Checking if user \(userId) can edit column \(columnIndex) in cue stack \(cueStackId)")
        
        guard let user = users.first(where: { $0.id == userId }) else {
            print("❌ User not found with ID: \(userId)")
            return false
        }
        
        print("🔍 Found user: \(user.username) (Admin: \(user.isAdmin))")
        
        // Admin users can edit all columns
        if user.isAdmin {
            print("✅ Admin user - can edit all columns")
            return true
        }
        
        // Check specific permissions
        let userPermissions = permissions.filter { $0.userId == userId }
        print("🔍 User has \(userPermissions.count) permission entries")
        
        guard let permission = userPermissions.first(where: { 
            $0.cueStackId == cueStackId 
        }) else {
            print("❌ No permission found for cue stack \(cueStackId)")
            print("🔍 Available permissions for user: \(userPermissions.map { "\($0.cueStackId): \($0.allowedColumns)" })")
            return false
        }
        
        print("🔍 Found permission for cue stack: allowed columns \(permission.allowedColumns)")
        let canEdit = permission.canEditColumn(columnIndex)
        print("🔍 Can edit column \(columnIndex): \(canEdit)")
        
        return canEdit
    }
    
    // MARK: - Helper Methods
    
    private func createDefaultAdminUserIfNeeded() {
        if users.isEmpty {
            let adminPassword = "admin123" // Change this in production!
            let adminUser = User(username: "admin", passwordHash: User.hashPassword(adminPassword), isAdmin: true)
            DispatchQueue.main.async {
                self.users.append(adminUser)
            }
            saveAuthData()
            print("🔐 Created default admin user (username: admin, password: admin123)")
        }
    }
    
    private func cleanupExpiredTokens() {
        let validTokens = tokens.filter { !$0.isExpired }
        if validTokens.count != tokens.count {
            DispatchQueue.main.async {
                self.tokens = validTokens
            }
            saveAuthData()
            print("🧹 Cleaned up \(tokens.count - validTokens.count) expired tokens")
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
        print("🔧 Starting createTestUserIfNeeded...")
        print("🔍 Current users: \(users.map { "\($0.username) (ID: \($0.id))" })")
        
        // Check if sherman user exists
        if !self.users.contains(where: { $0.username.lowercased() == "sherman" }) {
            print("🔧 Creating test user 'sherman'...")
            
            let result = self.createUser(username: "sherman", password: "password123", isAdmin: false)
            switch result {
            case .success(let user):
                print("✅ Created user: \(user.username) with ID: \(user.id)")
                
                // Get the first cue stack to set permissions
                if let firstCueStack = self.dataSyncManager.cueStacks.first {
                    print("🔧 Setting permissions for cue stack: \(firstCueStack.name) (ID: \(firstCueStack.id))")
                    print("🔧 Cue stack has \(firstCueStack.columns.count) columns: \(firstCueStack.columns.map { $0.name })")
                    
                    // Give sherman permission to edit the "Preset" column (index 2)
                    let permissionRequest = PermissionRequest(
                        cueStackId: firstCueStack.id,
                        allowedColumns: [2] // Preset column
                    )
                    
                    print("🔧 Creating permission request: cueStackId=\(permissionRequest.cueStackId), allowedColumns=\(permissionRequest.allowedColumns)")
                    
                    let permissionResult = self.updateUserPermissions(user.id, permissions: [permissionRequest])
                    switch permissionResult {
                    case .success:
                        print("✅ Set permissions for user \(user.username): can edit column 2 (Preset)")
                        print("🔍 Final permissions for user: \(self.permissions.filter { $0.userId == user.id }.map { "\($0.cueStackId): \($0.allowedColumns)" })")
                    case .failure(let error):
                        print("❌ Failed to set permissions: \(error)")
                    }
                } else {
                    print("❌ No cue stacks available for permissions")
                }
                
            case .failure(let error):
                print("❌ Failed to create user: \(error)")
            }
        } else {
            print("✅ User 'sherman' already exists")
            if let sherman = self.users.first(where: { $0.username.lowercased() == "sherman" }) {
                print("🔍 Sherman user details: ID=\(sherman.id), Admin=\(sherman.isAdmin)")
                let shermanPermissions = self.permissions.filter { $0.userId == sherman.id }
                print("🔍 Sherman permissions: \(shermanPermissions.map { "\($0.cueStackId): \($0.allowedColumns)" })")
            }
        }
    }
}
