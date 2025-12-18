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

struct SavedData: FileDocument, Codable {
    static var readableContentTypes: [UTType] { [.json] }

    var cueStacks: [CueStack]
    var highlightColors: [HighlightColorSetting]
    var pdfNotes: [String: [Int: String]] = [:]

    init(cueStacks: [CueStack], highlightColors: [HighlightColorSetting], pdfNotes: [String: [Int: String]] = [:]) {
        self.cueStacks = cueStacks
        self.highlightColors = highlightColors
        self.pdfNotes = pdfNotes
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decodedData = try JSONDecoder().decode(SavedData.self, from: data)
        self.cueStacks = decodedData.cueStacks
        self.highlightColors = decodedData.highlightColors
        self.pdfNotes = decodedData.pdfNotes
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(self)
        return FileWrapper(regularFileWithContents: data)
    }
}
