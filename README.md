# Nebula Creative - Showtime Website

A theatrical landing page for Nebula Creative with interactive elements, stage lighting effects, and mobile-responsive design.

## 🚀 Live Site

- **URL**: https://nebulacreative.org
- **Repository**: https://github.com/corbinhand1/corbinhand1.github.io
- **Deployment**: GitHub Pages + Cloudflare

## 📱 Mobile-First Design

This site is built with mobile-first principles and includes:

- Responsive design that works on all screen sizes
- Touch-friendly buttons (44px minimum)
- Optimized Stage Manager panel for mobile
- Single sticky note on mobile devices
- Cache busting to ensure updates are visible

## 🛠️ Development

### Prerequisites

- Node.js 16+
- npm or yarn

### Setup

```bash
# Clone the repository
git clone https://github.com/corbinhand1/corbinhand1.github.io.git
cd corbinhand1.github.io

# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build
```

### Project Structure

```
├── src/
│   ├── components/
│   │   └── NebulaShowtime.tsx    # Main interactive component
│   ├── App.tsx                   # Root component
│   ├── main.tsx                  # Entry point
│   └── styles.css                # Global styles
├── assets/
│   ├── mobile-baseline.css       # Mobile-first CSS baseline
│   ├── index-*.js                # Built JavaScript bundles
│   ├── index-*.css               # Built CSS bundles
│   └── *.png                     # Logo and image assets
├── index.html                    # Main HTML file
├── CNAME                         # Custom domain configuration
└── .github/workflows/
    └── bust-cache.yml            # Cache busting workflow
```

## 🚀 Deployment

### GitHub Pages Setup

1. **Repository Settings**:
   - Go to Settings → Pages
   - Source: Deploy from a branch
   - Branch: `main`
   - Folder: `/ (root)`

2. **Custom Domain**:
   - Ensure `CNAME` file contains exactly: `nebulacreative.org`
   - Enable "Enforce HTTPS"

3. **Automatic Deployment**:
   - The GitHub Action automatically deploys on push to `main`
   - Cache busting is handled automatically

### Manual Deployment

```bash
# Build the project
npm run build

# Copy built files to root
cp dist/index.html .
cp -r dist/assets/* assets/

# Commit and push
git add .
git commit -m "feat: deploy latest changes"
git push origin main
```

## ☁️ Cloudflare Configuration

### SSL/TLS Settings
- **Encryption Mode**: Full (strict)
- **Always Use HTTPS**: On
- **HTTP Strict Transport Security (HSTS)**: On

### Performance Settings
- **Rocket Loader**: Off (can interfere with React)
- **Auto Minify**: Off during debugging
- **Brotli Compression**: On

### Caching Rules

#### HTML Files (No Cache)
- **URL Pattern**: `nebulacreative.org/*.html`
- **Cache Level**: Bypass Cache
- **Edge TTL**: 0 seconds
- **Browser TTL**: 0 seconds

#### Assets (Aggressive Cache)
- **URL Pattern**: `nebulacreative.org/assets/*`
- **Cache Level**: Cache Everything
- **Edge TTL**: 1 month
- **Browser TTL**: 1 week

#### Query String Handling
- **Query Strings**: Respect Query Strings
- This ensures cache busting works properly

### Page Rules (Alternative to Caching Rules)

If using Page Rules instead of Caching Rules:

1. **HTML Files**:
   - URL: `nebulacreative.org/*`
   - Settings: Cache Level = Bypass

2. **Assets**:
   - URL: `nebulacreative.org/assets/*`
   - Settings: Cache Level = Cache Everything, Edge TTL = 1 month

## 🔧 Cache Busting & Service Worker

The site uses automatic cache busting and intelligent service worker caching:

### Cache Busting

1. **GitHub Action** runs on every push to `main`
2. **Generates timestamp** version (e.g., `20241003-2150`)
3. **Updates HTML** with new version query strings
4. **Updates Service Worker** cache version
5. **Commits changes** automatically
6. **Deploys** to GitHub Pages

### Service Worker

The site includes a service worker for:
- **Intelligent caching** of static assets
- **Offline fallback** for navigation requests
- **Automatic cache updates** when new versions deploy
- **Performance optimization** for repeat visits

The service worker automatically:
- Caches static assets on first visit
- Serves cached content for faster loading
- Updates cache when new versions are deployed
- Cleans up old cache versions

### Manual Cache Busting

If you need to manually bust cache:

```bash
# Update version in index.html
sed -i 's/v=[0-9]\{8\}-[0-9]\{4\}/v=20241003-2150/g' index.html

# Commit and push
git add index.html
git commit -m "chore: manual cache bust"
git push
```

## 📱 Mobile QA Checklist

Before deploying, test on mobile:

### ✅ Viewport & Meta Tags
- [ ] Viewport meta tag present: `width=device-width, initial-scale=1, viewport-fit=cover`
- [ ] No horizontal scroll at 375px viewport width
- [ ] Content scales properly on different screen sizes
- [ ] Safe area insets respected on modern devices (iPhone X+)

### ✅ Touch Interactions
- [ ] Buttons are at least 44px tall
- [ ] Touch targets don't overlap
- [ ] Confetti button works on mobile
- [ ] Contact button appears after confetti
- [ ] All interactive elements are accessible

### ✅ Content Visibility
- [ ] Logo is fully visible and not blocked
- [ ] Stage Manager panel is compact and positioned correctly
- [ ] Only one sticky note shows on mobile
- [ ] Text is readable without zooming
- [ ] No content cut off by device notches/safe areas

### ✅ Performance
- [ ] Page loads quickly on mobile
- [ ] Images scale properly
- [ ] No layout shifts during load
- [ ] Animations are smooth
- [ ] Service worker caching works

### ✅ Cache Testing
- [ ] Open site in incognito mode
- [ ] Check Network tab shows versioned CSS/JS
- [ ] Verify changes appear after deployment
- [ ] Test cache busting works
- [ ] Service worker updates properly

### ✅ Device Testing
- [ ] iPhone (Safari)
- [ ] Android (Chrome)
- [ ] iPad (Safari)
- [ ] Various screen sizes (375px, 414px, 768px, 1024px)

## 🐛 Troubleshooting

### Changes Not Appearing

1. **Check cache busting**:
   ```bash
   # Verify version in HTML
   grep "v=" index.html
   ```

2. **Clear Cloudflare cache**:
   - Go to Cloudflare Dashboard
   - Caching → Purge Everything

3. **Test in incognito**:
   - Open site in private browsing
   - Check if changes appear

### Mobile Issues

1. **Viewport problems**:
   - Ensure viewport meta tag is correct
   - Check for fixed widths in CSS

2. **Touch issues**:
   - Verify button sizes are 44px+
   - Check z-index values

3. **Layout problems**:
   - Test on actual devices
   - Use browser dev tools mobile simulation

### Deployment Issues

1. **GitHub Pages not updating**:
   - Check Actions tab for failed workflows
   - Verify branch is set to `main`
   - Ensure CNAME file is correct

2. **Custom domain issues**:
   - Verify DNS settings
   - Check Cloudflare proxy status
   - Ensure SSL certificate is valid

## 📞 Support

For issues or questions:
- **Email**: corbin@nebulacreative.org
- **Repository**: https://github.com/corbinhand1/corbinhand1.github.io

## 📄 License

This project is proprietary to Nebula Creative.
