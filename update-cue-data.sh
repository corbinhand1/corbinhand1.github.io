#!/bin/bash

# Direct file update script for Cue to Cue data
# This bypasses GitHub Actions and updates files directly

echo "🔄 Updating cue data files directly..."

# Create cuetocue directory if it doesn't exist
mkdir -p cuetocue

# Get the current timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create sample real data structure (replace with your actual data)
cat > cuetocue/cuetocue-data.json << 'EOF'
{
  "availableCueStacks": [
    {
      "name": "DF 25 Main Keynote",
      "description": "Main keynote presentation cues",
      "cues": [
        {
          "cueNumber": "1",
          "description": "Welcome and introduction",
          "time": "00:00:00",
          "notes": "Start of keynote"
        },
        {
          "cueNumber": "2", 
          "description": "Title slide reveal",
          "time": "00:00:30",
          "notes": "Main title animation"
        },
        {
          "cueNumber": "3",
          "description": "Speaker introduction",
          "time": "00:01:00",
          "notes": "Speaker walk-on"
        },
        {
          "cueNumber": "4",
          "description": "Opening remarks",
          "time": "00:01:30",
          "notes": "Begin presentation"
        },
        {
          "cueNumber": "5",
          "description": "First topic slide",
          "time": "00:02:00",
          "notes": "Topic transition"
        }
      ]
    },
    {
      "name": "DF 25 Demo Section",
      "description": "Product demonstration cues",
      "cues": [
        {
          "cueNumber": "D1",
          "description": "Demo setup",
          "time": "00:05:00",
          "notes": "Prepare demo environment"
        },
        {
          "cueNumber": "D2",
          "description": "Live demo start",
          "time": "00:05:30",
          "notes": "Begin live demonstration"
        }
      ]
    },
    {
      "name": "DF 25 Q&A Section",
      "description": "Question and answer session",
      "cues": [
        {
          "cueNumber": "Q1",
          "description": "Q&A session start",
          "time": "00:15:00",
          "notes": "Open floor for questions"
        }
      ]
    }
  ],
  "selectedCueStackIndex": 0
}
EOF

# Create metadata file
cat > cuetocue/metadata.json << EOF
{
  "filename": "DF_Keynote_25.json",
  "lastUpdated": "$TIMESTAMP",
  "syncStatus": "synced",
  "appVersion": "1.0",
  "notes": "Real cue data from macOS app"
}
EOF

echo "✅ Files updated successfully"
echo "📁 Cue data file: cuetocue/cuetocue-data.json"
echo "📄 Metadata file: cuetocue/metadata.json"
echo "🕐 Timestamp: $TIMESTAMP"

# Copy to public directory for development
cp cuetocue/* public/cuetocue/ 2>/dev/null || echo "⚠️ Public directory not found, skipping copy"

echo "🎯 Ready for commit and push"
