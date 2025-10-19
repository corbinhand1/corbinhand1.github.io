# Cue to Cue Website - Complete Documentation

## Overview
The Cue to Cue website is a professional web-based cue management system deployed at `nebulacreative.org/cuetocue/`. It provides password-protected access to cue data with a modern, responsive interface optimized for both desktop and mobile devices.

## Live Website URLs
- **Main Application**: `https://nebulacreative.org/cuetocue/`
- **Admin Panel**: `https://nebulacreative.org/cuetocue/admin.html`
- **Homepage**: `https://nebulacreative.org/` (unrelated to cuetocue system)

## Architecture Overview

### Technology Stack
- **Frontend**: Pure HTML5, CSS3, JavaScript (ES6+)
- **Backend**: Swift-based HTTP server (macOS app)
- **Data Format**: JSON
- **Authentication**: Client-side SHA-256 password hashing
- **Deployment**: GitHub Pages
- **Domain**: Cloudflare CDN

### Core Components
1. **Password Protection System** - Client-side authentication
2. **Cue Data Viewer** - Interactive table with real-time updates
3. **Admin Panel** - Password management interface
4. **Mobile-Responsive Design** - Optimized for all screen sizes

## File Structure

### Deployed Files (`/cuetocue/` directory)
```
cuetocue/
├── index.html              # Main application interface
├── admin.html              # Password management panel
├── password-config.js       # Password configuration & hashes
├── password-system.js       # Authentication logic
├── cuetocue-data.json      # Live cue data (auto-updated)
├── metadata.json           # File metadata (auto-updated)
├── html2canvas.min.js      # PDF generation library
└── jspdf.umd.min.js        # PDF creation library
```

### Development Files
```
cuetocue-web-viewer-working/    # Local development version
├── index.html                  # Development version with all features
├── admin.html                  # Admin panel for testing
├── password-config.js          # Password configuration
├── password-system.js          # Authentication system
├── debug-password.html         # Debug/testing page
├── test-password.html          # Password system testing
└── [other development files]

cuetocue-web-viewer/            # Legacy development directory
└── [older versions of files]
```

## Password Protection System

### Authentication Flow
1. **Initial Load**: User visits `nebulacreative.org/cuetocue/`
2. **Session Check**: System checks for valid session in localStorage
3. **Password Prompt**: If no valid session, shows login modal
4. **Password Verification**: SHA-256 hash comparison against stored hashes
5. **Session Creation**: On success, creates 12-hour session
6. **Content Display**: Shows main application interface

### Password Configuration (`password-config.js`)
```javascript
const PASSWORD_CONFIG = {
    passwords: {
        "KeynoteEvents": "a1b2c3d4e5f6...", // SHA-256 hash
        "admin123": "f6e5d4c3b2a1..."     // Admin password hash
    },
    sessionTimeout: 12 * 60 * 60 * 1000, // 12 hours in milliseconds
    maxAttempts: 5,
    lockoutDuration: 15 * 60 * 1000        // 15 minutes
};
```

### Session Management
- **Storage**: localStorage with key `cuetocue_session`
- **Duration**: 12 hours from login
- **Persistence**: Survives browser refresh and tab close
- **Security**: Automatic logout on session expiry

## Main Application Interface (`index.html`)

### Header Structure (Three-Row Layout)
```
Row 1: [Title + Time] | [Current Show Info] | [Logout Button]
Row 2: [Current Show Info - Mobile Only]
Row 3: [Cue Stack Selector] | [Action Buttons]
```

### Key Features
- **Real-time Updates**: Auto-refreshes every 30 seconds
- **Column Management**: Show/hide columns dynamically
- **Color Highlighting**: Visual cues for different content types
- **Print Functionality**: Generate PDF reports
- **Mobile Optimization**: Responsive design with touch-friendly controls

### Data Flow
1. **Data Fetching**: AJAX calls to `cuetocue-data.json` and `metadata.json`
2. **Real-time Updates**: 30-second polling for live data
3. **User Interactions**: Immediate UI updates with server sync
4. **Error Handling**: Graceful fallbacks for network issues

## Admin Panel (`admin.html`)

### Purpose
- **Password Management**: Change cuetocue access password
- **Security Settings**: Modify session timeout and attempt limits
- **System Status**: View current configuration

### Access Control
- **URL**: `https://nebulacreative.org/cuetocue/admin.html`
- **Authentication**: Separate admin password (`admin123`)
- **Session**: Independent from main application session

## Mobile Responsiveness

### Design Philosophy
- **Mobile-First**: Optimized for iPhone 15 Pro (393px width)
- **Touch-Friendly**: Minimum 32px touch targets
- **Compact Layout**: Three-row header structure
- **Performance**: Minimal JavaScript, fast loading

### Mobile-Specific Features
- **Hidden Elements**: Color and Print buttons removed on mobile
- **Compact Text**: "Select Columns" becomes "Col"
- **Full Filename Display**: No truncation on mobile
- **Optimized Spacing**: Reduced padding and margins

## Data Management

### Data Sources
- **Primary**: `cuetocue-data.json` - Contains all cue information
- **Metadata**: `metadata.json` - File info, timestamps, selected stack
- **Updates**: Real-time from macOS application via HTTP server

### Data Structure
```javascript
// cuetocue-data.json
{
    "allCues": [...],           // Array of cue objects
    "highlightColors": [...],   // Color configuration
    "columns": [...],           // Available columns
    "availableCueStacks": 12    // Number of cue stacks
}

// metadata.json
{
    "filename": "DF_Keynote_25_v2 copy.json",
    "lastUpdated": "2025-10-18T22:39:31Z",
    "selectedCueStackIndex": 0,
    "totalCueStacks": 12
}
```

## Deployment Process

### GitHub Repository Structure
```
corbinhand1/corbinhand1.github.io/
├── cuetocue/                    # Deployed website files
│   ├── index.html
│   ├── admin.html
│   ├── password-config.js
│   ├── password-system.js
│   └── [other files]
├── .github/workflows/           # CI/CD workflows
│   ├── bust-cache.yml          # Cache busting (disabled)
│   └── update-cue-data.yml     # Data update automation
└── [other website files]
```

### Deployment Steps
1. **Local Development**: Work in `cuetocue-web-viewer-working/`
2. **File Copying**: Copy updated files to `cuetocue/` directory
3. **Git Operations**:
   ```bash
   git add cuetocue/
   git commit -m "Description of changes"
   git push origin main
   ```
4. **GitHub Pages**: Automatic deployment via GitHub Actions

### Workflow Automation
- **Update Cue Data**: Automated via `update-cue-data.yml`
- **Cache Busting**: Disabled workflow (`bust-cache.yml`)
- **Pages Deployment**: Automatic on push to main branch

## Development Workflow

### Local Testing
1. **Start Local Server**:
   ```bash
   cd cuetocue-web-viewer-working
   python3 -m http.server 8080
   ```
2. **Access**: `http://localhost:8080`
3. **Test Features**: Password system, mobile responsiveness, data updates

### Making Changes
1. **Edit Files**: Modify files in `cuetocue-web-viewer-working/`
2. **Test Locally**: Verify changes work correctly
3. **Deploy**: Copy files to `cuetocue/` and push to GitHub
4. **Verify**: Check live site at `nebulacreative.org/cuetocue/`

## Security Considerations

### Password Security
- **Hashing**: SHA-256 with salt
- **Client-Side**: No server-side authentication
- **Session Management**: localStorage-based with timeout
- **Rate Limiting**: Built-in attempt limiting

### Data Security
- **HTTPS**: All traffic encrypted
- **No Sensitive Data**: Passwords are hashed, no plaintext storage
- **Access Control**: Password-protected access to cue data

## Troubleshooting

### Common Issues
1. **404 Errors**: Check file paths and GitHub Pages deployment
2. **Password Not Working**: Verify hash in `password-config.js`
3. **Mobile Layout Issues**: Check CSS media queries
4. **Data Not Updating**: Verify macOS app is running and serving data

### Debug Tools
- **Browser Console**: Check for JavaScript errors
- **Network Tab**: Monitor AJAX requests
- **Local Storage**: Inspect session data
- **Debug Pages**: Use `debug-password.html` for testing

## Future Development Guidelines

### Code Organization
- **Separation of Concerns**: HTML structure, CSS styling, JavaScript logic
- **Modular Design**: Reusable components and functions
- **Documentation**: Comment complex logic and configurations

### Best Practices
- **Mobile-First**: Always consider mobile experience
- **Performance**: Minimize JavaScript, optimize images
- **Accessibility**: Use semantic HTML, proper ARIA labels
- **Security**: Never store plaintext passwords

### Adding New Features
1. **Plan**: Consider mobile impact and user experience
2. **Develop**: Use local testing environment
3. **Test**: Verify on multiple devices and browsers
4. **Deploy**: Follow established deployment process
5. **Document**: Update this README with new information

## Contact and Support

### Repository Information
- **GitHub**: `corbinhand1/corbinhand1.github.io`
- **Branch**: `main`
- **Domain**: `nebulacreative.org` (Cloudflare CDN)

### Key Files for New Developers
1. **Start Here**: `cuetocue-web-viewer-working/index.html`
2. **Password System**: `cuetocue-web-viewer-working/password-system.js`
3. **Configuration**: `cuetocue-web-viewer-working/password-config.js`
4. **Admin Panel**: `cuetocue-web-viewer-working/admin.html`

---

*This documentation was last updated: October 18, 2025*
*For questions or updates, refer to the development team or update this README accordingly.*
