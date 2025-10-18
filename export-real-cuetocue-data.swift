#!/usr/bin/env swift

import Foundation

// MARK: - Data Export Script for Real Cue to Cue Data
// This script exports actual cue data from your Cue to Cue app files

// MARK: - Data Models (matching your actual app)

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

// MARK: - Web Export Format (matching your local network viewer)

struct WebCueData: Codable {
    let cueStackId: String
    let cueStackName: String
    let columns: [WebColumn]
    let cues: [WebCue]
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
    let highlightColors: [WebHighlightColor]
    let availableCueStacks: [WebAvailableCueStack]
    let currentCueStackIndex: Int
    
    struct WebColumn: Codable {
        let name: String
        let width: Double
    }
    
    struct WebCue: Codable {
        let id: String
        let index: Int
        let values: [String]
        let timerValue: String
        let isStruckThrough: Bool
        let struck: [Bool]
    }
    
    struct WebHighlightColor: Codable {
        let keyword: String
        let color: String
    }
    
    struct WebAvailableCueStack: Codable {
        let name: String
        let index: Int
    }
}

// MARK: - Color Extension

extension Color {
    func toHex() -> String {
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - File Operations

func readCueDataFromFile(filePath: String) -> WebCueData? {
    guard let data = FileManager.default.contents(atPath: filePath) else {
        print("Error: Could not read file at \(filePath)")
        return nil
    }
    
    do {
        let decoder = JSONDecoder()
        let savedData = try decoder.decode(SavedData.self, from: data)
        return convertToWebFormat(savedData)
    } catch {
        print("Error decoding file: \(error)")
        return nil
    }
}

// MARK: - Data Conversion

func convertToWebFormat(_ savedData: SavedData) -> WebCueData {
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
    
    let webCues = cueStack.cues.enumerated().map { index, cue in
        WebCueData.WebCue(
            id: cue.id.uuidString,
            index: index,
            values: cue.values,
            timerValue: cue.timerValue,
            isStruckThrough: cue.isStruckThrough,
            struck: Array(repeating: cue.isStruckThrough, count: cueStack.columns.count)
        )
    }
    
    let webColumns = cueStack.columns.map { column in
        WebCueData.WebColumn(name: column.name, width: Double(column.width))
    }
    
    let webHighlightColors = savedData.highlightColors.map { colorSetting in
        WebCueData.WebHighlightColor(keyword: colorSetting.keyword, color: colorSetting.color.toHex())
    }
    
    let availableCueStacks = savedData.cueStacks.enumerated().map { index, stack in
        WebCueData.WebAvailableCueStack(name: stack.name, index: index)
    }
    
    return WebCueData(
        cueStackId: cueStack.id.uuidString,
        cueStackName: cueStack.name,
        columns: webColumns,
        cues: webCues,
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
        highlightColors: webHighlightColors,
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
        print("")
        print("This script exports your actual Cue to Cue data to JSON format")
        print("for use with the web viewer on your Nebula Creative website.")
        exit(1)
    }
    
    let filePath = arguments[1]
    
    guard let webData = readCueDataFromFile(filePath: filePath) else {
        print("Failed to read and convert cue data")
        exit(1)
    }
    
    do {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try jsonEncoder.encode(webData)
        
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

main()


