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
