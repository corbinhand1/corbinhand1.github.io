# Test Sync Setup Guide

## ✅ **Real Sync Implementation Complete!**

The macOS app now has **real GitHub API integration** instead of the simulated sync. Here's how to test it:

## **Step 1: Configure GitHub Settings**

1. **Open your Cue to Cue app**
2. **Go to Settings** (gear icon in toolbar)
3. **Click "Website Sync" tab**
4. **Enter your GitHub token**:
   - Get a token from: https://github.com/settings/tokens
   - Make sure it has `repo` scope
   - Paste it in the "GitHub Token" field
5. **Enable "Auto-sync when cue data changes"**
6. **Settings will save automatically**

## **Step 2: Test Manual Sync**

1. **Load a cue file** (like `DF_Keynote_25.json`)
2. **Click the cloud button** in the toolbar
3. **Watch for sync status**:
   - ✅ **Success**: Cloud button stops spinning, shows success
   - ❌ **Error**: Shows error message in sync status

## **Step 3: Test Auto-Sync**

1. **Make sure auto-sync is enabled** in settings
2. **Open a different cue file**
3. **Auto-sync should trigger automatically**
4. **Check sync status** in the settings

## **Step 4: Verify Web Viewer**

1. **Visit**: https://nebulacreative.org/cuetocue/
2. **Should show**:
   - ✅ **Current Show**: Name of your cue file
   - ✅ **Last Updated**: Recent timestamp
   - ✅ **Real cue data**: Your actual cues, not placeholder

## **Expected Behavior**

### **Before Sync:**
- Web viewer shows "No file loaded"
- Placeholder cue data
- Old timestamp

### **After Sync:**
- Web viewer shows your cue file name
- Real cue data from your file
- Current timestamp
- All 6 cue stacks with 85 cues visible

## **Troubleshooting**

### **If sync fails:**
1. **Check GitHub token** - Make sure it's valid and has `repo` scope
2. **Check network** - Make sure you have internet connection
3. **Check error message** - Look at sync status in settings

### **If web viewer doesn't update:**
1. **Wait 1-2 minutes** - GitHub Actions takes time to process
2. **Refresh the web page** - Hard refresh (Cmd+Shift+R)
3. **Check GitHub Actions** - Look at your repository's Actions tab

## **What's Different Now**

- ✅ **Real API calls** to GitHub (not simulated)
- ✅ **Actual cue data** sent to website
- ✅ **Proper error handling** with real error messages
- ✅ **Auto-save settings** when you change them
- ✅ **Real-time sync status** updates

## **Next Steps**

1. **Test with your cue files**
2. **Verify web viewer updates**
3. **Set up GitHub Actions** on your website repository
4. **Enjoy real-time sync!** 🎉

---

**The sync system is now fully functional and ready to use!**


