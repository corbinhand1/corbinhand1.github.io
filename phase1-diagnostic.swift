#!/usr/bin/env swift

import Foundation

// PHASE 1: IMMEDIATE DIAGNOSTIC FIX
// This script will analyze the exact payload structure being sent to GitHub

print("🔍 PHASE 1: IMMEDIATE DIAGNOSTIC FIX")
print("=====================================")

// Simulate the payload structure from the macOS app
let sampleCueData: [String: Any] = [
    "availableCueStacks": [
        [
            "id": "12345",
            "name": "DF 25 Main Keynote"
        ]
    ],
    "allCues": [
        [
            "id": "12345",
            "name": "DF 25 Main Keynote",
            "cues": [
                [
                    "cueNumber": "1",
                    "description": "House lights fade to black",
                    "time": "00:00:00",
                    "notes": "Start of show"
                ]
            ]
        ]
    ]
]

let sampleMetadata: [String: Any] = [
    "filename": "DF_Keynote_25.json",
    "lastUpdated": "2024-01-15T10:30:00Z",
    "selectedCueStackIndex": 0,
    "totalCueStacks": 6
]

let payload: [String: Any] = [
    "event_type": "cue-data-update",
    "client_payload": [
        "cueData": sampleCueData,
        "metadata": sampleMetadata
    ]
]

print("\n📊 PAYLOAD STRUCTURE ANALYSIS:")
print("===============================")

// 1. Enhanced Workflow Debugging
print("📊 Payload keys: \(payload.keys.sorted())")
if let clientPayload = payload["client_payload"] as? [String: Any] {
    print("📊 Client payload keys: \(clientPayload.keys.sorted())")
    
    if let cueData = clientPayload["cueData"] as? [String: Any] {
        print("📊 Cue data keys: \(cueData.keys.sorted())")
        
        if let availableCueStacks = cueData["availableCueStacks"] as? [[String: Any]] {
            print("📊 Available cue stacks count: \(availableCueStacks.count)")
            for (index, stack) in availableCueStacks.enumerated() {
                print("📊 Stack \(index): \(stack.keys.sorted())")
            }
        }
        
        if let allCues = cueData["allCues"] as? [[String: Any]] {
            print("📊 All cues count: \(allCues.count)")
            for (index, cueStack) in allCues.enumerated() {
                print("📊 Cue stack \(index): \(cueStack.keys.sorted())")
                if let cues = cueStack["cues"] as? [[String: Any]] {
                    print("📊 Cue stack \(index) cues count: \(cues.count)")
                }
            }
        }
    }
    
    if let metadata = clientPayload["metadata"] as? [String: Any] {
        print("📊 Metadata keys: \(metadata.keys.sorted())")
        print("📊 Filename: \(metadata["filename"] ?? "nil")")
        print("📊 Last updated: \(metadata["lastUpdated"] ?? "nil")")
    }
}

// 2. Payload Size Logging
do {
    let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
    print("\n📏 PAYLOAD SIZE ANALYSIS:")
    print("=========================")
    print("📏 Raw payload size: \(jsonData.count) bytes")
    print("📏 Payload size in KB: \(String(format: "%.2f", Double(jsonData.count) / 1024.0)) KB")
    
    // 3. Raw Payload Capture
    let payloadString = String(data: jsonData, encoding: .utf8) ?? "Failed to convert to string"
    print("\n📄 RAW PAYLOAD PREVIEW:")
    print("=======================")
    print("📄 First 500 characters:")
    print("📄 \(String(payloadString.prefix(500)))")
    
    // Save to file for analysis
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let payloadFileURL = documentsPath.appendingPathComponent("phase1_payload_analysis.json")
    try jsonData.write(to: payloadFileURL)
    print("\n💾 PAYLOAD SAVED TO FILE:")
    print("=========================")
    print("💾 File path: \(payloadFileURL.path)")
    
} catch {
    print("❌ Failed to serialize payload: \(error)")
}

// 4. Content-Type Verification
print("\n🔍 CONTENT-TYPE VERIFICATION:")
print("=============================")
print("🔍 Expected Content-Type: application/json")
print("🔍 Expected Accept: application/vnd.github.v3+json")
print("🔍 Expected Authorization: token <github_token>")

print("\n✅ PHASE 1 DIAGNOSTIC COMPLETE")
print("===============================")
print("Next steps:")
print("1. Run this diagnostic script")
print("2. Check the generated payload file")
print("3. Compare with GitHub Actions workflow expectations")
print("4. Implement Phase 2 fixes based on findings")
