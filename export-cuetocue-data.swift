#!/usr/bin/env swift

import Foundation

// MARK: - Data Export Script for Cue to Cue App
// This script can be run to export current cue data to JSON format
// for use with the web viewer

// MARK: - Data Models (matching your Cue to Cue app)

struct ExportedCue: Codable {
    let id: String
    let values: [String]
    let timerValue: String
    let isStruckThrough: Bool
}

struct ExportedColumn: Codable {
    let name: String
    let width: Double
}

struct ExportedCueStack: Codable {
    let id: String
    let name: String
    let cues: [ExportedCue]
    let columns: [ExportedColumn]
}

struct ExportedData: Codable {
    let cueStackId: String
    let cueStackName: String
    let columns: [ExportedColumn]
    let cues: [ExportedCueData]
    let activeCueIndex: Int
    let selectedCueIndex: Int
    let lastUpdateTime: Double
    let currentDate: String
    let currentTime: String
    let currentAMPM: String
    let countdownTime: Int
    let countUpTime: Int
    let countdownRunning: Bool
    let countUpRunning: Bool
    let availableCueStacks: [ExportedAvailableCueStack]
    let currentCueStackIndex: Int
    
    struct ExportedCueData: Codable {
        let id: String
        let index: Int
        let values: [String]
        let timerValue: String
        let isStruckThrough: Bool
        let struck: [Bool]
    }
    
    struct ExportedAvailableCueStack: Codable {
        let name: String
        let index: Int
    }
}

// MARK: - File Operations

func readCueDataFromFile(filePath: String) -> ExportedData? {
    guard let data = FileManager.default.contents(atPath: filePath) else {
        print("Error: Could not read file at \(filePath)")
        return nil
    }
    
    do {
        let decoder = JSONDecoder()
        let savedData = try decoder.decode(SavedData.self, from: data)
        return convertToExportedData(savedData)
    } catch {
        print("Error decoding file: \(error)")
        return nil
    }
}

// MARK: - Data Conversion

func convertToExportedData(_ savedData: SavedData) -> ExportedData {
    let now = Date()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "EEE MMM d, yyyy"
    
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "h:mm:ss"
    
    let amPmFormatter = DateFormatter()
    amPmFormatter.dateFormat = "a"
    
    // Use the first cue stack as default, or create sample data if none exist
    let cueStack = savedData.cueStacks.first ?? createSampleCueStack()
    let selectedIndex = 0
    
    let exportedCues = cueStack.cues.enumerated().map { index, cue in
        ExportedData.ExportedCueData(
            id: cue.id.uuidString,
            index: index,
            values: cue.values,
            timerValue: cue.timerValue,
            isStruckThrough: cue.isStruckThrough,
            struck: Array(repeating: cue.isStruckThrough, count: cueStack.columns.count)
        )
    }
    
    let exportedColumns = cueStack.columns.map { column in
        ExportedColumn(name: column.name, width: Double(column.width))
    }
    
    let availableCueStacks = savedData.cueStacks.enumerated().map { index, stack in
        ExportedData.ExportedAvailableCueStack(name: stack.name, index: index)
    }
    
    return ExportedData(
        cueStackId: cueStack.id.uuidString,
        cueStackName: cueStack.name,
        columns: exportedColumns,
        cues: exportedCues,
        activeCueIndex: -1, // No active cue by default
        selectedCueIndex: -1, // No selected cue by default
        lastUpdateTime: now.timeIntervalSince1970,
        currentDate: dateFormatter.string(from: now),
        currentTime: timeFormatter.string(from: now),
        currentAMPM: amPmFormatter.string(from: now),
        countdownTime: 0,
        countUpTime: 0,
        countdownRunning: false,
        countUpRunning: false,
        availableCueStacks: availableCueStacks,
        currentCueStackIndex: selectedIndex
    )
}

func createSampleCueStack() -> CueStack {
    return CueStack(
        name: "Sample Cue Stack",
        cues: [
            Cue(values: ["101", "Sample cue 1", "10", "", "", "", "Rock", ""], timerValue: ""),
            Cue(values: ["102", "Sample cue 2", "", "", "", "", "APM", ""], timerValue: ""),
            Cue(values: ["103", "Sample cue 3", "5", "", "", "", "", ""], timerValue: "")
        ],
        columns: [
            Column(name: "#", width: 60),
            Column(name: "Description", width: 300),
            Column(name: "Preset", width: 100),
            Column(name: "Video", width: 100),
            Column(name: "LX", width: 100),
            Column(name: "L3", width: 100),
            Column(name: "Audio", width: 100),
            Column(name: "Staging", width: 100)
        ]
    )
}

// MARK: - Main Execution

func main() {
    let arguments = CommandLine.arguments
    
    if arguments.count < 2 {
        print("Usage: \(arguments[0]) <path-to-cue-file>")
        print("Example: \(arguments[0]) ~/Documents/MyShow.cuetocue")
        exit(1)
    }
    
    let filePath = arguments[1]
    
    guard let exportedData = readCueDataFromFile(filePath: filePath) else {
        print("Failed to read and convert cue data")
        exit(1)
    }
    
    do {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try jsonEncoder.encode(exportedData)
        
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        } else {
            print("Error: Failed to convert data to string")
            exit(1)
        }
    } catch {
        print("Error encoding data: \(error)")
        exit(1)
    }
}

// MARK: - Supporting Types (matching your app's Models.swift)

struct Cue: Codable {
    let id: UUID
    let values: [String]
    let timerValue: String
    let isStruckThrough: Bool
}

struct Column: Codable {
    let id: UUID
    let name: String
    let width: CGFloat
}

struct CueStack: Codable {
    let id: UUID
    let name: String
    let cues: [Cue]
    let columns: [Column]
}

struct HighlightColorSetting: Codable {
    let keyword: String
    let color: Color
}

struct Color: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

struct SavedData: Codable {
    let cueStacks: [CueStack]
    let highlightColors: [HighlightColorSetting]
    let pdfNotes: [String: [Int: String]]
}

main()



