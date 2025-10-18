#!/bin/bash

# Cue to Cue Web Viewer Deployment Script
# This script helps deploy the web viewer to your Nebula Creative website

set -e

echo "🎭 Cue to Cue Web Viewer Deployment Script"
echo "=========================================="

# Configuration
WEBSITE_DIR="/Users/corbinhand/Documents/Cue to Cue App/Cue to Cue Main Branch 1"
OUTPUT_DIR="./cuetocue-web-viewer"
VIEWER_FILE="cuetocue-viewer.html"
DATA_FILE="cuetocue-data.json"

# Create output directory
echo "📁 Creating output directory..."
mkdir -p "$OUTPUT_DIR"

# Copy the real viewer HTML file with metadata support
echo "📄 Copying real viewer HTML with metadata..."
cp "$WEBSITE_DIR/cuetocue-viewer-with-metadata.html" "$OUTPUT_DIR/index.html"

# Generate sample data (you can replace this with real data export)
echo "📊 Generating sample data..."
cd "$WEBSITE_DIR"
swift generate-cuetocue-data.swift > "$OUTPUT_DIR/$DATA_FILE"

# Create a simple README
echo "📝 Creating README..."
cat > "$OUTPUT_DIR/README.md" << 'EOF'
# Cue to Cue Web Viewer

A simple, read-only web viewer for Cue to Cue show data.

## Files

- `index.html` - The main viewer interface
- `cuetocue-data.json` - The cue data (update this with your actual show data)

## Usage

1. **Update Data**: Replace `cuetocue-data.json` with your actual cue data
2. **Deploy**: Upload the contents of this directory to your web server
3. **Access**: Visit `https://nebulacreative.org/cuetocue/` to view your cues

## Data Export

To export data from your Cue to Cue app:

```bash
# Export from a saved .cuetocue file
swift export-real-cuetocue-data.swift /path/to/your/show.cuetocue > cuetocue-data.json
```

**IMPORTANT**: Replace the sample data with your actual show data for the viewer to work properly.

## Features

- ✅ Read-only viewing (no editing)
- ✅ Real-time clock updates
- ✅ Responsive design for mobile/desktop
- ✅ Multiple cue stack support
- ✅ Clean, professional interface
- ✅ Matches Nebula Creative branding

## Customization

The viewer uses CSS custom properties for easy theming. Key colors:
- Primary: `#4ecdc4` (teal)
- Secondary: `#ff6b6b` (coral)
- Background: Dark gradient
EOF

# Create deployment instructions
echo "🚀 Creating deployment instructions..."
cat > "$OUTPUT_DIR/DEPLOYMENT.md" << 'EOF'
# Deployment Instructions

## For GitHub Pages (Recommended)

1. **Copy files to your website repository**:
   ```bash
   cp -r cuetocue-web-viewer/* /path/to/your/website/cuetocue/
   ```

2. **Update your website's navigation** to include a link to `/cuetocue/`

3. **Commit and push**:
   ```bash
   git add .
   git commit -m "Add Cue to Cue web viewer"
   git push origin main
   ```

## For Other Web Servers

1. Upload the contents of `cuetocue-web-viewer/` to your web server
2. Ensure the files are accessible at `https://nebulacreative.org/cuetocue/`
3. Update your website's navigation to link to the viewer

## Data Updates

To update the cue data:

1. Export fresh data from your Cue to Cue app
2. Replace `cuetocue-data.json` with the new data
3. Redeploy the files

## Testing

Test the deployment by:
1. Opening `https://nebulacreative.org/cuetocue/` in a browser
2. Verifying the cue data displays correctly
3. Checking that the clocks update properly
4. Testing on mobile devices
EOF

echo ""
echo "✅ Deployment package created in: $OUTPUT_DIR"
echo ""
echo "📋 Next steps:"
echo "1. Review the files in $OUTPUT_DIR"
echo "2. Update cuetocue-data.json with your actual show data"
echo "3. Follow DEPLOYMENT.md instructions to deploy"
echo "4. Test the live site at https://nebulacreative.org/cuetocue/"
echo ""
echo "🎭 Your Cue to Cue web viewer is ready!"

