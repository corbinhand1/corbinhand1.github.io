// API endpoint for receiving cue data from macOS Cue to Cue app
// This should be added to your Nebula Creative website

// POST /api/cue-data
// Receives cue data from macOS app and stores it for web viewing

const express = require('express');
const fs = require('fs').promises;
const path = require('path');

const app = express();
app.use(express.json({ limit: '10mb' })); // Allow large cue data

// Store cue data
const CUEDATA_FILE = path.join(__dirname, 'public', 'cuetocue', 'cuetocue-data.json');
const METADATA_FILE = path.join(__dirname, 'public', 'cuetocue', 'metadata.json');

// Ensure cuetocue directory exists
async function ensureDirectoryExists() {
    const cuetocueDir = path.dirname(CUEDATA_FILE);
    try {
        await fs.mkdir(cuetocueDir, { recursive: true });
    } catch (error) {
        console.error('Error creating cuetocue directory:', error);
    }
}

// API endpoint to receive cue data from macOS app
app.post('/api/cue-data', async (req, res) => {
    try {
        const cueData = req.body;
        
        // Validate required fields
        if (!cueData.cueStackName || !cueData.cues || !cueData.columns) {
            return res.status(400).json({ 
                error: 'Missing required fields: cueStackName, cues, columns' 
            });
        }
        
        // Add metadata
        const metadata = {
            filename: cueData.filename || 'Unknown File',
            lastUpdated: new Date().toISOString(),
            cueStackName: cueData.cueStackName,
            cueCount: cueData.cues.length,
            columnCount: cueData.columns.length,
            source: 'macOS Cue to Cue App'
        };
        
        // Ensure directory exists
        await ensureDirectoryExists();
        
        // Save cue data
        await fs.writeFile(CUEDATA_FILE, JSON.stringify(cueData, null, 2));
        
        // Save metadata
        await fs.writeFile(METADATA_FILE, JSON.stringify(metadata, null, 2));
        
        console.log(`Cue data updated: ${metadata.filename} (${metadata.cueCount} cues)`);
        
        res.json({ 
            success: true, 
            message: 'Cue data saved successfully',
            metadata: metadata
        });
        
    } catch (error) {
        console.error('Error saving cue data:', error);
        res.status(500).json({ 
            error: 'Failed to save cue data',
            details: error.message 
        });
    }
});

// API endpoint to get cue data metadata
app.get('/api/cue-data/metadata', async (req, res) => {
    try {
        const metadata = await fs.readFile(METADATA_FILE, 'utf8');
        res.json(JSON.parse(metadata));
    } catch (error) {
        res.status(404).json({ 
            error: 'No cue data available',
            details: 'No cue data has been synced yet'
        });
    }
});

// API endpoint to get cue data
app.get('/api/cue-data', async (req, res) => {
    try {
        const cueData = await fs.readFile(CUEDATA_FILE, 'utf8');
        res.json(JSON.parse(cueData));
    } catch (error) {
        res.status(404).json({ 
            error: 'No cue data available',
            details: 'No cue data has been synced yet'
        });
    }
});

module.exports = app;


