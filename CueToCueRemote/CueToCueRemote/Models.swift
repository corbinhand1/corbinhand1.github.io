import Foundation

/// One stack's sheet as served by the Mac (GET /stack/<id>, GET /cues).
struct Sheet: Codable, Equatable {
    var cueStackId: String
    var cueStackName: String
    var columns: [SheetColumn]
    var cues: [SheetCue]
    var availableCueStacks: [StackSummary]
    var dataVersion: Int?
}

struct SheetColumn: Codable, Equatable, Identifiable {
    var name: String
    var width: Double
    var id: String { name }
    // Column names can repeat; identify by position when needed.
}

struct SheetCue: Codable, Equatable, Identifiable {
    var id: String
    var values: [String]
    var timerValue: String
    var isStruckThrough: Bool
}

struct StackSummary: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var cueCount: Int
}

struct LoginResult: Decodable {
    var success: Bool
    var token: String?
    var message: String?
    var user: LoginUser?
}

struct LoginUser: Decodable { var isAdmin: Bool }

struct ServerError: Decodable { var error: String? }
