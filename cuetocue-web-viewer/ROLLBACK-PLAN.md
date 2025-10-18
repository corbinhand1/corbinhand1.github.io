# Cue to Cue Password Protection - Rollback Plan

## 🚨 EMERGENCY ROLLBACK (30 seconds)

If anything goes wrong, immediately restore the original system:

```bash
cd "/Users/corbinhand/Documents/Cue to Cue App/Cue to Cue Main Branch 1"
cp -r cuetocue-web-viewer-BACKUP-20251018-180734 cuetocue-web-viewer
```

## 📋 ROLLBACK CHECKLIST

### Before Rollback:
- [ ] Note any error messages
- [ ] Check browser console for JavaScript errors
- [ ] Verify which functionality is broken
- [ ] Test on different browsers/devices

### During Rollback:
- [ ] Stop any running web servers
- [ ] Copy backup files over current files
- [ ] Verify original files are restored
- [ ] Test that original functionality works

### After Rollback:
- [ ] Test main viewer loads correctly
- [ ] Test cue data displays properly
- [ ] Test mobile compatibility
- [ ] Verify all original features work

## 🔧 TROUBLESHOOTING GUIDE

### Common Issues & Solutions:

#### 1. Password Prompt Not Appearing
**Symptoms:** Page loads directly without password prompt
**Cause:** JavaScript error or missing files
**Solution:** 
- Check browser console for errors
- Verify password-config.js and password-system.js are present
- Check file permissions

#### 2. Password Not Working
**Symptoms:** Correct password rejected
**Cause:** Hash mismatch or encoding issue
**Solution:**
- Verify password is exactly "KeynoteEvents"
- Check browser console for hashing errors
- Test with admin panel

#### 3. Admin Panel Not Accessible
**Symptoms:** Cannot access admin.html
**Cause:** File not deployed or path issue
**Solution:**
- Verify admin.html is in the same directory
- Check URL is correct: `/admin.html`
- Verify file permissions

#### 4. Original Functionality Broken
**Symptoms:** Cue data not loading, clocks not working
**Cause:** JavaScript conflicts or initialization issues
**Solution:**
- Check browser console for errors
- Verify CueToCueViewer class is still intact
- Test with original backup files

## 📁 FILE STRUCTURE VERIFICATION

### Original Files (Backup):
```
cuetocue-web-viewer-BACKUP-20251018-180734/
├── index.html              # Original (700 lines)
├── cuetocue-data.json      # Original cue data
├── DEPLOYMENT.md           # Original deployment docs
├── INTEGRATION-GUIDE.md    # Original integration guide
└── README.md               # Original readme
```

### New Files (With Password Protection):
```
cuetocue-web-viewer/
├── index.html              # Modified (with password protection)
├── admin.html              # New (admin panel)
├── password-config.js      # New (password configuration)
├── password-system.js      # New (password system)
├── cuetocue-data.json      # Unchanged
├── DEPLOYMENT.md           # Unchanged
├── INTEGRATION-GUIDE.md    # Unchanged
└── README.md               # Unchanged
```

## 🔄 PARTIAL ROLLBACK OPTIONS

### Option 1: Remove Password Protection Only
If you want to keep the admin panel but remove password protection:

```bash
# Remove password system files
rm cuetocue-web-viewer/password-config.js
rm cuetocue-web-viewer/password-system.js

# Restore original index.html
cp cuetocue-web-viewer-BACKUP-20251018-180734/index.html cuetocue-web-viewer/index.html
```

### Option 2: Keep Password, Remove Admin
If you want to keep password protection but remove admin panel:

```bash
# Remove admin panel
rm cuetocue-web-viewer/admin.html
```

### Option 3: Reset Password Only
If you need to reset the password back to default:

1. Edit `password-config.js`
2. Change `viewerPassword` back to: `"2a142dddf2bfac0df9bf023dc939b4b9534e4588d3bfa36771c3281453d29338"`
3. Clear browser localStorage: `localStorage.clear()`

## 🚀 DEPLOYMENT VERIFICATION

### Pre-Deployment Checklist:
- [ ] All files present and correct
- [ ] Password protection working locally
- [ ] Admin panel accessible and functional
- [ ] Original functionality preserved
- [ ] Mobile compatibility tested
- [ ] Browser compatibility tested

### Post-Deployment Checklist:
- [ ] Main viewer loads with password prompt
- [ ] Password "KeynoteEvents" works
- [ ] Admin panel accessible at `/admin.html`
- [ ] Admin password "admin123" works
- [ ] Password change functionality works
- [ ] Original cue data displays correctly
- [ ] All original features work after login

## 📞 SUPPORT CONTACTS

If rollback doesn't work or you need help:

1. **Check browser console** for JavaScript errors
2. **Test with different browsers** (Chrome, Safari, Firefox)
3. **Clear browser cache** and try again
4. **Check file permissions** on web server
5. **Verify all files uploaded** correctly

## 🎯 SUCCESS CRITERIA

The password protection system is working correctly when:

- [ ] Password prompt appears on first visit
- [ ] "KeynoteEvents" password grants access
- [ ] Content loads normally after authentication
- [ ] Session persists for 2 hours
- [ ] Admin panel accessible at `/admin.html`
- [ ] Admin password "admin123" works
- [ ] Password can be changed through admin panel
- [ ] All original functionality preserved
- [ ] Mobile and desktop compatibility maintained

## 🔒 SECURITY NOTES

### Current Security Level:
- **Appropriate for:** Event privacy, casual access prevention
- **Not suitable for:** High-security applications, financial data
- **Protection level:** Basic but professional

### Password Management:
- **Default password:** KeynoteEvents
- **Admin password:** admin123
- **Session timeout:** 12 hours
- **Max attempts:** 5 before lockout
- **Lockout duration:** 15 minutes

Remember: This is client-side protection suitable for your use case of preventing casual access to event cue sheets.
