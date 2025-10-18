#!/bin/bash

# Add CellTextFieldWrapper.swift to Xcode project

PROJECT_FILE="/Users/corbinhand/Documents/Cue to Cue App/Cue to Cue Main Branch 1/Cue to Cue.xcodeproj/project.pbxproj"
WRAPPER_FILE="/Users/corbinhand/Documents/Cue to Cue App/Cue to Cue Main Branch 1/Cue to Cue/CellTextFieldWrapper.swift"

echo "Adding CellTextFieldWrapper.swift to Xcode project..."

# Generate unique IDs for the new file
WRAPPER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24)
BUILD_FILE_WRAPPER_ID=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-24)

echo "Generated IDs:"
echo "  CellTextFieldWrapper.swift: $WRAPPER_ID"

# Create backup of project file
cp "$PROJECT_FILE" "$PROJECT_FILE.backup"

echo "Backup created: $PROJECT_FILE.backup"

# Add PBXFileReference entry
cat >> "$PROJECT_FILE" << EOF

/* Begin PBXFileReference section - CellTextFieldWrapper */
		$WRAPPER_ID /* CellTextFieldWrapper.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CellTextFieldWrapper.swift; sourceTree = "<group>"; };
/* End PBXFileReference section - CellTextFieldWrapper */

EOF

# Add PBXBuildFile entry
cat >> "$PROJECT_FILE" << EOF

/* Begin PBXBuildFile section - CellTextFieldWrapper */
		$BUILD_FILE_WRAPPER_ID /* CellTextFieldWrapper.swift in Sources */ = {isa = PBXBuildFile; fileRef = $WRAPPER_ID /* CellTextFieldWrapper.swift */; };
/* End PBXBuildFile section - CellTextFieldWrapper */

EOF

echo "✅ Added file reference and build file entry to Xcode project"
echo ""
echo "⚠️  Manual steps required:"
echo "1. Open Xcode"
echo "2. Add CellTextFieldWrapper.swift to your project"
echo "3. Make sure it's added to the target"
echo "4. Build the project to verify everything works"
echo ""
echo "The file is ready to be added to your Xcode project!"


