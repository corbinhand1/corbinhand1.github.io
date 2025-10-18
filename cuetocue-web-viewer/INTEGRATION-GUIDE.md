# Cue to Cue Integration Guide for Nebula Creative Website

## Overview

This guide will help you integrate the Cue to Cue web viewer into your existing Nebula Creative website hosted on GitHub Pages.

## Current Website Structure

Based on your repository at `https://github.com/corbinhand1/corbinhand1.github.io`, your website uses:
- **Framework**: Vite + TypeScript
- **Hosting**: GitHub Pages
- **Domain**: nebulacreative.org
- **Build System**: npm/yarn with Vite

## Integration Steps

### 1. Add Cue to Cue Files to Your Repository

```bash
# Navigate to your website repository
cd /path/to/your/website/repository

# Create cuetocue directory
mkdir -p cuetocue

# Copy the viewer files
cp /path/to/cuetocue-web-viewer/* cuetocue/
```

### 2. Update Your Website Navigation

Add a link to the Cue to Cue viewer in your main navigation. In your `src/App.tsx` or main component:

```tsx
// Add to your navigation menu
<nav>
  <a href="/cuetocue/">Cue to Cue</a>
  {/* other nav items */}
</nav>
```

### 3. Update Your Vite Configuration

In your `vite.config.ts`, ensure static files are properly handled:

```typescript
import { defineConfig } from 'vite'

export default defineConfig({
  // ... existing config
  build: {
    // Ensure static assets are copied
    assetsDir: 'assets',
    rollupOptions: {
      output: {
        // Handle static files
        assetFileNames: (assetInfo) => {
          if (assetInfo.name?.endsWith('.json')) {
            return 'assets/[name].[hash][extname]'
          }
          return 'assets/[name].[hash][extname]'
        }
      }
    }
  },
  // ... rest of config
})
```

### 4. Update Your Build Process

Add a build step to copy the Cue to Cue files. In your `package.json`:

```json
{
  "scripts": {
    "build": "vite build && cp -r cuetocue dist/cuetocue",
    "preview": "vite preview"
  }
}
```

### 5. GitHub Pages Configuration

Ensure your GitHub Pages is configured to serve from the `dist` directory:

1. Go to your repository Settings
2. Navigate to Pages
3. Source: Deploy from a branch
4. Branch: `main` (or your deployment branch)
5. Folder: `/dist`

### 6. Custom Domain Configuration

Since you're using `nebulacreative.org`, ensure your `CNAME` file contains:

```
nebulacreative.org
```

## File Structure After Integration

```
your-website-repo/
├── src/
│   ├── components/
│   ├── App.tsx
│   └── ...
├── cuetocue/
│   ├── index.html
│   ├── cuetocue-data.json
│   ├── README.md
│   └── DEPLOYMENT.md
├── dist/ (after build)
│   ├── index.html
│   ├── assets/
│   └── cuetocue/
│       ├── index.html
│       └── cuetocue-data.json
├── vite.config.ts
├── package.json
└── CNAME
```

## Deployment Workflow

### Automatic Deployment (Recommended)

1. **Commit your changes**:
   ```bash
   git add .
   git commit -m "Add Cue to Cue web viewer"
   git push origin main
   ```

2. **GitHub Actions will automatically build and deploy**

### Manual Deployment

If you prefer manual deployment:

```bash
# Build the project
npm run build

# The cuetocue files will be copied to dist/cuetocue/
# Commit and push the dist directory
git add dist/
git commit -m "Deploy Cue to Cue viewer"
git push origin main
```

## Testing the Integration

1. **Local Testing**:
   ```bash
   npm run build
   npm run preview
   # Visit http://localhost:4173/cuetocue/
   ```

2. **Live Testing**:
   - Visit `https://nebulacreative.org/cuetocue/`
   - Verify the viewer loads correctly
   - Check that the cue data displays properly
   - Test on mobile devices

## Updating Cue Data

To update the cue data with your actual show information:

1. **Export from your Cue to Cue app**:
   ```bash
   swift export-cuetocue-data.swift /path/to/your/show.cuetocue > cuetocue/cuetocue-data.json
   ```

2. **Commit and push**:
   ```bash
   git add cuetocue/cuetocue-data.json
   git commit -m "Update cue data"
   git push origin main
   ```

## Troubleshooting

### Common Issues

1. **404 Error on `/cuetocue/`**:
   - Ensure the `cuetocue` directory is in your repository root
   - Check that the build process copies the files to `dist/cuetocue/`

2. **JSON Data Not Loading**:
   - Verify `cuetocue-data.json` is accessible at `/cuetocue/cuetocue-data.json`
   - Check browser console for CORS or loading errors

3. **Styling Issues**:
   - The viewer uses self-contained CSS, so it shouldn't conflict with your main site
   - If needed, you can customize the CSS in `cuetocue/index.html`

### GitHub Pages Cache Issues

If changes don't appear immediately:

1. **Purge Cloudflare cache** (if using Cloudflare)
2. **Wait 5-10 minutes** for GitHub Pages to update
3. **Test in incognito mode** to bypass browser cache

## Security Considerations

- ✅ **Read-only access**: No editing capabilities
- ✅ **No authentication required**: Simple viewing only
- ✅ **Static data**: No server-side processing
- ✅ **CORS-friendly**: Works with GitHub Pages

## Next Steps

1. **Test the integration** locally
2. **Deploy to your live site**
3. **Update with your actual cue data**
4. **Add navigation link** to your main site
5. **Test on various devices**

## Support

If you encounter any issues:
- Check the browser console for errors
- Verify file paths and permissions
- Test with the sample data first
- Review the GitHub Pages deployment logs



