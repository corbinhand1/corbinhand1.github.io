# Development Guide - Nebula Creative Site

## 🚀 Quick Start

### Development (Live Reloading)
```bash
npm run dev
# Opens http://localhost:5173 with live reloading
# Uses /src/main.tsx and hot module replacement
```

### Production Build
```bash
npm run build:prod
# Creates optimized build in /dist folder
# Ready for GitHub Pages deployment
```

### Preview Production Build
```bash
npm run preview:prod
# Preview the production build locally
# Opens http://localhost:4173
```

## 📁 File Structure

### Development Files
- `src/` - Source code (React components, styles, config)
- `index.dev.html` - Development HTML template
- `vite.config.ts` - Vite configuration

### Production Files
- `index.html` - Production HTML (points to built assets)
- `dist/` - Built production files
- `assets/` - Static assets for GitHub Pages

## 🔧 Environment Configuration

### Development
- **Base Path**: `/` (root)
- **Entry Point**: `/src/main.tsx`
- **Hot Reload**: ✅ Enabled
- **Source Maps**: ✅ Enabled
- **Port**: 5173

### Production
- **Base Path**: `./` (relative for GitHub Pages)
- **Entry Point**: `./assets/index-[hash].js`
- **Optimization**: ✅ Minified, tree-shaken
- **Assets**: Hashed filenames for caching

## 🚨 Important Notes

### DO NOT EDIT THESE FILES
- `dist/` folder contents (auto-generated)
- `assets/` folder contents (auto-generated)
- Production `index.html` (use `index.dev.html` for dev)

### ALWAYS USE
- `npm run dev` for development
- `npm run build:prod` for production builds
- `npm run deploy` for GitHub Pages deployment

## 🐛 Troubleshooting

### Changes Not Appearing
1. Make sure you're using `npm run dev` (not opening `index.html` directly)
2. Check browser console for errors
3. Try `npm run fresh` to reset everything

### Build Issues
1. Run `npm run clean` to clear cache
2. Check `dist/` folder is generated correctly
3. Verify `index.html` points to correct asset files

### Port Conflicts
- Development: `npm run dev` (port 5173)
- Preview: `npm run preview:prod` (port 4173)
- If port 5173 is busy, Vite will auto-find next available port

## 📦 Deployment

### GitHub Pages
```bash
npm run deploy
# Builds production version and deploys to GitHub Pages
```

### Manual Deployment
```bash
npm run build:prod
# Copy contents of /dist to your web server
```

## 🎯 Development Workflow

1. **Start Development**: `npm run dev`
2. **Make Changes**: Edit files in `src/`
3. **Test Changes**: Browser auto-reloads
4. **Build Production**: `npm run build:prod`
5. **Preview Production**: `npm run preview:prod`
6. **Deploy**: `npm run deploy`
