#!/usr/bin/env swift

import Foundation

// Test script to verify what the macOS app is actually sending to GitHub

print("🔍 TESTING MACOS APP PAYLOAD")
print("============================")

// Simulate the exact payload structure from your macOS app
let cueStacks = [
    [
        "id": "stack1",
        "name": "DF 25 Main Keynote"
    ],
    [
        "id": "stack2", 
        "name": "DF25 E2 Scre"
    ],
    [
        "id": "stack3",
        "name": "Rehearsal Sc"
    ]
]

let allCues = [
    [
        "id": "stack1",
        "name": "DF 25 Main Keynote",
        "cues": [
            [
                "cueNumber": "1",
                "description": "House lights fade to black",
                "time": "00:00:00",
                "notes": "Start of show - ensure audience is seated"
            ],
            [
                "cueNumber": "2",
                "description": "Stage lights up - warm wash",
                "time": "00:00:05",
                "notes": "Reveal stage setup"
            ],
            [
                "cueNumber": "3",
                "description": "Spotlight on center stage",
                "time": "00:00:10",
                "notes": "Actor entrance"
            ]
        ]
    ],
    [
        "id": "stack2",
        "name": "DF25 E2 Scre",
        "cues": [
            [
                "cueNumber": "1",
                "description": "Screen test pattern",
                "time": "00:00:00",
                "notes": "Test screen display"
            ]
        ]
    ]
]

let cueData: [String: Any] = [
    "availableCueStacks": cueStacks,
    "allCues": allCues
]

let metadata: [String: Any] = [
    "filename": "DF_Keynote_25.json",
    "lastUpdated": "2025-01-15T10:30:00Z",
    "selectedCueStackIndex": 0,
    "totalCueStacks": 3
]

let payload: [String: Any] = [
    "event_type": "cue-data-update",
    "client_payload": [
        "cueData": cueData,
        "metadata": metadata
    ]
]

print("📊 PAYLOAD STRUCTURE:")
print("=====================")
print("📊 Cue data keys: \(cueData.keys.sorted())")
print("📊 Available cue stacks: \(cueStacks.count)")
print("📊 All cues: \(allCues.count)")

for (index, cueStack) in allCues.enumerated() {
    if let name = cueStack["name"] as? String,
       let cues = cueStack["cues"] as? [[String: Any]] {
        print("📊 Stack \(index): \(name) - \(cues.count) cues")
        for cue in cues.prefix(3) {
            if let cueNumber = cue["cueNumber"],
               let description = cue["description"] {
                print("   📊 Cue \(cueNumber): \(description)")
            }
        }
    }
}

do {
    let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
    let payloadString = String(data: jsonData, encoding: .utf8) ?? "Failed to convert"
    
    print("\n📄 ACTUAL PAYLOAD BEING SENT:")
    print("==============================")
    print(payloadString)
    
    // Save to file
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let fileURL = documentsPath.appendingPathComponent("real_payload_test.json")
    try jsonData.write(to: fileURL)
    print("\n💾 Saved to: \(fileURL.path)")
    
} catch {
    print("❌ Error: \(error)")
}

print("\n✅ This is what your macOS app should be sending to GitHub!")
print("The GitHub Actions workflow should receive this exact structure.")


