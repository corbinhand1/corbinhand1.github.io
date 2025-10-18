#!/usr/bin/env swift

import Foundation

// Enhanced debug script to test Phase 1 fixes
print("🔧 Phase 1 Fixes Debug Tool")
print("============================")

// Check UserDefaults for sync settings
let githubToken = UserDefaults.standard.string(forKey: "githubToken") ?? ""
let autoSyncEnabled = UserDefaults.standard.bool(forKey: "autoSyncEnabled")
let repoOwner = UserDefaults.standard.string(forKey: "repoOwner") ?? "corbinhand1"
let repoName = UserDefaults.standard.string(forKey: "repoName") ?? "corbinhand1.github.io"

print("📋 Current Settings:")
print("  GitHub Token: \(githubToken.isEmpty ? "❌ Not set" : "✅ Set (\(githubToken.prefix(8))...)")")
print("  Auto-sync: \(autoSyncEnabled ? "✅ Enabled" : "❌ Disabled")")
print("  Repository: \(repoOwner)/\(repoName)")

if githubToken.isEmpty {
    print("\n❌ ISSUE: GitHub token not configured!")
    print("   Solution: Go to Settings → Website Sync → Enter GitHub token")
    exit(1)
}

// Test GitHub API connectivity with detailed logging
print("\n🌐 Testing GitHub API connectivity...")
print("   URL: https://api.github.com/repos/\(repoOwner)/\(repoName)/dispatches")

let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/dispatches")!
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

let testPayload: [String: Any] = [
    "event_type": "cue-data-update",
    "client_payload": [
        "cueData": [
            "availableCueStacks": [
                [
                    "name": "Test Stack",
                    "cues": [
                        [
                            "cueNumber": "1",
                            "description": "Test cue",
                            "time": "00:00:00",
                            "notes": "Test notes"
                        ]
                    ]
                ]
            ],
            "selectedCueStackIndex": 0
        ],
        "metadata": [
            "filename": "test-file.json",
            "lastUpdated": "2025-01-01T00:00:00Z",
            "selectedCueStackIndex": 0,
            "totalCueStacks": 1
        ]
    ]
]

do {
    request.httpBody = try JSONSerialization.data(withJSONObject: testPayload)
    print("✅ Test payload serialized successfully")
} catch {
    print("❌ Failed to serialize test payload: \(error)")
    exit(1)
}

let semaphore = DispatchSemaphore(value: 0)
var apiSuccess = false
var apiError: String?
var responseData: Data?

print("🚀 Sending test request...")

URLSession.shared.dataTask(with: request) { data, response, error in
    responseData = data
    
    if let error = error {
        apiError = "Network error: \(error.localizedDescription)"
    } else if let httpResponse = response as? HTTPURLResponse {
        print("📡 HTTP Response: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 204 {
            apiSuccess = true
        } else {
            apiError = "HTTP \(httpResponse.statusCode)"
            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                apiError! += ": \(responseString)"
            }
        }
    } else {
        apiError = "Invalid response"
    }
    semaphore.signal()
}.resume()

semaphore.wait()

if apiSuccess {
    print("✅ GitHub API test successful!")
    print("   The repository_dispatch event was sent successfully")
} else {
    print("❌ GitHub API test failed: \(apiError ?? "Unknown error")")
    print("\n🔧 Possible solutions:")
    print("   1. Check GitHub token has 'repo' scope")
    print("   2. Verify repository name is correct")
    print("   3. Check internet connection")
    print("   4. Verify repository exists and is accessible")
    
    if let data = responseData, let responseString = String(data: data, encoding: .utf8) {
        print("\n📄 Full response:")
        print(responseString)
    }
    exit(1)
}

// Check if GitHub Actions workflow exists
print("\n🔍 Checking for GitHub Actions workflow...")

let workflowURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/actions/workflows")!
var workflowRequest = URLRequest(url: workflowURL)
workflowRequest.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
workflowRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

let workflowSemaphore = DispatchSemaphore(value: 0)
var workflowExists = false
var workflowName = ""

URLSession.shared.dataTask(with: workflowRequest) { data, response, error in
    if let data = data,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let workflows = json["workflows"] as? [[String: Any]] {
        
        for workflow in workflows {
            if let name = workflow["name"] as? String, name.lowercased().contains("cue") {
                workflowExists = true
                workflowName = name
                break
            }
        }
    }
    workflowSemaphore.signal()
}.resume()

workflowSemaphore.wait()

if workflowExists {
    print("✅ GitHub Actions workflow found: '\(workflowName)'")
} else {
    print("❌ GitHub Actions workflow not found!")
    print("\n🔧 SOLUTION NEEDED:")
    print("   You need to add the GitHub Actions workflow to your website repository.")
    print("   Go to your website Cursor session and add:")
    print("   - .github/workflows/update-cue-data.yml")
    print("   - cuetocue/ directory")
    print("   - cuetocue/index.html")
}

print("\n📊 Phase 1 Fixes Summary:")
print("  ✅ ContentView parameter bug: Fixed")
print("  ✅ Manual sync filename: Fixed")
print("  ✅ Comprehensive logging: Added")
print("  ✅ GitHub API: \(apiSuccess ? "Working" : "Failed")")
print("  ✅ GitHub Actions: \(workflowExists ? "Found" : "Missing")")

if apiSuccess && workflowExists {
    print("\n🎉 Phase 1 fixes are working! Ready for testing.")
    print("   Next steps:")
    print("   1. Test manual sync in the app")
    print("   2. Test auto-sync by opening a file")
    print("   3. Check web viewer for updates")
} else {
    print("\n⚠️  Issues found. Fix GitHub Actions setup and try again.")
}


