#!/bin/bash

# Cue to Cue Data Sync Script
# This script syncs cue data from your macOS app to your Nebula Creative website

# Configuration - UPDATE THESE VALUES
GITHUB_TOKEN="your_github_token_here"
REPO_OWNER="corbinhand1"
REPO_NAME="corbinhand1.github.io"
CUEDATA_FILE="$1"  # Pass the .cuetocue file path as first argument

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🎭 Cue to Cue Data Sync${NC}"
echo "=================================="

# Check if file path is provided
if [ -z "$CUEDATA_FILE" ]; then
    echo -e "${RED}Error: Please provide the path to your .cuetocue file${NC}"
    echo "Usage: $0 /path/to/your/show.cuetocue"
    exit 1
fi

# Check if file exists
if [ ! -f "$CUEDATA_FILE" ]; then
    echo -e "${RED}Error: File not found: $CUEDATA_FILE${NC}"
    exit 1
fi

# Check if GitHub token is set
if [ "$GITHUB_TOKEN" = "your_github_token_here" ]; then
    echo -e "${RED}Error: Please set your GitHub token in this script${NC}"
    echo "Get a token from: https://github.com/settings/tokens"
    echo "Make sure it has 'repo' permissions"
    exit 1
fi

# Export cue data using Swift script
echo -e "${YELLOW}📊 Exporting cue data...${NC}"
TEMP_CUEDATA=$(mktemp)
swift export-real-cuetocue-data.swift "$CUEDATA_FILE" > "$TEMP_CUEDATA"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to export cue data${NC}"
    rm -f "$TEMP_CUEDATA"
    exit 1
fi

# Create metadata
FILENAME=$(basename "$CUEDATA_FILE")
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

METADATA=$(cat << EOF
{
    "filename": "$FILENAME",
    "lastUpdated": "$TIMESTAMP",
    "source": "macOS Cue to Cue App",
    "syncMethod": "GitHub Actions"
}
EOF
)

echo -e "${YELLOW}🚀 Syncing to website...${NC}"

# Send to GitHub using repository dispatch
RESPONSE=$(curl -s -w "%{http_code}" -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Content-Type: application/json" \
  -d "{\"event_type\":\"cue-data-update\",\"client_payload\":{\"cueData\":$(cat "$TEMP_CUEDATA"),\"metadata\":$METADATA}}" \
  "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/dispatches")

HTTP_CODE="${RESPONSE: -3}"
RESPONSE_BODY="${RESPONSE%???}"

if [ "$HTTP_CODE" = "204" ]; then
    echo -e "${GREEN}✅ Cue data synced successfully!${NC}"
    echo -e "${GREEN}📁 File: $FILENAME${NC}"
    echo -e "${GREEN}🕐 Timestamp: $TIMESTAMP${NC}"
    echo -e "${GREEN}🌐 Website: https://nebulacreative.org/cuetocue/${NC}"
    echo ""
    echo -e "${YELLOW}Note: It may take 1-2 minutes for the website to update${NC}"
else
    echo -e "${RED}❌ Sync failed (HTTP $HTTP_CODE)${NC}"
    echo "Response: $RESPONSE_BODY"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check your GitHub token has 'repo' permissions"
    echo "2. Verify the repository name is correct"
    echo "3. Make sure the GitHub Action workflow is set up"
fi

# Cleanup
rm -f "$TEMP_CUEDATA"

echo ""
echo -e "${YELLOW}🎭 Sync complete!${NC}"


