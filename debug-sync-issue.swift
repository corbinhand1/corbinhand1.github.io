#!/usr/bin/env swift

import Foundation

// Debug script to test sync functionality
print("🔍 Cue to Cue Sync Debug Tool")
print("================================")

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

// Test GitHub API connectivity
print("\n🌐 Testing GitHub API connectivity...")

let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/dispatches")!
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

let testPayload: [String: Any] = [
    "event_type": "cue-data-update",
    "client_payload": [
        "cueData": ["test": "data"],
        "metadata": ["filename": "test-file.json", "lastUpdated": "2025-01-01T00:00:00Z"]
    ]
]

do {
    request.httpBody = try JSONSerialization.data(withJSONObject: testPayload)
} catch {
    print("❌ Failed to serialize test payload: \(error)")
    exit(1)
}

let semaphore = DispatchSemaphore(value: 0)
var apiSuccess = false
var apiError: String?

URLSession.shared.dataTask(with: request) { data, response, error in
    if let error = error {
        apiError = "Network error: \(error.localizedDescription)"
    } else if let httpResponse = response as? HTTPURLResponse {
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
} else {
    print("❌ GitHub API test failed: \(apiError ?? "Unknown error")")
    print("\n🔧 Possible solutions:")
    print("   1. Check GitHub token has 'repo' scope")
    print("   2. Verify repository name is correct")
    print("   3. Check internet connection")
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

URLSession.shared.dataTask(with: workflowRequest) { data, response, error in
    if let data = data,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let workflows = json["workflows"] as? [[String: Any]] {
        
        for workflow in workflows {
            if let name = workflow["name"] as? String, name.contains("cue") {
                workflowExists = true
                break
            }
        }
    }
    workflowSemaphore.signal()
}.resume()

workflowSemaphore.wait()

if workflowExists {
    print("✅ GitHub Actions workflow found!")
} else {
    print("❌ GitHub Actions workflow not found!")
    print("\n🔧 SOLUTION NEEDED:")
    print("   You need to add the GitHub Actions workflow to your website repository.")
    print("   Go to your website Cursor session and add:")
    print("   - .github/workflows/update-cue-data.yml")
    print("   - cuetocue/ directory")
    print("   - cuetocue/index.html")
}

print("\n📊 Summary:")
print("  macOS App Sync: ✅ Ready")
print("  GitHub API: \(apiSuccess ? "✅ Working" : "❌ Failed")")
print("  GitHub Actions: \(workflowExists ? "✅ Found" : "❌ Missing")")

if apiSuccess && workflowExists {
    print("\n🎉 Everything looks good! Try syncing from your app now.")
} else {
    print("\n⚠️  Issues found. Fix them and try again.")
}


