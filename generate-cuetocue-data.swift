#!/usr/bin/env swift

import Foundation

// MARK: - Data Models (matching your Cue to Cue app)

struct Cue: Codable {
    let id: String
    let values: [String]
    let timerValue: String
    let isStruckThrough: Bool
}

struct Column: Codable {
    let name: String
    let width: Double
}

struct CueStack: Codable {
    let id: String
    let name: String
    let cues: [Cue]
    let columns: [Column]
}

struct CueData: Codable {
    let cueStackId: String
    let cueStackName: String
    let columns: [Column]
    let cues: [CueDataItem]
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
    let availableCueStacks: [AvailableCueStack]
    let currentCueStackIndex: Int
    
    struct CueDataItem: Codable {
        let id: String
        let index: Int
        let values: [String]
        let timerValue: String
        let isStruckThrough: Bool
        let struck: [Bool]
    }
    
    struct AvailableCueStack: Codable {
        let name: String
        let index: Int
    }
}

// MARK: - Sample Data Generator

func generateSampleData() -> CueData {
    let now = Date()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "EEE MMM d, yyyy"
    
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "h:mm:ss"
    
    let amPmFormatter = DateFormatter()
    amPmFormatter.dateFormat = "a"
    
    let sampleCues = [
        CueData.CueDataItem(
            id: "cue-101",
            index: 0,
            values: ["101", "9:25a - Doors, Walk in Music, Walk in Lx, Preset 10", "10", "", "", "", "Rock", ""],
            timerValue: "",
            isStruckThrough: false,
            struck: Array(repeating: false, count: 8)
        ),
        CueData.CueDataItem(
            id: "cue-102",
            index: 1,
            values: ["102", "9:55a - ROLL RECORDS & Transition to APM", "", "", "", "", "APM", ""],
            timerValue: "",
            isStruckThrough: false,
            struck: Array(repeating: false, count: 8)
        ),
        CueData.CueDataItem(
            id: "cue-102-1",
            index: 2,
            values: ["102.01", "Preset 99 & LX 104", "99", "", "", "", "", ""],
            timerValue: "",
            isStruckThrough: false,
            struck: Array(repeating: false, count: 8)
        ),
        CueData.CueDataItem(
            id: "cue-102-2",
            index: 3,
            values: ["102.1", "Preset 5 & VT Opening", "5", "", "", "", "", ""],
            timerValue: "",
            isStruckThrough: false,
            struck: Array(repeating: false, count: 8)
        ),
        CueData.CueDataItem(
            id: "cue-103",
            index: 4,
            values: ["103", "Connor Mic Hot Out of VID", "", "", "", "", "", ""],
            timerValue: "",
            isStruckThrough: false,
            struck: Array(repeating: false, count: 8)
        ),
        CueData.CueDataItem(
            id: "cue-104",
            index: 5,
            values: ["104", "Connor VO & LX 105 [1 sac after note]", "", "", "", "", "", ""],
            timerValue: "",
            isStruckThrough: false,
            struck: Array(repeating: false, count: 8)
        ),
        CueData.CueDataItem(
            id: "cue-105",
            index: 6,
            values: ["105", "Preset 4 [on welcome]", "4", "", "", "", "", ""],
            timerValue: "",
            isStruckThrough: false,
            struck: Array(repeating: false, count: 8)
        )
    ]
    
    let sampleColumns = [
        Column(name: "#", width: 60),
        Column(name: "Description", width: 300),
        Column(name: "Preset", width: 100),
        Column(name: "Video", width: 100),
        Column(name: "LX", width: 100),
        Column(name: "L3", width: 100),
        Column(name: "Audio", width: 100),
        Column(name: "Staging", width: 100)
    ]
    
    let availableCueStacks = [
        CueData.AvailableCueStack(name: "BOS Keynote", index: 0),
        CueData.AvailableCueStack(name: "Sample Show 2", index: 1),
        CueData.AvailableCueStack(name: "Tech Rehearsal", index: 2)
    ]
    
    return CueData(
        cueStackId: "bos-keynote-001",
        cueStackName: "BOS Keynote",
        columns: sampleColumns,
        cues: sampleCues,
        activeCueIndex: 2,
        selectedCueIndex: 2,
        lastUpdateTime: now.timeIntervalSince1970,
        currentDate: dateFormatter.string(from: now),
        currentTime: timeFormatter.string(from: now),
        currentAMPM: amPmFormatter.string(from: now),
        countdownTime: 300, // 5 minutes
        countUpTime: 0,
        countdownRunning: true,
        countUpRunning: false,
        availableCueStacks: availableCueStacks,
        currentCueStackIndex: 0
    )
}

// MARK: - Main Execution

func main() {
    let data = generateSampleData()
    
    do {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try jsonEncoder.encode(data)
        
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
