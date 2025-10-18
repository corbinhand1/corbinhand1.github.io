# GitHub Pages API Simulation for Cue to Cue Data Sync

Since GitHub Pages doesn't support server-side APIs, we'll use a different approach:

## Option 1: GitHub Actions + Webhook (Recommended)

Create a GitHub Action that receives webhook data and updates the cue data file.

### 1. Create `.github/workflows/update-cue-data.yml`

```yaml
name: Update Cue Data

on:
  repository_dispatch:
    types: [cue-data-update]

jobs:
  update-cue-data:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v3
        
      - name: Update cue data
        run: |
          echo '${{ github.event.client_payload.cueData }}' > cuetocue/cuetocue-data.json
          echo '${{ github.event.client_payload.metadata }}' > cuetocue/metadata.json
          
      - name: Commit changes
        run: |
          git config --local user.email "action@github.com"
          git config --local user.name "GitHub Action"
          git add cuetocue/cuetocue-data.json cuetocue/metadata.json
          git commit -m "Update cue data from macOS app" || exit 0
          git push
```

### 2. macOS App Integration Script

```bash
#!/bin/bash
# sync-cue-data.sh - Run this from your macOS app

# Configuration
GITHUB_TOKEN="your_github_token"
REPO_OWNER="corbinhand1"
REPO_NAME="corbinhand1.github.io"
CUEDATA_FILE="/path/to/your/cue/data.json"

# Read cue data
if [ ! -f "$CUEDATA_FILE" ]; then
    echo "Error: Cue data file not found: $CUEDATA_FILE"
    exit 1
fi

CUEDATA=$(cat "$CUEDATA_FILE")
METADATA=$(cat << EOF
{
    "filename": "$(basename "$CUEDATA_FILE")",
    "lastUpdated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "source": "macOS Cue to Cue App"
}
EOF
)

# Send to GitHub
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Content-Type: application/json" \
  -d "{\"event_type\":\"cue-data-update\",\"client_payload\":{\"cueData\":$CUEDATA,\"metadata\":$METADATA}}" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/dispatches"

echo "Cue data synced to website"
```

## Option 2: Simple File Upload (Alternative)

Use a simple file upload service or GitHub's file upload API.

### macOS App Integration (Simpler)

```swift
// Add this to your Cue to Cue app
import Foundation

class WebsiteSyncManager {
    private let githubToken = "your_github_token"
    private let repoOwner = "corbinhand1"
    private let repoName = "corbinhand1.github.io"
    
    func syncCueData(_ cueData: Data, filename: String) {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/contents/cuetocue/cuetocue-data.json")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("token \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let base64Data = cueData.base64EncodedString()
        let body = [
            "message": "Update cue data from \(filename)",
            "content": base64Data
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Sync error: \(error)")
            } else {
                print("Cue data synced successfully")
            }
        }.resume()
    }
}
```

## Option 3: Manual Sync Script (Simplest)

Create a simple script that you run manually to sync data.

```bash
#!/bin/bash
# manual-sync.sh

# Export cue data from your app
swift export-real-cuetocue-data.swift /path/to/your/show.cuetocue > temp-cue-data.json

# Copy to website directory
cp temp-cue-data.json /path/to/your/website/cuetocue/cuetocue-data.json

# Create metadata
cat > /path/to/your/website/cuetocue/metadata.json << EOF
{
    "filename": "$(basename /path/to/your/show.cuetocue)",
    "lastUpdated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "source": "Manual Sync"
}
EOF

# Commit and push
cd /path/to/your/website
git add cuetocue/
git commit -m "Update cue data: $(basename /path/to/your/show.cuetocue)"
git push

echo "Cue data synced to website"
```

## Recommendation

I recommend **Option 1 (GitHub Actions + Webhook)** because:
- ✅ Fully automated
- ✅ Works with GitHub Pages
- ✅ Secure (uses GitHub tokens)
- ✅ Real-time updates
- ✅ No server required

Would you like me to implement Option 1, or do you prefer a different approach?


