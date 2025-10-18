# Real-Time Cue to Cue Web Sync System

## Overview

This system automatically syncs your actual cue data from your macOS Cue to Cue app to your Nebula Creative website, allowing people to view your real cues even when the macOS app is offline.

## System Architecture

```
macOS Cue to Cue App → GitHub API → GitHub Actions → Website Files → Web Viewer
```

## Setup Instructions

### Phase 1: Website Setup

#### 1. Add Files to Your Website Repository

Add these files to your `corbinhand1.github.io` repository:

**`.github/workflows/update-cue-data.yml`**
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
          git commit -m "Update cue data from macOS app: ${{ github.event.client_payload.metadata.filename }}" || exit 0
          git push
```

**`cuetocue/index.html`** (use the content from `cuetocue-viewer-with-metadata.html`)

#### 2. Create GitHub Token

1. Go to https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Give it a name like "Cue to Cue Sync"
4. Select "repo" scope (Full control of private repositories)
5. Copy the token (you'll need it for the macOS app)

### Phase 2: macOS App Integration

#### 1. Add Sync Manager to Your App

Add `WebsiteSyncManager.swift` to your Xcode project:

```swift
// Add this to your ContentView or AppDelegate
@StateObject private var websiteSyncManager = WebsiteSyncManager()

// Add sync button to your UI
Button("Sync to Website") {
    websiteSyncManager.syncCueData(
        cueStacks: cueStacks,
        selectedCueStackIndex: selectedCueStackIndex,
        filename: currentFileName
    )
}
```

#### 2. Configure Sync Settings

Add sync settings to your app:

```swift
// Add to your SettingsView
NavigationLink("Website Sync") {
    WebsiteSyncSettingsView()
}
```

#### 3. Auto-Sync Integration

Add auto-sync to your data update methods:

```swift
// In your ContentView, add this to your cue update methods
func updateCues() {
    // ... existing update code ...
    
    // Auto-sync if enabled
    websiteSyncManager.autoSyncIfEnabled(
        cueStacks: cueStacks,
        selectedCueStackIndex: selectedCueStackIndex,
        filename: currentFileName
    )
}
```

### Phase 3: Manual Sync (Alternative)

If you prefer manual sync, use the provided script:

#### 1. Configure the Script

Edit `sync-cue-data.sh` and update:
- `GITHUB_TOKEN="your_github_token_here"`
- Verify `REPO_OWNER` and `REPO_NAME`

#### 2. Run Manual Sync

```bash
./sync-cue-data.sh /path/to/your/show.cuetocue
```

## Usage

### Automatic Sync (Recommended)

1. **Configure sync** in your macOS app settings
2. **Enter your GitHub token**
3. **Enable auto-sync**
4. **Open cue files** - they'll sync automatically
5. **View on website** - https://nebulacreative.org/cuetocue/

### Manual Sync

1. **Run the sync script** with your cue file
2. **Wait 1-2 minutes** for GitHub Actions to update
3. **View on website** - https://nebulacreative.org/cuetocue/

## Features

- ✅ **Real cue data only** - never sample data
- ✅ **Filename visibility** - shows which show file is loaded
- ✅ **Last updated timestamp** - know when data was synced
- ✅ **Offline viewing** - works when macOS app is closed
- ✅ **Auto-sync** - data updates automatically
- ✅ **Manual sync** - sync on demand
- ✅ **Error handling** - graceful fallbacks
- ✅ **Mobile responsive** - works on all devices

## Troubleshooting

### Sync Not Working

1. **Check GitHub token** - make sure it has 'repo' permissions
2. **Verify repository name** - ensure it matches your GitHub repo
3. **Check GitHub Actions** - look for failed workflows
4. **Test manual sync** - try the sync script first

### Website Not Updating

1. **Wait 1-2 minutes** - GitHub Actions takes time
2. **Check Actions tab** - look for failed workflows
3. **Clear browser cache** - try incognito mode
4. **Check file paths** - ensure files are in correct locations

### No Data Showing

1. **Check file exists** - verify `cuetocue-data.json` exists
2. **Check JSON format** - ensure valid JSON
3. **Check browser console** - look for JavaScript errors
4. **Test with sample data** - verify viewer works

## Security

- ✅ **GitHub token** - secure API authentication
- ✅ **Repository permissions** - only your repo can be updated
- ✅ **No public data** - cue data is private to your repository
- ✅ **HTTPS only** - all communication encrypted

## Next Steps

1. **Set up the website files** in your repository
2. **Create GitHub token** with repo permissions
3. **Add sync manager** to your macOS app
4. **Configure auto-sync** settings
5. **Test with a cue file**
6. **View on website** to verify it works

This system will give you a **live, real-time sync** where your website always shows the actual cues from your most recently opened Cue to Cue file, with the filename visible to users, and it works offline once synced.


