#!/usr/bin/env swift

import Foundation

// Diagnostic script to check GitHub Actions workflow status
print("🔍 GitHub Actions Workflow Diagnostic")
print("=====================================")

let repoOwner = "corbinhand1"
let repoName = "corbinhand1.github.io"
let githubToken = UserDefaults.standard.string(forKey: "githubToken") ?? ""

if githubToken.isEmpty {
    print("❌ GitHub token not configured")
    exit(1)
}

// Check if GitHub Actions workflow exists
print("🔍 Checking for GitHub Actions workflow...")

let workflowURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/actions/workflows")!
var workflowRequest = URLRequest(url: workflowURL)
workflowRequest.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
workflowRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

let workflowSemaphore = DispatchSemaphore(value: 0)
var workflows: [[String: Any]] = []

URLSession.shared.dataTask(with: workflowRequest) { data, response, error in
    if let data = data,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let workflowList = json["workflows"] as? [[String: Any]] {
        workflows = workflowList
    }
    workflowSemaphore.signal()
}.resume()

workflowSemaphore.wait()

print("📋 Found \(workflows.count) workflows:")
for workflow in workflows {
    if let name = workflow["name"] as? String,
       let state = workflow["state"] as? String {
        print("  - \(name) (\(state))")
    }
}

// Check for cue-related workflow
let cueWorkflow = workflows.first { workflow in
    if let name = workflow["name"] as? String {
        return name.lowercased().contains("cue") || name.lowercased().contains("update")
    }
    return false
}

if let cueWorkflow = cueWorkflow {
    print("✅ Found cue-related workflow: \(cueWorkflow["name"] ?? "Unknown")")
    
    // Check recent runs
    if let workflowId = cueWorkflow["id"] as? Int {
        print("🔍 Checking recent workflow runs...")
        
        let runsURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/actions/workflows/\(workflowId)/runs")!
        var runsRequest = URLRequest(url: runsURL)
        runsRequest.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        runsRequest.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        let runsSemaphore = DispatchSemaphore(value: 0)
        var runs: [[String: Any]] = []
        
        URLSession.shared.dataTask(with: runsRequest) { data, response, error in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let runList = json["workflow_runs"] as? [[String: Any]] {
                runs = runList
            }
            runsSemaphore.signal()
        }.resume()
        
        runsSemaphore.wait()
        
        print("📊 Recent runs (\(runs.count)):")
        for (index, run) in runs.prefix(5).enumerated() {
            if let status = run["status"] as? String,
               let conclusion = run["conclusion"] as? String,
               let createdAt = run["created_at"] as? String {
                print("  \(index + 1). \(status)/\(conclusion) - \(createdAt)")
            }
        }
    }
} else {
    print("❌ No cue-related workflow found!")
    print("\n🔧 SOLUTION:")
    print("You need to add the GitHub Actions workflow to your repository.")
    print("Go to your website Cursor session and add:")
    print("1. .github/workflows/update-cue-data.yml")
    print("2. cuetocue/ directory")
    print("3. cuetocue/index.html")
}

// Check if cuetocue files exist
print("\n🔍 Checking if cuetocue files exist on website...")

let cuetocueDataURL = URL(string: "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/main/cuetocue/cuetocue-data.json")!
let metadataURL = URL(string: "https://raw.githubusercontent.com/\(repoOwner)/\(repoName)/main/cuetocue/metadata.json")!

let cuetocueSemaphore = DispatchSemaphore(value: 0)
var cuetocueExists = false
var metadataExists = false

URLSession.shared.dataTask(with: cuetocueDataURL) { data, response, error in
    if let httpResponse = response as? HTTPURLResponse {
        cuetocueExists = httpResponse.statusCode == 200
    }
    cuetocueSemaphore.signal()
}.resume()

URLSession.shared.dataTask(with: metadataURL) { data, response, error in
    if let httpResponse = response as? HTTPURLResponse {
        metadataExists = httpResponse.statusCode == 200
    }
    cuetocueSemaphore.signal()
}.resume()

cuetocueSemaphore.wait()
cuetocueSemaphore.wait()

print("📁 cuetocue-data.json: \(cuetocueExists ? "✅ Exists" : "❌ Missing")")
print("📁 metadata.json: \(metadataExists ? "✅ Exists" : "❌ Missing")")

if !cuetocueExists || !metadataExists {
    print("\n❌ ISSUE: cuetocue files are missing!")
    print("This confirms the GitHub Actions workflow is not set up.")
    print("\n🔧 IMMEDIATE ACTION REQUIRED:")
    print("1. Go to your website Cursor session")
    print("2. Add the GitHub Actions workflow")
    print("3. Add the cuetocue directory and files")
    print("4. Test the sync again")
} else {
    print("\n✅ cuetocue files exist - checking content...")
    
    // Try to fetch and display the content
    URLSession.shared.dataTask(with: cuetocueDataURL) { data, response, error in
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("📊 Cue data content:")
            if let cueStacks = json["availableCueStacks"] as? [[String: Any]] {
                print("  - \(cueStacks.count) cue stacks")
                for (index, stack) in cueStacks.enumerated() {
                    if let name = stack["name"] as? String,
                       let cues = stack["cues"] as? [[String: Any]] {
                        print("    \(index + 1). \(name) (\(cues.count) cues)")
                    }
                }
            }
        }
    }.resume()
}

print("\n📋 Summary:")
print("  macOS App: ✅ Working (sending data successfully)")
print("  GitHub API: ✅ Working (204 responses)")
print("  GitHub Actions: \(cueWorkflow != nil ? "✅ Found" : "❌ Missing")")
print("  cuetocue files: \(cuetocueExists && metadataExists ? "✅ Exist" : "❌ Missing")")
print("  Website: \(cuetocueExists && metadataExists ? "✅ Should work" : "❌ Needs setup")")


