// Offline Data Manager for Cue to Cue
// This class manages offline data storage and retrieval

class OfflineDataManager {
    constructor() {
        this.dbName = 'CueToCueOffline';
        this.version = 1;
        this.db = null;
        this.isInitialized = false;
    }
    
    // Initialize the offline database
    async initDB() {
        if (this.isInitialized) return;
        
        try {
            return new Promise((resolve, reject) => {
                const request = indexedDB.open(this.dbName, this.version);
                
                request.onerror = () => {
                    console.warn('Offline database initialization failed:', request.error);
                    reject(request.error);
                };
                
                request.onsuccess = () => {
                    this.db = request.result;
                    this.isInitialized = true;
                    console.log('Offline database initialized successfully');
                    resolve();
                };
                
                request.onupgradeneeded = (event) => {
                    const db = event.target.result;
                    console.log('Setting up offline database schema...');
                    
                    // Store cue stacks
                    if (!db.objectStoreNames.contains('cueStacks')) {
                        const cueStore = db.createObjectStore('cueStacks', { keyPath: 'id' });
                        cueStore.createIndex('name', 'name', { unique: false });
                        cueStore.createIndex('timestamp', 'timestamp', { unique: false });
                    }
                    
                    // Store highlight colors
                    if (!db.objectStoreNames.contains('highlightColors')) {
                        db.createObjectStore('highlightColors', { keyPath: 'id' });
                    }
                    
                    // Store connection status
                    if (!db.objectStoreNames.contains('connectionStatus')) {
                        db.createObjectStore('connectionStatus', { keyPath: 'id' });
                    }
                    
                    // Store offline changes
                    if (!db.objectStoreNames.contains('offlineChanges')) {
                        const changeStore = db.createObjectStore('offlineChanges', { keyPath: 'id', autoIncrement: true });
                        changeStore.createIndex('timestamp', 'timestamp', { unique: false });
                        changeStore.createIndex('type', 'type', { unique: false });
                    }
                };
            });
        } catch (error) {
            console.warn('Offline database not available:', error);
            // Don't fail the app - offline mode is optional
            this.isInitialized = false;
        }
    }
    
    // Save cue stacks to offline storage
    async saveCueStacks(cueStacks) {
        if (!this.isInitialized) return;
        
        try {
            const transaction = this.db.transaction(['cueStacks'], 'readwrite');
            const store = transaction.objectStore('cueStacks');
            
            for (const stack of cueStacks) {
                await store.put({
                    id: stack.id,
                    data: stack,
                    timestamp: Date.now(),
                    version: stack.version || 1
                });
            }
            
            console.log('Cue stacks saved to offline storage');
        } catch (error) {
            console.warn('Failed to save cue stacks offline:', error);
        }
    }
    
    // Retrieve cue stacks from offline storage
    async getCueStacks() {
        if (!this.isInitialized) return [];
        
        try {
            const transaction = this.db.transaction(['cueStacks'], 'readonly');
            const store = transaction.objectStore('cueStacks');
            const request = store.getAll();
            
            return new Promise((resolve, reject) => {
                request.onsuccess = () => {
                    const stacks = request.result
                        .sort((a, b) => b.timestamp - a.timestamp)
                        .map(item => item.data);
                    resolve(stacks);
                };
                request.onerror = () => reject(request.error);
            });
        } catch (error) {
            console.warn('Failed to retrieve offline cue stacks:', error);
            return [];
        }
    }
    
    // Save highlight colors to offline storage
    async saveHighlightColors(highlightColors) {
        if (!this.isInitialized) return;
        
        try {
            const transaction = this.db.transaction(['highlightColors'], 'readwrite');
            const store = transaction.objectStore('highlightColors');
            
            // Clear existing colors
            await store.clear();
            
            // Save new colors
            for (const color of highlightColors) {
                await store.put({
                    id: color.id,
                    data: color,
                    timestamp: Date.now()
                });
            }
            
            console.log('Highlight colors saved to offline storage');
        } catch (error) {
            console.warn('Failed to save highlight colors offline:', error);
        }
    }
    
    // Retrieve highlight colors from offline storage
    async getHighlightColors() {
        if (!this.isInitialized) return [];
        
        try {
            const transaction = this.db.transaction(['highlightColors'], 'readonly');
            const store = transaction.objectStore('highlightColors');
            const request = store.getAll();
            
            return new Promise((resolve, reject) => {
                request.onsuccess = () => {
                    const colors = request.result
                        .sort((a, b) => b.timestamp - a.timestamp)
                        .map(item => item.data);
                    resolve(colors);
                };
                request.onerror = () => reject(request.error);
            });
        } catch (error) {
            console.warn('Failed to retrieve offline highlight colors:', error);
            return [];
        }
    }
    
    // Store offline changes for later sync
    async storeOfflineChange(change) {
        if (!this.isInitialized) return;
        
        try {
            const transaction = this.db.transaction(['offlineChanges'], 'readwrite');
            const store = transaction.objectStore('offlineChanges');
            
            await store.add({
                type: change.type,
                data: change.data,
                timestamp: Date.now(),
                description: change.description || 'Offline change'
            });
            
            console.log('Offline change stored:', change.type);
        } catch (error) {
            console.warn('Failed to store offline change:', error);
        }
    }
    
    // Get all pending offline changes
    async getOfflineChanges() {
        if (!this.isInitialized) return [];
        
        try {
            const transaction = this.db.transaction(['offlineChanges'], 'readonly');
            const store = transaction.objectStore('offlineChanges');
            const request = store.getAll();
            
            return new Promise((resolve, reject) => {
                request.onsuccess = () => {
                    const changes = request.result
                        .sort((a, b) => a.timestamp - b.timestamp);
                    resolve(changes);
                };
                request.onerror = () => reject(request.error);
            });
        } catch (error) {
            console.warn('Failed to retrieve offline changes:', error);
            return [];
        }
    }
    
    // Clear offline changes after successful sync
    async clearOfflineChanges() {
        if (!this.isInitialized) return;
        
        try {
            const transaction = this.db.transaction(['offlineChanges'], 'readwrite');
            const store = transaction.objectStore('offlineChanges');
            await store.clear();
            console.log('Offline changes cleared after sync');
        } catch (error) {
            console.warn('Failed to clear offline changes:', error);
        }
    }
    
    // Check if offline storage is available
    isAvailable() {
        return this.isInitialized && this.db !== null;
    }
    
    // Get storage usage information
    async getStorageInfo() {
        if (!this.isAvailable()) return null;
        
        try {
            const cueStacks = await this.getCueStacks();
            const highlightColors = await this.getHighlightColors();
            const offlineChanges = await this.getOfflineChanges();
            
            return {
                cueStacksCount: cueStacks.length,
                highlightColorsCount: highlightColors.length,
                offlineChangesCount: offlineChanges.length,
                lastUpdated: cueStacks.length > 0 ? Math.max(...cueStacks.map(s => s.timestamp || 0)) : null
            };
        } catch (error) {
            console.warn('Failed to get storage info:', error);
            return null;
        }
    }
}
