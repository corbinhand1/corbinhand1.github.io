//
//  Models.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/11/24.
//

import Foundation
import SwiftUI
import Combine
import UniformTypeIdentifiers
import CryptoKit

struct Cue: Identifiable, Equatable, Codable {
    var id = UUID()
    var values: [String]
    var timerValue: String
    var isStruckThrough: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case values
        case timerValue
        case isStruckThrough
    }

    init(id: UUID = UUID(), values: [String], timerValue: String = "", isStruckThrough: Bool = false) {
        self.id = id
        self.values = values
        self.timerValue = timerValue
        self.isStruckThrough = isStruckThrough
    }
}

struct Column: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var width: CGFloat
}

struct CueStack: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var cues: [Cue]
    var columns: [Column]
}

// MARK: - Countdown Playlist Models

struct PlaylistEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var timeString: String  // Format: "HH:mm:ss"
    var label: String?       // Optional label/name for the entry
    
    init(id: UUID = UUID(), timeString: String, label: String? = nil) {
        self.id = id
        self.timeString = timeString
        self.label = label
    }
}

struct CountdownPlaylist: Codable, Equatable {
    var entries: [PlaylistEntry]
    var currentIndex: Int?  // nil if not using playlist
    var isActive: Bool  // Kept for backward compatibility, always treated as true in logic
    var loopPlaylist: Bool
    
    init() {
        // Default playlist has one entry at 10:00:00 with label "Keynote Start"
        self.entries = [PlaylistEntry(timeString: "10:00:00", label: "Keynote Start")]
        self.currentIndex = 0  // First entry is current by default
        self.isActive = true  // Always active (playlist is the only mode)
        self.loopPlaylist = false
    }
}

struct SavedData: FileDocument, Decodable, Encodable {
    static var readableContentTypes: [UTType] { UTType.cueStackReadableTypes }

    var cueStacks: [CueStack]
    var highlightColors: [HighlightColorSetting]
    var pdfNotes: [String: [Int: String]] = [:]
    var countdownPlaylist: CountdownPlaylist = CountdownPlaylist()

    init(cueStacks: [CueStack], highlightColors: [HighlightColorSetting], pdfNotes: [String: [Int: String]] = [:], countdownPlaylist: CountdownPlaylist = CountdownPlaylist()) {
        self.cueStacks = cueStacks
        self.highlightColors = highlightColors
        self.pdfNotes = pdfNotes
        self.countdownPlaylist = countdownPlaylist
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Use standard decoder - our custom init(from:) handles backward compatibility
        let decoder = JSONDecoder()
        let decodedData = try decoder.decode(SavedData.self, from: data)
        self.cueStacks = decodedData.cueStacks
        self.highlightColors = decodedData.highlightColors
        self.pdfNotes = decodedData.pdfNotes
        self.countdownPlaylist = decodedData.countdownPlaylist
    }
    
    // Custom Decodable init for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields
        self.cueStacks = try container.decode([CueStack].self, forKey: .cueStacks)
        self.highlightColors = try container.decode([HighlightColorSetting].self, forKey: .highlightColors)
        self.pdfNotes = try container.decodeIfPresent([String: [Int: String]].self, forKey: .pdfNotes) ?? [:]
        
        // Backward compatibility: countdownPlaylist may not exist in old files
        var playlist: CountdownPlaylist
        if let decodedPlaylist = try? container.decodeIfPresent(CountdownPlaylist.self, forKey: .countdownPlaylist) {
            playlist = decodedPlaylist
            // Ensure isActive is true if entries exist (for old files that had isActive=false)
            if !playlist.entries.isEmpty && !playlist.isActive {
                playlist.isActive = true
            }
            // If playlist is empty, initialize with default entry
            if playlist.entries.isEmpty {
                playlist = CountdownPlaylist()  // This will create default entry
            }
        } else {
            // Field doesn't exist at all - create default playlist
            playlist = CountdownPlaylist()
        }
        self.countdownPlaylist = playlist
    }
    
    enum CodingKeys: String, CodingKey {
        case cueStacks, highlightColors, pdfNotes, countdownPlaylist
    }
    
    // Encodable implementation
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cueStacks, forKey: .cueStacks)
        try container.encode(highlightColors, forKey: .highlightColors)
        try container.encode(pdfNotes, forKey: .pdfNotes)
        try container.encode(countdownPlaylist, forKey: .countdownPlaylist)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(self)
        return FileWrapper(regularFileWithContents: data)
    }

    /// A clean starting document for File → New.
    static func blankDocument(highlightColors: [HighlightColorSetting]) -> SavedData {
        SavedData(
            cueStacks: [
                CueStack(
                    name: "Cue Stack 1",
                    cues: [],
                    columns: [
                        Column(name: "#", width: 60),
                        Column(name: "Description", width: 300),
                        Column(name: "Preset", width: 100),
                        Column(name: "Video", width: 100),
                        Column(name: "LX", width: 100),
                        Column(name: "Audio", width: 100),
                    ]
                )
            ],
            highlightColors: highlightColors,
            pdfNotes: [:],
            countdownPlaylist: CountdownPlaylist()
        )
    }
}

// MARK: - Authentication Models

struct User: Identifiable, Equatable, Hashable, Codable {
    var id = UUID()
    var username: String
    var passwordHash: String
    var isAdmin: Bool
    var createdAt: Date
    var lastLoginAt: Date?
    
    init(id: UUID = UUID(), username: String, passwordHash: String, isAdmin: Bool = false, createdAt: Date = Date(), lastLoginAt: Date? = nil) {
        self.id = id
        self.username = username
        self.passwordHash = passwordHash
        self.isAdmin = isAdmin
        self.createdAt = createdAt
        self.lastLoginAt = lastLoginAt
    }
    
    // Helper method to verify password
    func verifyPassword(_ password: String) -> Bool {
        let hashedPassword = SHA256.hash(data: password.data(using: .utf8) ?? Data())
        let hashString = hashedPassword.compactMap { String(format: "%02x", $0) }.joined()
        return hashString == passwordHash
    }
    
    // Helper method to hash password
    static func hashPassword(_ password: String) -> String {
        let hashedPassword = SHA256.hash(data: password.data(using: .utf8) ?? Data())
        return hashedPassword.compactMap { String(format: "%02x", $0) }.joined()
    }
}

struct Permission: Identifiable, Equatable, Codable {
    var id = UUID()
    var userId: UUID
    var cueStackId: UUID
    var allowedColumns: [String] // Array of column names user can edit
    var allowedColumnIndices: [Int]? // Legacy support for old index-based permissions
    var createdAt: Date
    
    init(id: UUID = UUID(), userId: UUID, cueStackId: UUID, allowedColumns: [String], allowedColumnIndices: [Int]? = nil, createdAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.cueStackId = cueStackId
        self.allowedColumns = allowedColumns
        self.allowedColumnIndices = allowedColumnIndices
        self.createdAt = createdAt
    }
    
    // Helper method to check if user can edit a specific column by name
    func canEditColumn(_ columnName: String) -> Bool {
        return allowedColumns.contains(columnName)
    }
    
    // Helper method to check if user can edit a specific column by index (for backward compatibility)
    func canEditColumnByIndex(_ columnIndex: Int, cueStack: CueStack) -> Bool {
        // First try the new name-based approach
        if columnIndex < cueStack.columns.count {
            let columnName = cueStack.columns[columnIndex].name
            if canEditColumn(columnName) {
                return true
            }
        }
        
        // Fall back to legacy index-based approach
        if let indices = allowedColumnIndices {
            return indices.contains(columnIndex)
        }
        
        return false
    }
}

struct AuthToken: Identifiable, Equatable, Codable {
    var id = UUID()
    var token: String
    var userId: UUID
    var expiresAt: Date
    var createdAt: Date
    
    init(id: UUID = UUID(), token: String, userId: UUID, expiresAt: Date, createdAt: Date = Date()) {
        self.id = id
        self.token = token
        self.userId = userId
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }
    
    // Helper method to check if token is expired
    var isExpired: Bool {
        return Date() > expiresAt
    }
    
    // Helper method to generate a new token
    static func generateToken(for userId: UUID, expiresInHours: Int = 24) -> AuthToken {
        let token = UUID().uuidString
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresInHours * 3600))
        return AuthToken(token: token, userId: userId, expiresAt: expiresAt)
    }
}

// MARK: - Request/Response Models

struct LoginRequest: Codable {
    let username: String
    let password: String
}

struct LoginResponse: Codable {
    let success: Bool
    let token: String?
    let user: User?
    let message: String?
    
    init(success: Bool, token: String? = nil, user: User? = nil, message: String? = nil) {
        self.success = success
        self.token = token
        self.user = user
        self.message = message
    }
}

struct PermissionResponse: Codable {
    let cueStackId: UUID
    let cueStackName: String
    let allowedColumns: [String] // Column names instead of indices
    let allowedColumnIndices: [Int]? // Legacy support
    let columnNames: [String] // All column names for reference
    
    init(cueStackId: UUID, cueStackName: String, allowedColumns: [String], allowedColumnIndices: [Int]? = nil, columnNames: [String]) {
        self.cueStackId = cueStackId
        self.cueStackName = cueStackName
        self.allowedColumns = allowedColumns
        self.allowedColumnIndices = allowedColumnIndices
        self.columnNames = columnNames
    }
}

struct UserResponse: Codable {
    let id: UUID
    let username: String
    let isAdmin: Bool
    let createdAt: Date
    let lastLoginAt: Date?
    let permissions: [PermissionResponse]
    
    init(user: User, permissions: [PermissionResponse]) {
        self.id = user.id
        self.username = user.username
        self.isAdmin = user.isAdmin
        self.createdAt = user.createdAt
        self.lastLoginAt = user.lastLoginAt
        self.permissions = permissions
    }
}

struct CreateUserRequest: Codable {
    let username: String
    let password: String
    let isAdmin: Bool
    let permissions: [PermissionRequest]
}

struct PermissionRequest: Codable {
    let cueStackId: UUID
    let allowedColumns: [String] // Column names instead of indices
    let allowedColumnIndices: [Int]? // Legacy support
}

struct EditCueRequest: Codable {
    let cueId: UUID
    let columnIndex: Int
    let newValue: String
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle cueId as either UUID or String
        if let uuidValue = try? container.decode(UUID.self, forKey: .cueId) {
            self.cueId = uuidValue
        } else if let stringValue = try? container.decode(String.self, forKey: .cueId),
                  let uuidFromString = UUID(uuidString: stringValue) {
            self.cueId = uuidFromString
        } else {
            throw DecodingError.typeMismatch(UUID.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected UUID or valid UUID string"))
        }
        
        self.columnIndex = try container.decode(Int.self, forKey: .columnIndex)
        self.newValue = try container.decode(String.self, forKey: .newValue)
    }
    
    private enum CodingKeys: String, CodingKey {
        case cueId, columnIndex, newValue
    }
}

struct AddCueRequest: Codable {
    let cueStackId: UUID
    let values: [String]
    let timerValue: String
}

struct DeleteCueRequest: Codable {
    let cueId: UUID
}

// MARK: - Authentication Data Storage

struct AuthData: Codable {
    var users: [User]
    var permissions: [Permission]
    var tokens: [AuthToken]
    
    init(users: [User] = [], permissions: [Permission] = [], tokens: [AuthToken] = []) {
        self.users = users
        self.permissions = permissions
        self.tokens = tokens
    }
}
