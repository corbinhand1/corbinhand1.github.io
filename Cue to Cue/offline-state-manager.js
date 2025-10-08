// Offline State Manager for Cue to Cue
// This class manages the application state for offline functionality

class OfflineStateManager {
    constructor() {
        this.isInitialized = false;
        this.currentState = null;
        this.offlineMode = false;
        this.lastSyncTime = null;
        this.syncQueue = [];
        this.stateChangeCallbacks = [];
    }
    
    async init() {
        if (this.isInitialized) return;
        
        try {
            // Load any existing state from localStorage
            this.loadPersistedState();
            
            // Set up state change listeners
            this.setupStateListeners();
            
            // Check if we're starting in offline mode
            if (!navigator.onLine) {
                this.enableOfflineMode();
            }
            
            this.isInitialized = true;
            console.log('✅ Offline State Manager initialized');
            
        } catch (error) {
            console.warn('⚠️ Offline State Manager initialization failed:', error);
        }
    }
    
    loadPersistedState() {
        try {
            const persistedState = localStorage.getItem('cueToCueAppState');
            if (persistedState) {
                this.currentState = JSON.parse(persistedState);
                this.lastSyncTime = this.currentState.timestamp || Date.now();
                console.log('📱 Loaded persisted app state');
            }
        } catch (error) {
            console.warn('⚠️ Failed to load persisted state:', error);
        }
    }
    
    setupStateListeners() {
        // Listen for online/offline events
        window.addEventListener('online', () => this.handleOnline());
        window.addEventListener('offline', () => this.handleOffline());
        
        // Listen for page visibility changes
        document.addEventListener('visibilitychange', () => {
            if (!document.hidden && navigator.onLine) {
                this.syncState();
            }
        });
        
        // Listen for beforeunload to save state
        window.addEventListener('beforeunload', () => {
            this.saveCurrentState();
        });
    }
    
    handleOnline() {
        this.offlineMode = false;
        this.notifyStateChange('online');
        
        // Process any queued sync operations
        this.processSyncQueue();
        
        console.log('🌐 Back online - processing sync queue');
    }
    
    handleOffline() {
        this.offlineMode = true;
        this.notifyStateChange('offline');
        
        // Save current state before going offline
        this.saveCurrentState();
        
        console.log('📱 Gone offline - state saved');
    }
    
    saveCurrentState() {
        try {
            const state = this.captureCurrentState();
            this.currentState = state;
            
            // Save to localStorage
            localStorage.setItem('cueToCueAppState', JSON.stringify(state));
            
            // Save to IndexedDB if available
            this.saveToIndexedDB(state);
            
            console.log('💾 App state saved for offline use');
            
        } catch (error) {
            console.warn('⚠️ Failed to save app state:', error);
        }
    }
    
    captureCurrentState() {
        const state = {
            timestamp: Date.now(),
            url: window.location.href,
            userAgent: navigator.userAgent,
            viewport: {
                width: window.innerWidth,
                height: window.innerHeight
            }
        };
        
        // Try to capture cue data from various sources
        try {
            // Look for global cue data
            if (window.cueData) {
                state.cueData = window.cueData;
            }
            
            // Look for data in script tags
            const scriptTags = document.querySelectorAll('script[type="application/json"]');
            for (const script of scriptTags) {
                try {
                    const data = JSON.parse(script.textContent);
                    if (data.cueStacks || data.cues) {
                        state.scriptData = data;
                        break;
                    }
                } catch (e) {
                    // Ignore parsing errors
                }
            }
            
            // Look for data attributes
            const dataElements = document.querySelectorAll('[data-cue-data]');
            for (const element of dataElements) {
                try {
                    const data = JSON.parse(element.dataset.cueData);
                    if (data.cueStacks || data.cues) {
                        state.attributeData = data;
                        break;
                    }
                } catch (e) {
                    // Ignore parsing errors
                }
            }
            
            // Capture form data if any
            const forms = document.querySelectorAll('form');
            if (forms.length > 0) {
                state.formData = {};
                forms.forEach((form, index) => {
                    const formData = new FormData(form);
                    const formObject = {};
                    for (let [key, value] of formData.entries()) {
                        formObject[key] = value;
                    }
                    state.formData[`form_${index}`] = formObject;
                });
            }
            
        } catch (error) {
            console.warn('⚠️ Failed to capture complete app state:', error);
        }
        
        return state;
    }
    
    async saveToIndexedDB(state) {
        if (!('indexedDB' in window)) return;
        
        try {
            const dbName = 'CueToCueOffline';
            const request = indexedDB.open(dbName, 1);
            
            request.onupgradeneeded = function(event) {
                const db = event.target.result;
                
                // Create object store for app state
                if (!db.objectStoreNames.contains('appState')) {
                    const stateStore = db.createObjectStore('appState', { keyPath: 'id' });
                    stateStore.createIndex('timestamp', 'timestamp', { unique: false });
                }
            };
            
            request.onsuccess = function(event) {
                const db = event.target.result;
                const transaction = db.transaction(['appState'], 'readwrite');
                const store = transaction.objectStore('appState');
                
                store.put({
                    id: 'current',
                    data: state,
                    timestamp: Date.now()
                });
            };
            
        } catch (error) {
            console.warn('⚠️ Failed to save to IndexedDB:', error);
        }
    }
    
    async restoreState() {
        try {
            // Try to restore from IndexedDB first
            if ('indexedDB' in window) {
                const state = await this.loadFromIndexedDB();
                if (state) {
                    this.currentState = state;
                    return state;
                }
            }
            
            // Fallback to localStorage
            if (this.currentState) {
                return this.currentState;
            }
            
        } catch (error) {
            console.warn('⚠️ Failed to restore state:', error);
        }
        
        return null;
    }
    
    async loadFromIndexedDB() {
        if (!('indexedDB' in window)) return null;
        
        try {
            const dbName = 'CueToCueOffline';
            const request = indexedDB.open(dbName, 1);
            
            return new Promise((resolve, reject) => {
                request.onsuccess = function(event) {
                    const db = event.target.result;
                    
                    if (db.objectStoreNames.contains('appState')) {
                        const transaction = db.transaction(['appState'], 'readonly');
                        const store = transaction.objectStore('appState');
                        const getRequest = store.get('current');
                        
                        getRequest.onsuccess = function() {
                            if (getRequest.result) {
                                resolve(getRequest.result.data);
                            } else {
                                resolve(null);
                            }
                        };
                        
                        getRequest.onerror = function() {
                            reject(getRequest.error);
                        };
                    } else {
                        resolve(null);
                    }
                };
                
                request.onerror = function() {
                    reject(request.error);
                };
            });
            
        } catch (error) {
            console.warn('⚠️ Failed to load from IndexedDB:', error);
            return null;
        }
    }
    
    enableOfflineMode() {
        this.offlineMode = true;
        this.notifyStateChange('offline');
        
        // Save current state
        this.saveCurrentState();
        
        console.log('📱 Offline mode enabled');
    }
    
    disableOfflineMode() {
        this.offlineMode = false;
        this.notifyStateChange('online');
        
        // Sync any pending changes
        this.syncState();
        
        console.log('🌐 Offline mode disabled');
    }
    
    async syncState() {
        if (this.offlineMode || !navigator.onLine) {
            // Queue sync operation for when we're back online
            this.syncQueue.push({
                type: 'state_sync',
                timestamp: Date.now(),
                data: this.currentState
            });
            return;
        }
        
        try {
            // Try to sync with server
            const response = await fetch('/cues', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    action: 'sync',
                    state: this.currentState,
                    timestamp: this.lastSyncTime
                })
            });
            
            if (response.ok) {
                this.lastSyncTime = Date.now();
                console.log('✅ State synced with server');
            }
            
        } catch (error) {
            console.warn('⚠️ Failed to sync state:', error);
            
            // Queue for later sync
            this.syncQueue.push({
                type: 'state_sync',
                timestamp: Date.now(),
                data: this.currentState
            });
        }
    }
    
    async processSyncQueue() {
        if (this.syncQueue.length === 0) return;
        
        console.log(`🔄 Processing ${this.syncQueue.length} queued sync operations`);
        
        const queue = [...this.syncQueue];
        this.syncQueue = [];
        
        for (const operation of queue) {
            try {
                await this.processSyncOperation(operation);
            } catch (error) {
                console.warn('⚠️ Failed to process sync operation:', error);
                
                // Re-queue failed operations
                this.syncQueue.push(operation);
            }
        }
    }
    
    async processSyncOperation(operation) {
        switch (operation.type) {
            case 'state_sync':
                await this.syncState();
                break;
            default:
                console.warn('⚠️ Unknown sync operation type:', operation.type);
        }
    }
    
    addStateChangeListener(callback) {
        this.stateChangeCallbacks.push(callback);
    }
    
    removeStateChangeListener(callback) {
        const index = this.stateChangeCallbacks.indexOf(callback);
        if (index > -1) {
            this.stateChangeCallbacks.splice(index, 1);
        }
    }
    
    notifyStateChange(event) {
        this.stateChangeCallbacks.forEach(callback => {
            try {
                callback(event, this.currentState);
            } catch (error) {
                console.warn('⚠️ State change callback error:', error);
            }
        });
    }
    
    getCurrentState() {
        return this.currentState;
    }
    
    isOfflineMode() {
        return this.offlineMode;
    }
    
    getLastSyncTime() {
        return this.lastSyncTime;
    }
    
    getSyncQueueLength() {
        return this.syncQueue.length;
    }
    
    // Utility methods
    getStateAge() {
        if (!this.currentState || !this.currentState.timestamp) {
            return null;
        }
        
        const age = Date.now() - this.currentState.timestamp;
        const minutes = Math.floor(age / (1000 * 60));
        const hours = Math.floor(minutes / 60);
        const days = Math.floor(hours / 24);
        
        if (days > 0) {
            return `${days} day(s) ago`;
        } else if (hours > 0) {
            return `${hours} hour(s) ago`;
        } else if (minutes > 0) {
            return `${minutes} minute(s) ago`;
        } else {
            return 'Just now';
        }
    }
    
    isStateStale(maxAgeMinutes = 60) {
        if (!this.currentState || !this.currentState.timestamp) {
            return true;
        }
        
        const age = Date.now() - this.currentState.timestamp;
        return age > (maxAgeMinutes * 60 * 1000);
    }
    
    clearState() {
        this.currentState = null;
        this.lastSyncTime = null;
        this.syncQueue = [];
        
        // Clear from localStorage
        localStorage.removeItem('cueToCueAppState');
        
        // Clear from IndexedDB
        this.clearFromIndexedDB();
        
        console.log('🗑️ App state cleared');
    }
    
    async clearFromIndexedDB() {
        if (!('indexedDB' in window)) return;
        
        try {
            const dbName = 'CueToCueOffline';
            const request = indexedDB.open(dbName, 1);
            
            request.onsuccess = function(event) {
                const db = event.target.result;
                
                if (db.objectStoreNames.contains('appState')) {
                    const transaction = db.transaction(['appState'], 'readwrite');
                    const store = transaction.objectStore('appState');
                    store.clear();
                }
            };
            
        } catch (error) {
            console.warn('⚠️ Failed to clear from IndexedDB:', error);
        }
    }
}

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = OfflineStateManager;
}
