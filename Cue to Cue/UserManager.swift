//
//  UserManager.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 12/19/24.
//

import Foundation
import SwiftUI
import Combine

// MARK: - User Models

struct User: Codable, Identifiable {
    let id: UUID
    var username: String
    var password: String // In production, this should be hashed
    var role: UserRole
    var canEditPresetColumn: Bool
    var createdAt: Date
    var lastLogin: Date?
    
    init(id: UUID = UUID(), username: String, password: String, role: UserRole, canEditPresetColumn: Bool = false) {
        self.id = id
        self.username = username
        self.password = password
        self.role = role
        self.canEditPresetColumn = canEditPresetColumn
        self.createdAt = Date()
        self.lastLogin = nil
    }
}

enum UserRole: String, Codable, CaseIterable {
    case admin = "admin"
    case editor = "editor"
    case viewer = "viewer"
    
    var displayName: String {
        switch self {
        case .admin: return "Administrator"
        case .editor: return "Editor"
        case .viewer: return "Viewer"
        }
    }
    
    var canEditPresetColumn: Bool {
        switch self {
        case .admin: return true
        case .editor: return true
        case .viewer: return false
        }
    }
}

// MARK: - User Manager

class UserManager: ObservableObject {
    @Published var currentUser: User?
    @Published var isLoggedIn: Bool = false
    @Published var users: [User] = []
    
    private let userDefaultsKey = "CueToCueUsers"
    private let currentUserKey = "CueToCueCurrentUser"
    
    init() {
        loadUsers()
        loadCurrentUser()
    }
    
    // MARK: - User Management
    
    func login(username: String, password: String) -> Bool {
        guard let user = users.first(where: { $0.username == username && $0.password == password }) else {
            return false
        }
        
        var updatedUser = user
        updatedUser.lastLogin = Date()
        
        // Update user in array
        if let index = users.firstIndex(where: { $0.id == user.id }) {
            users[index] = updatedUser
        }
        
        currentUser = updatedUser
        isLoggedIn = true
        
        saveUsers()
        saveCurrentUser()
        
        return true
    }
    
    func logout() {
        currentUser = nil
        isLoggedIn = false
        UserDefaults.standard.removeObject(forKey: currentUserKey)
    }
    
    func createUser(username: String, password: String, role: UserRole) -> Bool {
        // Check if username already exists
        guard !users.contains(where: { $0.username == username }) else {
            return false
        }
        
        let newUser = User(
            username: username,
            password: password,
            role: role,
            canEditPresetColumn: role.canEditPresetColumn
        )
        
        users.append(newUser)
        saveUsers()
        return true
    }
    
    func updateUser(_ user: User) {
        if let index = users.firstIndex(where: { $0.id == user.id }) {
            users[index] = user
            saveUsers()
            
            // Update current user if it's the same user
            if currentUser?.id == user.id {
                currentUser = user
                saveCurrentUser()
            }
        }
    }
    
    func deleteUser(_ user: User) {
        users.removeAll { $0.id == user.id }
        saveUsers()
        
        // Logout if we deleted the current user
        if currentUser?.id == user.id {
            logout()
        }
    }
    
    // MARK: - Permission Checking
    
    func canEditPresetColumn() -> Bool {
        return currentUser?.canEditPresetColumn ?? false
    }
    
    func hasRole(_ role: UserRole) -> Bool {
        return currentUser?.role == role
    }
    
    func isAdmin() -> Bool {
        return hasRole(.admin)
    }
    
    // MARK: - Data Persistence
    
    private func loadUsers() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decodedUsers = try? JSONDecoder().decode([User].self, from: data) {
            self.users = decodedUsers
        } else {
            // Create default admin user if no users exist
            createDefaultUsers()
        }
    }
    
    private func saveUsers() {
        if let encodedData = try? JSONEncoder().encode(users) {
            UserDefaults.standard.set(encodedData, forKey: userDefaultsKey)
        }
    }
    
    private func loadCurrentUser() {
        if let data = UserDefaults.standard.data(forKey: currentUserKey),
           let decodedUser = try? JSONDecoder().decode(User.self, from: data) {
            self.currentUser = decodedUser
            self.isLoggedIn = true
        }
    }
    
    private func saveCurrentUser() {
        if let user = currentUser,
           let encodedData = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encodedData, forKey: currentUserKey)
        }
    }
    
    private func createDefaultUsers() {
        // Create default admin user
        let adminUser = User(
            username: "admin",
            password: "admin123", // Change this in production!
            role: .admin,
            canEditPresetColumn: true
        )
        
        // Create default editor user
        let editorUser = User(
            username: "editor",
            password: "editor123", // Change this in production!
            role: .editor,
            canEditPresetColumn: true
        )
        
        // Create default viewer user
        let viewerUser = User(
            username: "viewer",
            password: "viewer123", // Change this in production!
            role: .viewer,
            canEditPresetColumn: false
        )
        
        users = [adminUser, editorUser, viewerUser]
        saveUsers()
    }
}
