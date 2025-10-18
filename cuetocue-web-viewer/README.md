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
