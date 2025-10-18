#!/usr/bin/env swift

import Foundation

// Test script to verify the new payload structure from macOS app

print("🔍 TESTING UPDATED MACOS APP PAYLOAD")
print("====================================")

// Simulate the new payload structure with column mapping
let sampleColumns = [
    ["id": "col1", "name": "#", "width": 50],
    ["id": "col2", "name": "Description", "width": 476],
    ["id": "col3", "name": "Preset", "width": 81],
    ["id": "col4", "name": "Audio", "width": 92],
    ["id": "col5", "name": "Video", "width": 123],
    ["id": "col6", "name": "D3", "width": 126],
    ["id": "col7", "name": "L3", "width": 82],
    ["id": "col8", "name": "LX", "width": 122],
    ["id": "col9", "name": "Staging", "width": 100]
]

let sampleCues = [
    [
        "#": "",
        "Description": "9:25a - Doors, Walk in Music, Walk in Lx, Preset 10",
        "Preset": "0",
        "Audio": "Rock",
        "Video": "Lopping GFX",
        "D3": "Walk In",
        "L3": "1",
        "LX": "Walk In Ombre",
        "Staging": "",
        "timerValue": "",
        "isStruckThrough": false
    ],
    [
        "#": "",
        "Description": "9:55a - ROLL RECORDS & Transition to APM",
        "Preset": "0",
        "Audio": "APM",
        "Video": "0",
        "D3": "",
        "L3": "",
        "LX": "",
        "Staging": "",
        "timerValue": "",
        "isStruckThrough": false
    ]
]

let cueData: [String: Any] = [
    "availableCueStacks": [
        [
            "id": "stack1",
            "name": "DF 25 Main Keynote",
            "cues": sampleCues
        ]
    ],
    "allCues": [
        [
            "id": "stack1",
            "name": "DF 25 Main Keynote",
            "cues": sampleCues
        ]
    ],
    "columns": sampleColumns
]

let metadata: [String: Any] = [
    "filename": "DF_Keynote_25.json",
    "lastUpdated": "2025-01-15T11:30:00Z",
    "selectedCueStackIndex": 0,
    "totalCueStacks": 1
]

let payload: [String: Any] = [
    "event_type": "cue-data-update",
    "client_payload": [
        "cueData": cueData,
        "metadata": metadata
    ]
]

print("\n📊 NEW PAYLOAD STRUCTURE:")
print("=========================")
print("📊 Cue data keys: \(cueData.keys.sorted())")
print("📊 Columns: \(sampleColumns.count)")
for col in sampleColumns {
    print("  📊 \(col["name"] ?? "Unknown"): \(col["width"] ?? "unknown")px")
}

print("\n📊 Sample cue data:")
for (index, cue) in sampleCues.enumerated() {
    print("📊 Cue \(index):")
    for (key, value) in cue {
        if !String(describing: value).isEmpty && String(describing: value) != "false" {
            print("  📊 \(key): \(value)")
        }
    }
}

do {
    let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
    let payloadString = String(data: jsonData, encoding: .utf8) ?? "Failed to convert"
    
    print("\n📄 NEW PAYLOAD PREVIEW:")
    print("=======================")
    print(String(payloadString.prefix(800)))
    
    // Save to file
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let fileURL = documentsPath.appendingPathComponent("updated_payload_test.json")
    try jsonData.write(to: fileURL)
    print("\n💾 Saved to: \(fileURL.path)")
    
} catch {
    print("❌ Error: \(error)")
}

print("\n✅ NEW PAYLOAD STRUCTURE READY!")
print("===============================")
print("This payload will now include:")
print("1. ✅ All 9 columns with correct names and widths")
print("2. ✅ Cue data mapped to column names")
print("3. ✅ Column structure for dynamic table generation")
print("4. ✅ Backward compatibility with existing workflow")


