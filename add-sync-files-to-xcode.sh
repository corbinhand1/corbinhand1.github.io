#!/bin/bash

# Add new Swift files to Xcode project
# This script adds WebsiteSyncManager.swift and WebsiteSyncSettingsView.swift to the project

PROJECT_FILE="/Users/corbinhand/Documents/Cue to Cue App/Cue to Cue Main Branch 1/Cue to Cue.xcodeproj/project.pbxproj"
SYNC_MANAGER_FILE="/Users/corbinhand/Documents/Cue to Cue App/Cue to Cue Main Branch 1/Cue to Cue/WebsiteSyncManager.swift"
SYNC_SETTINGS_FILE="/Users/corbinhand/Documents/Cue to Cue App/Cue to Cue Main Branch 1/Cue to Cue/WebsiteSyncSettingsView.swift"

echo "Adding WebsiteSyncManager.swift and WebsiteSyncSettingsView.swift to Xcode project..."

# Generate unique IDs for the new files
SYNC_MANAGER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24)
SYNC_SETTINGS_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24)
BUILD_FILE_SYNC_MANAGER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24)
BUILD_FILE_SYNC_SETTINGS_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24)

echo "Generated IDs:"
echo "  WebsiteSyncManager.swift: $SYNC_MANAGER_ID"
echo "  WebsiteSyncSettingsView.swift: $SYNC_SETTINGS_ID"

# Create backup of project file
cp "$PROJECT_FILE" "$PROJECT_FILE.backup"

echo "Backup created: $PROJECT_FILE.backup"

# Add PBXFileReference entries
cat >> "$PROJECT_FILE" << EOF

/* Begin PBXFileReference section - Website Sync Files */
		$SYNC_MANAGER_ID /* WebsiteSyncManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WebsiteSyncManager.swift; sourceTree = "<group>"; };
		$SYNC_SETTINGS_ID /* WebsiteSyncSettingsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WebsiteSyncSettingsView.swift; sourceTree = "<group>"; };
/* End PBXFileReference section - Website Sync Files */

EOF

# Add PBXBuildFile entries
cat >> "$PROJECT_FILE" << EOF

/* Begin PBXBuildFile section - Website Sync Files */
		$BUILD_FILE_SYNC_MANAGER_ID /* WebsiteSyncManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = $SYNC_MANAGER_ID /* WebsiteSyncManager.swift */; };
		$BUILD_FILE_SYNC_SETTINGS_ID /* WebsiteSyncSettingsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = $SYNC_SETTINGS_ID /* WebsiteSyncSettingsView.swift */; };
/* End PBXBuildFile section - Website Sync Files */

EOF

echo "✅ Added file references and build file entries to Xcode project"
echo ""
echo "⚠️  Manual steps required:"
echo "1. Open Xcode"
echo "2. Add WebsiteSyncManager.swift and WebsiteSyncSettingsView.swift to your project"
echo "3. Make sure they're added to the target"
echo "4. Build the project to verify everything works"
echo ""
echo "The files are ready to be added to your Xcode project!"


