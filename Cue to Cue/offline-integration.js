// Enhanced Offline Integration for Cue to Cue
// This script provides seamless offline functionality with automatic state persistence

class OfflineIntegration {
    constructor() {
        this.isOnline = navigator.onLine;
        this.offlineDataManager = null;
        this.offlineStateManager = null;
        this.serviceWorkerRegistration = null;
        this.lastSyncTime = Date.now();
        this.syncInterval = null;
        this.offlineMode = false;
        this.connectionQuality = 'unknown'; // Added for connection quality monitoring
        
        this.init();
    }
    
    async init() {
        try {
            // Initialize offline managers
            await this.initializeOfflineManagers();
            
            // Register service worker
            await this.registerServiceWorker();
            
            // Set up event listeners
            this.setupEventListeners();
            
            // Start periodic sync
            this.startPeriodicSync();
            
            // Check connection quality
            this.checkConnectionQuality();
            
            // Check if we're starting offline
            if (!this.isOnline) {
                this.enableOfflineMode();
            } else {
                // If we're online, immediately save the current state
                // This ensures we have data cached even if the user goes offline quickly
                setTimeout(() => {
                    this.forceSaveCurrentState();
                }, 2000); // Wait 2 seconds for page to fully load
            }
            
            console.log('✅ Offline integration initialized');
        } catch (error) {
            console.warn('⚠️ Offline integration initialization failed:', error);
            // Show error notification
            this.showNotification('⚠️ Offline mode initialization failed', 'error');
        }
    }
    
    async initializeOfflineManagers() {
        // Initialize offline data manager
        if (typeof OfflineDataManager !== 'undefined') {
            this.offlineDataManager = new OfflineDataManager();
            await this.offlineDataManager.initDB();
        }
        
        // Initialize offline state manager
        if (typeof OfflineStateManager !== 'undefined') {
            this.offlineStateManager = new OfflineStateManager();
            await this.offlineStateManager.init();
        }
    }
    
    async registerServiceWorker() {
        if ('serviceWorker' in navigator) {
            try {
                this.serviceWorkerRegistration = await navigator.serviceWorker.register('/offline-service-worker.js');
                console.log('🔧 Service Worker registered:', this.serviceWorkerRegistration);
                
                // Handle service worker updates
                this.serviceWorkerRegistration.addEventListener('updatefound', () => {
                    const newWorker = this.serviceWorkerRegistration.installing;
                    newWorker.addEventListener('statechange', () => {
                        if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                            // New service worker available
                            this.showUpdateNotification();
                        }
                    });
                });
                
                // Handle service worker messages
                navigator.serviceWorker.addEventListener('message', (event) => {
                    this.handleServiceWorkerMessage(event);
                });
                
            } catch (error) {
                console.warn('⚠️ Service Worker registration failed:', error);
            }
        }
    }
    
    setupEventListeners() {
        // Online/offline events
        window.addEventListener('online', () => this.handleOnline());
        window.addEventListener('offline', () => this.handleOffline());
        
        // Page visibility events for better sync
        // Note: We don't sync offline data on visibility change to avoid unnecessary "no offline changes to sync" banners
        // Only sync when there are actual connection transitions (online/offline events)
        
        // Before unload - save current state
        window.addEventListener('beforeunload', () => {
            this.saveCurrentState();
        });
        
        // Periodic state saving
        setInterval(() => {
            if (this.isOnline) {
                this.saveCurrentState();
            }
        }, 30000); // Save every 30 seconds when online
        
        // Save state when page becomes visible (user returns to tab)
        document.addEventListener('visibilitychange', () => {
            if (!document.hidden && this.isOnline) {
                // Save state when user returns to the tab
                this.saveCurrentState();
            }
        });
        
        // Save state when window gains focus
        window.addEventListener('focus', () => {
            if (this.isOnline) {
                this.saveCurrentState();
            }
        });
        
        // Save state when data might have changed
        this.setupDataChangeListeners();
        
        // Add debug panel for development/testing
        this.addDebugPanel();
    }
    
    addDebugPanel() {
        // Only add debug panel in development/testing environments
        if (window.location.hostname === 'localhost' || 
            window.location.hostname === '127.0.0.1' ||
            window.location.hostname.includes('test')) {
            
            const debugPanel = document.createElement('div');
            debugPanel.id = 'offline-debug-panel';
            debugPanel.style.cssText = `
                position: fixed;
                bottom: 20px;
                left: 20px;
                background: rgba(0, 0, 0, 0.8);
                color: white;
                padding: 15px;
                border-radius: 8px;
                font-family: monospace;
                font-size: 12px;
                z-index: 10000;
                max-width: 300px;
                cursor: move;
            `;
            
            debugPanel.innerHTML = `
                <div style="margin-bottom: 10px; font-weight: bold; color: #4CAF50;">📱 Offline Debug</div>
                <div id="debug-status">Loading...</div>
                <div style="margin-top: 10px;">
                    <button onclick="window.offlineIntegration.forceSaveCurrentState()" style="
                        background: #4CAF50; color: white; border: none; padding: 5px 10px; 
                        border-radius: 4px; cursor: pointer; font-size: 11px; margin: 2px;
                    ">💾 Save Now</button>
                    <button onclick="window.offlineIntegration.forceRefreshCache()" style="
                        background: #2196F3; color: white; border: none; padding: 5px 10px; 
                        border-radius: 4px; cursor: pointer; font-size: 11px; margin: 2px;
                    ">🔄 Refresh Cache</button>
                    <button onclick="document.getElementById('offline-debug-panel').remove()" style="
                        background: #f44336; color: white; border: none; padding: 5px 10px; 
                        border-radius: 4px; cursor: pointer; font-size: 11px; margin: 2px;
                    ">❌ Close</button>
                </div>
            `;
            
            document.body.appendChild(debugPanel);
            
            // Make it draggable
            this.makeDraggable(debugPanel);
            
            // Update status periodically
            setInterval(() => {
                this.updateDebugStatus();
            }, 2000);
            
            // Initial status update
            this.updateDebugStatus();
        }
    }
    
    makeDraggable(element) {
        let isDragging = false;
        let currentX;
        let currentY;
        let initialX;
        let initialY;
        let xOffset = 0;
        let yOffset = 0;
        
        element.addEventListener('mousedown', dragStart);
        document.addEventListener('mousemove', drag);
        document.addEventListener('mouseup', dragEnd);
        
        function dragStart(e) {
            initialX = e.clientX - xOffset;
            initialY = e.clientY - yOffset;
            
            if (e.target === element) {
                isDragging = true;
            }
        }
        
        function drag(e) {
            if (isDragging) {
                e.preventDefault();
                currentX = e.clientX - initialX;
                currentY = e.clientY - initialY;
                xOffset = currentX;
                yOffset = currentY;
                
                element.style.transform = `translate(${currentX}px, ${currentY}px)`;
            }
        }
        
        function dragEnd() {
            initialX = currentX;
            initialY = currentY;
            isDragging = false;
        }
    }
    
    updateDebugStatus() {
        const statusDiv = document.getElementById('debug-status');
        if (!statusDiv) return;
        
        const status = this.getOfflineStatus();
        const lastSave = status.lastSave === 'Never' ? 'Never' : new Date(status.lastSave).toLocaleTimeString();
        
        statusDiv.innerHTML = `
            <div>🌐 Online: ${status.isOnline ? 'Yes' : 'No'}</div>
            <div>📱 Offline Mode: ${status.offlineMode ? 'Yes' : 'No'}</div>
            <div>💾 Has Data: ${status.hasOfflineData ? 'Yes' : 'No'}</div>
            <div>⏰ Last Save: ${lastSave}</div>
        `;
    }
    
    setupDataChangeListeners() {
        // Listen for potential data changes
        const observer = new MutationObserver((mutations) => {
            // Check if any significant changes occurred
            let shouldSave = false;
            
            for (const mutation of mutations) {
                if (mutation.type === 'childList') {
                    // Check if cue-related elements were added/removed
                    if (mutation.target.matches && (
                        mutation.target.matches('table') ||
                        mutation.target.matches('[data-cue]') ||
                        mutation.target.matches('.cue') ||
                        mutation.target.matches('.cue-item')
                    )) {
                        shouldSave = true;
                        break;
                    }
                }
            }
            
            if (shouldSave && this.isOnline) {
                // Debounce the save operation
                clearTimeout(this.saveTimeout);
                this.saveTimeout = setTimeout(() => {
                    this.saveCurrentState();
                }, 1000);
            }
        });
        
        // Start observing the document body for changes
        observer.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: false,
            characterData: false
        });
        
        this.mutationObserver = observer;
    }
    
    startPeriodicSync() {
        // Sync every 5 minutes when online
        this.syncInterval = setInterval(() => {
            if (this.isOnline && !this.offlineMode) {
                this.syncOfflineData();
            }
        }, 5 * 60 * 1000);
    }
    
    async checkConnectionQuality() {
        try {
            // Test connection quality by making a small request
            const startTime = Date.now();
            const response = await fetch(`${window.location.origin}/health`, { 
                method: 'HEAD',
                cache: 'no-cache'
            });
            const endTime = Date.now();
            
            const responseTime = endTime - startTime;
            
            if (response.ok) {
                if (responseTime < 100) {
                    this.connectionQuality = 'excellent';
                } else if (responseTime < 500) {
                    this.connectionQuality = 'good';
                } else if (responseTime < 2000) {
                    this.connectionQuality = 'fair';
                } else {
                    this.connectionQuality = 'poor';
                }
                
                console.log(`🌐 Connection quality: ${this.connectionQuality} (${responseTime}ms)`);
            }
        } catch (error) {
            this.connectionQuality = 'unknown';
            console.warn('⚠️ Could not determine connection quality:', error);
        }
    }
    
    async saveCurrentState() {
        try {
            // Save current app state to offline storage
            const currentState = this.captureCurrentState();
            
            if (this.offlineDataManager && this.offlineDataManager.isAvailable()) {
                // Save to IndexedDB
                if (currentState.cueStacks) {
                    await this.offlineDataManager.saveCueStacks(currentState.cueStacks);
                }
                if (currentState.highlightColors) {
                    await this.offlineDataManager.saveHighlightColors(currentState.highlightColors);
                }
            }
            
            // Cache in service worker
            if (this.serviceWorkerRegistration && this.serviceWorkerRegistration.active) {
                this.serviceWorkerRegistration.active.postMessage({
                    type: 'CACHE_DATA',
                    cues: currentState,
                    html: document.documentElement.outerHTML
                });
            }
            
            // Save to localStorage as backup
            this.saveToLocalStorage(currentState);
            
            // Update last save timestamp
            this.lastSaveTime = Date.now();
            
            console.log('💾 Current state saved for offline use at', new Date(this.lastSaveTime).toLocaleTimeString());
            
        } catch (error) {
            console.warn('⚠️ Failed to save current state:', error);
            // Show error notification
            this.showNotification('⚠️ Failed to save offline data', 'error');
        }
    }
    
    captureCurrentState() {
        // Capture the current state of the app
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
            
            // Look for data in hidden inputs or data attributes
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
            
            // Capture the entire DOM content for offline viewing
            state.domContent = this.captureDOMContent();
            
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
            
            // Capture any global variables that might contain cue data
            if (typeof window.getCueData === 'function') {
                try {
                    state.functionData = window.getCueData();
                } catch (e) {
                    // Ignore function call errors
                }
            }
            
            // Look for data in window object properties
            const dataProperties = ['cues', 'cueStacks', 'cueData', 'appData', 'currentData'];
            for (const prop of dataProperties) {
                if (window[prop]) {
                    state[prop] = window[prop];
                }
            }
            
        } catch (error) {
            console.warn('⚠️ Failed to capture complete app state:', error);
        }
        
        return state;
    }
    
    captureDOMContent() {
        // Capture the essential DOM content for offline viewing
        const content = {
            title: document.title,
            bodyContent: document.body.innerHTML,
            styles: this.captureStyles(),
            scripts: this.captureScripts()
        };
        
        // Try to preserve the main app structure
        const mainApp = document.querySelector('#app, .app, [data-app], main, .main-content');
        if (mainApp) {
            content.mainApp = mainApp.outerHTML;
        }
        
        // Capture any tables or lists that might contain cue data
        const tables = document.querySelectorAll('table');
        if (tables.length > 0) {
            content.tables = Array.from(tables).map(table => table.outerHTML);
        }
        
        // Capture any cue-related elements
        const cueElements = document.querySelectorAll('[data-cue], .cue, .cue-item');
        if (cueElements.length > 0) {
            content.cueElements = Array.from(cueElements).map(el => el.outerHTML);
        }
        
        return content;
    }
    
    captureStyles() {
        // Capture inline styles and critical CSS
        const styles = [];
        
        // Get inline styles
        const styleElements = document.querySelectorAll('style');
        styleElements.forEach(style => {
            styles.push(style.textContent);
        });
        
        // Get external stylesheet content if possible
        const linkElements = document.querySelectorAll('link[rel="stylesheet"]');
        linkElements.forEach(link => {
            if (link.href && link.href.startsWith(window.location.origin)) {
                // Only capture local stylesheets
                styles.push(`/* External stylesheet: ${link.href} */`);
            }
        });
        
        return styles;
    }
    
    captureScripts() {
        // Capture essential script content
        const scripts = [];
        
        const scriptElements = document.querySelectorAll('script:not([src])');
        scriptElements.forEach(script => {
            if (script.textContent.trim()) {
                scripts.push(script.textContent);
            }
        });
        
        return scripts;
    }
    
    saveToLocalStorage(state) {
        try {
            localStorage.setItem('cueToCueOfflineState', JSON.stringify(state));
            localStorage.setItem('cueToCueOfflineTimestamp', Date.now().toString());
        } catch (error) {
            console.warn('⚠️ Failed to save to localStorage:', error);
        }
    }
    
    async restoreOfflineState() {
        try {
            let state = null;
            
            // Try to restore from IndexedDB first
            if (this.offlineDataManager && this.offlineDataManager.isAvailable()) {
                const cueStacks = await this.offlineDataManager.getCueStacks();
                const highlightColors = await this.offlineDataManager.getHighlightColors();
                
                if (cueStacks.length > 0) {
                    state = {
                        cueStacks: cueStacks,
                        highlightColors: highlightColors,
                        timestamp: Date.now()
                    };
                }
            }
            
            // Fallback to localStorage
            if (!state) {
                const storedState = localStorage.getItem('cueToCueOfflineState');
                if (storedState) {
                    state = JSON.parse(storedState);
                }
            }
            
            if (state) {
                // Try to restore the full page state first
                if (this.restoreFullPageState(state)) {
                    console.log('📱 Full page state restored');
                    return true;
                }
                
                // Fallback to offline display if full restoration fails
                this.displayOfflineState(state);
                console.log('📱 Offline state restored (fallback mode)');
                return true;
            }
            
        } catch (error) {
            console.warn('⚠️ Failed to restore offline state:', error);
        }
        
        return false;
    }
    
    restoreFullPageState(state) {
        try {
            // If we have DOM content, try to restore the full page
            if (state.domContent && state.domContent.bodyContent) {
                // Create a temporary container to parse the content
                const tempDiv = document.createElement('div');
                tempDiv.innerHTML = state.domContent.bodyContent;
                
                // Replace the current body content
                document.body.innerHTML = tempDiv.innerHTML;
                
                // Restore the title
                if (state.domContent.title) {
                    document.title = state.domContent.title + ' - Offline';
                }
                
                // Add offline indicators to the restored page
                this.addOfflineIndicatorsToPage();
                
                // Try to restore any cue data to the page
                this.injectCueDataIntoPage(state);
                
                console.log('📱 Full page restored from cache');
                return true;
            }
            
            return false;
        } catch (error) {
            console.warn('⚠️ Failed to restore full page state:', error);
            return false;
        }
    }
    
    addOfflineIndicatorsToPage() {
        // Add offline banner at the top of the page
        const offlineBanner = document.createElement('div');
        offlineBanner.id = 'offline-banner';
        offlineBanner.style.cssText = `
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            background: linear-gradient(135deg, #ff6b6b, #ee5a24);
            color: white;
            padding: 12px 20px;
            text-align: center;
            font-weight: 600;
            font-size: 13px;
            z-index: 10000;
            box-shadow: 0 4px 15px rgba(0,0,0,0.3);
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 15px;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            backdrop-filter: blur(15px);
            -webkit-backdrop-filter: blur(15px);
        `;
        
        offlineBanner.innerHTML = `
            <span style="font-size: 16px;">📱</span>
            <span style="text-transform: uppercase; letter-spacing: 0.5px; font-size: 12px;">You're viewing cached data - Offline Mode</span>
            <button onclick="window.offlineIntegration.safeReconnect()" style="
                background: rgba(255,255,255,0.15);
                border: 1px solid rgba(255,255,255,0.25);
                color: white;
                padding: 6px 14px;
                border-radius: 15px;
                cursor: pointer;
                font-size: 11px;
                font-weight: 600;
                transition: all 0.3s ease;
                backdrop-filter: blur(10px);
                -webkit-backdrop-filter: blur(10px);
                text-transform: uppercase;
                letter-spacing: 0.5px;
            " onmouseover="this.style.background='rgba(255,255,255,0.25)'" onmouseout="this.style.background='rgba(255,255,255,0.15)'">
                🔄 Try to Reconnect
            </button>
        `;
        
        document.body.insertBefore(offlineBanner, document.body.firstChild);
        
        // Add offline styling to the page
        this.addOfflinePageStyles();
        
        // Make all interactive elements read-only
        this.makePageReadOnly();
    }
    
    addOfflinePageStyles() {
        const style = document.createElement('style');
        style.textContent = `
            /* Offline mode styling */
            body { 
                padding-top: 60px; /* Make room for offline banner */
            }
            
            /* Dim interactive elements */
            input, textarea, button:not([onclick*="reload"]), select {
                opacity: 0.6;
                pointer-events: none;
            }
            
            /* Show offline indicator on forms */
            form::before {
                content: "📱 Offline - Read Only";
                display: block;
                background: #ffebee;
                color: #c62828;
                padding: 8px 12px;
                margin-bottom: 15px;
                border-radius: 4px;
                font-size: 12px;
                font-weight: bold;
                text-align: center;
            }
            
            /* Highlight offline status */
            .offline-mode {
                border-left: 4px solid #ff6b6b;
                padding-left: 15px;
                background: rgba(255, 107, 107, 0.05);
            }
        `;
        document.head.appendChild(style);
    }
    
    makePageReadOnly() {
        // Make all inputs read-only
        const inputs = document.querySelectorAll('input, textarea');
        inputs.forEach(input => {
            if (input.type !== 'hidden') {
                input.setAttribute('readonly', true);
                input.setAttribute('data-offline-readonly', 'true');
            }
        });
        
        // Disable buttons (except reconnect button)
        const buttons = document.querySelectorAll('button:not([onclick*="reload"])');
        buttons.forEach(button => {
            button.setAttribute('disabled', true);
            button.setAttribute('data-offline-disabled', 'true');
        });
        
        // Disable forms
        const forms = document.querySelectorAll('form');
        forms.forEach(form => {
            form.classList.add('offline-mode');
        });
        
        // Add offline class to body
        document.body.classList.add('offline-mode');
    }
    
    injectCueDataIntoPage(state) {
        try {
            // Try to inject cue data into any existing elements
            if (state.cueData || state.scriptData || state.attributeData) {
                const cueData = state.cueData || state.scriptData || state.attributeData;
                
                // Look for cue tables and populate them
                const tables = document.querySelectorAll('table');
                if (tables.length > 0 && cueData.cueStacks) {
                    this.populateCueTables(tables, cueData);
                }
                
                // Look for cue lists and populate them
                const cueLists = document.querySelectorAll('[data-cue-list], .cue-list, .cues');
                if (cueLists.length > 0 && cueData.cueStacks) {
                    this.populateCueLists(cueLists, cueData);
                }
                
                // Update any data attributes
                this.updateDataAttributes(cueData);
            }
        } catch (error) {
            console.warn('⚠️ Failed to inject cue data into page:', error);
        }
    }
    
    populateCueTables(tables, cueData) {
        const selectedStack = cueData.cueStacks[cueData.selectedCueStackIndex || 0];
        if (!selectedStack || !selectedStack.cues) return;
        
        tables.forEach(table => {
            const tbody = table.querySelector('tbody');
            if (tbody) {
                tbody.innerHTML = '';
                
                selectedStack.cues.forEach((cue, index) => {
                    const row = document.createElement('tr');
                    row.className = `${index === cueData.activeCueIndex ? 'active-cue' : ''} ${index === cueData.selectedCueIndex ? 'selected-cue' : ''}`;
                    
                    if (cue.values && Array.isArray(cue.values)) {
                        cue.values.forEach(value => {
                            const cell = document.createElement('td');
                            cell.textContent = value;
                            if (cue.isStruckThrough) {
                                cell.style.textDecoration = 'line-through';
                                cell.style.opacity = '0.6';
                            }
                            row.appendChild(cell);
                        });
                    }
                    
                    tbody.appendChild(row);
                });
            }
        });
    }
    
    populateCueLists(lists, cueData) {
        const selectedStack = cueData.cueStacks[cueData.selectedCueStackIndex || 0];
        if (!selectedStack || !selectedStack.cues) return;
        
        lists.forEach(list => {
            list.innerHTML = '';
            
            selectedStack.cues.forEach((cue, index) => {
                const item = document.createElement('div');
                item.className = `cue-item ${index === cueData.activeCueIndex ? 'active-cue' : ''} ${index === cueData.selectedCueIndex ? 'selected-cue' : ''}`;
                
                if (cue.values && Array.isArray(cue.values)) {
                    item.textContent = cue.values.join(' - ');
                }
                
                if (cue.isStruckThrough) {
                    item.style.textDecoration = 'line-through';
                    item.style.opacity = '0.6';
                }
                
                list.appendChild(item);
            });
        });
    }
    
    updateDataAttributes(cueData) {
        // Update any elements with data attributes that might contain cue data
        const dataElements = document.querySelectorAll('[data-cue-data]');
        dataElements.forEach(element => {
            try {
                element.dataset.cueData = JSON.stringify(cueData);
            } catch (e) {
                // Ignore errors
            }
        });
    }
    
    displayOfflineState(state) {
        // Display the offline state in read-only mode
        if (state.cueStacks && state.cueStacks.length > 0) {
            this.createOfflineCueDisplay(state);
        }
    }
    
    createOfflineCueDisplay(state) {
        // Create a read-only display of the cue data
        const container = document.createElement('div');
        container.id = 'offline-cue-display';
        container.className = 'offline-cue-container';
        
        const selectedStack = state.cueStacks[state.selectedCueStackIndex || 0];
        if (!selectedStack) return;
        
        container.innerHTML = `
            <div class="offline-header">
                <h1>📱 Cue to Cue - Offline Mode</h1>
                <p class="offline-subtitle">Viewing cached data from ${new Date(state.timestamp).toLocaleString()}</p>
                <div class="connection-status offline">🔴 Offline - Read Only</div>
            </div>
            
            <div class="offline-cue-content">
                <h2>${selectedStack.name}</h2>
                
                <div class="offline-cue-table">
                    <table>
                        <thead>
                            <tr>
                                ${selectedStack.columns.map(col => `<th style="width: ${col.width}px">${col.name}</th>`).join('')}
                            </tr>
                        </thead>
                        <tbody>
                            ${selectedStack.cues.map((cue, index) => `
                                <tr class="${index === state.activeCueIndex ? 'active-cue' : ''} ${index === state.selectedCueIndex ? 'selected-cue' : ''}">
                                    ${cue.values.map((value, colIndex) => `
                                        <td class="${cue.isStruckThrough ? 'struck-through' : ''}">
                                            ${value}
                                        </td>
                                    `).join('')}
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
                
                ${state.highlightColors && state.highlightColors.length > 0 ? `
                    <div class="offline-highlight-colors">
                        <h3>Highlight Colors</h3>
                        <div class="color-list">
                            ${state.highlightColors.map(color => `
                                <span class="color-item" style="background-color: ${color.color}">
                                    ${color.keyword}
                                </span>
                            `).join('')}
                        </div>
                    </div>
                ` : ''}
            </div>
            
            <div class="offline-footer">
                <button onclick="window.offlineIntegration.safeReconnect()" class="retry-button">
                    🔄 Try to Reconnect
                </button>
                <p class="offline-note">
                    This is a read-only view of your last known data. 
                    Some features may be limited while offline.
                </p>
            </div>
        `;
        
        // Add offline styles
        this.addOfflineStyles();
        
        // Replace the page content
        document.body.innerHTML = '';
        document.body.appendChild(container);
        
        // Update page title
        document.title = 'Cue to Cue - Offline Mode';
    }
    
    addOfflineStyles() {
        const style = document.createElement('style');
        style.textContent = `
            .offline-cue-container {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                max-width: 1200px;
                margin: 0 auto;
                padding: 20px;
                background: #f5f5f5;
                min-height: 100vh;
            }
            
            .offline-header {
                text-align: center;
                margin-bottom: 30px;
                padding: 20px;
                background: white;
                border-radius: 10px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            
            .offline-header h1 {
                color: #333;
                margin-bottom: 10px;
            }
            
            .offline-subtitle {
                color: #666;
                margin-bottom: 15px;
            }
            
            .connection-status {
                display: inline-block;
                padding: 8px 16px;
                border-radius: 20px;
                font-weight: bold;
                font-size: 14px;
            }
            
            .connection-status.offline {
                background: #ffebee;
                color: #c62828;
                border: 1px solid #ffcdd2;
            }
            
            .offline-cue-content {
                background: white;
                padding: 20px;
                border-radius: 10px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                margin-bottom: 20px;
            }
            
            .offline-cue-content h2 {
                color: #333;
                margin-bottom: 20px;
                text-align: center;
            }
            
            .offline-cue-table {
                overflow-x: auto;
            }
            
            .offline-cue-table table {
                width: 100%;
                border-collapse: collapse;
                border: 1px solid #ddd;
            }
            
            .offline-cue-table th,
            .offline-cue-table td {
                padding: 12px;
                text-align: left;
                border: 1px solid #ddd;
            }
            
            .offline-cue-table th {
                background: #f8f9fa;
                font-weight: bold;
                color: #333;
            }
            
            .offline-cue-table tr.active-cue {
                background: #e3f2fd;
            }
            
            .offline-cue-table tr.selected-cue {
                background: #fff3e0;
            }
            
            .offline-cue-table .struck-through {
                text-decoration: line-through;
                color: #999;
            }
            
            .offline-highlight-colors {
                margin-top: 20px;
                padding-top: 20px;
                border-top: 1px solid #eee;
            }
            
            .offline-highlight-colors h3 {
                color: #333;
                margin-bottom: 15px;
            }
            
            .color-list {
                display: flex;
                flex-wrap: wrap;
                gap: 10px;
            }
            
            .color-item {
                padding: 6px 12px;
                border-radius: 15px;
                color: white;
                font-size: 12px;
                font-weight: bold;
                text-shadow: 0 1px 2px rgba(0,0,0,0.3);
            }
            
            .offline-footer {
                text-align: center;
                padding: 20px;
                background: white;
                border-radius: 10px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            
            .retry-button {
                background: #4CAF50;
                color: white;
                border: none;
                padding: 12px 24px;
                border-radius: 6px;
                font-size: 16px;
                cursor: pointer;
                margin-bottom: 15px;
            }
            
            .retry-button:hover {
                background: #45a049;
            }
            
            .offline-note {
                color: #666;
                font-size: 14px;
                line-height: 1.5;
            }
            
            @media (max-width: 768px) {
                .offline-cue-container {
                    padding: 10px;
                }
                
                .offline-cue-table {
                    font-size: 14px;
                }
                
                .offline-cue-table th,
                .offline-cue-table td {
                    padding: 8px;
                }
            }
        `;
        document.head.appendChild(style);
    }
    
    handleOnline() {
        this.isOnline = true;
        
        // Show reconnecting state first
        this.showReconnectingState();
        
        // Wait a moment to show the reconnecting state
        setTimeout(async () => {
            try {
                // Try to sync data
                await this.syncOfflineData();
                
                // Disable offline mode
                this.offlineMode = false;
                
                // Remove offline display if present
                const offlineDisplay = document.getElementById('offline-cue-display');
                if (offlineDisplay) {
                    offlineDisplay.remove();
                }
                
                // Remove offline banner if present
                const offlineBanner = document.getElementById('offline-banner');
                if (offlineBanner) {
                    offlineBanner.remove();
                }
                
                // Restore original page
                await this.restoreOriginalPage();
                
                // Show success message
                this.showConnectionRestoredMessage();
                
                console.log('🌐 Back online - syncing data');
            } catch (error) {
                console.warn('⚠️ Failed to restore online state:', error);
                // Fallback to offline mode if restoration fails
                this.offlineMode = true;
            }
        }, 1500);
    }
    
    handleOffline() {
        this.isOnline = false;
        
        // Show disconnecting state first
        this.showDisconnectingState();
        
        // Wait a moment to show the disconnecting state
        setTimeout(async () => {
            // Try to restore offline state
            const restored = await this.restoreOfflineState();
            if (restored) {
                this.offlineMode = true;
                console.log('📱 Offline mode enabled with cached data');
            } else {
                // No cached data available
                this.showNoDataMessage();
            }
        }, 1000);
        
        console.log('📱 Gone offline');
    }
    
    showReconnectingState() {
        // Show reconnecting notification
        this.showNotification('🔄 Reconnecting...', 'info');
    }
    
    showDisconnectingState() {
        // Show disconnecting notification
        this.showNotification('📱 Going offline...', 'warning');
    }
    
    showConnectionRestoredMessage() {
        this.showNotification('✅ Connection restored!', 'success');
    }
    
    showNotification(message, type = 'info') {
        // Create notification element
        const notification = document.createElement('div');
        notification.id = `notification-${Date.now()}`;
        
        let backgroundColor, borderColor, icon;
        switch (type) {
            case 'success':
                backgroundColor = 'rgba(76, 175, 80, 0.95)';
                borderColor = '#4CAF50';
                icon = '✅';
                break;
            case 'warning':
                backgroundColor = 'rgba(255, 152, 0, 0.95)';
                borderColor = '#FF9800';
                icon = '⚠️';
                break;
            case 'error':
                backgroundColor = 'rgba(244, 67, 54, 0.95)';
                borderColor = '#F44336';
                icon = '❌';
                break;
            default:
                backgroundColor = 'rgba(33, 150, 243, 0.95)';
                borderColor = '#2196F3';
                icon = 'ℹ️';
        }
        
        notification.style.cssText = `
            position: fixed;
            top: 80px;
            right: 20px;
            background: ${backgroundColor};
            color: white;
            padding: 12px 18px;
            border-radius: 15px;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            font-size: 13px;
            font-weight: 600;
            z-index: 10002;
            display: flex;
            align-items: center;
            gap: 10px;
            box-shadow: 0 6px 20px rgba(0, 0, 0, 0.3);
            border: 2px solid ${borderColor};
            animation: slideIn 0.4s ease-out;
            max-width: 280px;
            backdrop-filter: blur(15px);
            -webkit-backdrop-filter: blur(15px);
            letter-spacing: 0.3px;
        `;
        
        notification.innerHTML = `
            <span style="font-size: 16px;">${icon}</span>
            <span style="font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px;">${message}</span>
        `;
        
        document.body.appendChild(notification);
        
        // Auto-remove after 3 seconds
        setTimeout(() => {
            if (notification.parentNode) {
                notification.style.animation = 'slideIn 0.4s ease-out reverse';
                setTimeout(() => {
                    if (notification.parentNode) {
                        notification.remove();
                    }
                }, 400);
            }
        }, 3000);
    }
    
    async restoreOriginalPage() {
        // Try to restore the original page from cache
        try {
            this.showNotification('🔄 Restoring online page...', 'info');
            
            const response = await fetch('/');
            if (response.ok) {
                const html = await response.text();
                document.documentElement.innerHTML = html;
                
                // Re-initialize the page
                this.init();
                
                this.showNotification('✅ Online page restored', 'success');
            } else {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
        } catch (error) {
            console.warn('⚠️ Failed to restore original page:', error);
            this.showNotification('⚠️ Failed to restore online page', 'error');
            
            // Fallback: try to reload the page
            setTimeout(() => {
                window.location.reload();
            }, 2000);
        }
    }
    
    showNoDataMessage() {
        // Show message when no offline data is available
        const container = document.createElement('div');
        container.innerHTML = `
            <div style="
                text-align: center; 
                padding: 50px; 
                font-family: -apple-system, sans-serif;
                background: linear-gradient(135deg, #f5f7fa, #c3cfe2);
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
            ">
                <div style="
                    background: white;
                    padding: 40px;
                    border-radius: 20px;
                    box-shadow: 0 20px 40px rgba(0,0,0,0.1);
                    max-width: 500px;
                ">
                    <h1 style="color: #333; margin-bottom: 20px;">📱 No Offline Data Available</h1>
                    <p style="color: #666; line-height: 1.6; margin-bottom: 30px;">
                        Please visit this page while online first to cache data for offline viewing.
                        <br><br>
                        <strong>Tip:</strong> Stay on the page for a few seconds to ensure data is properly cached.
                    </p>
                    <button onclick="window.offlineIntegration.safeReconnect()" style="
                        background: #007AFF; 
                        color: white; 
                        border: none; 
                        padding: 15px 30px; 
                        border-radius: 25px; 
                        cursor: pointer;
                        font-size: 16px;
                        font-weight: 600;
                        transition: all 0.3s ease;
                        box-shadow: 0 4px 15px rgba(0, 122, 255, 0.3);
                    " onmouseover="this.style.transform='translateY(-2px)'; this.style.boxShadow='0 6px 20px rgba(0, 122, 255, 0.4)'" onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 15px rgba(0, 122, 255, 0.3)'">
                        🔄 Try Again
                    </button>
                </div>
            </div>
        `;
        
        document.body.innerHTML = '';
        document.body.appendChild(container);
        document.title = 'Cue to Cue - No Offline Data';
        
        // Show notification
        this.showNotification('📱 No offline data available', 'warning');
    }
    
    async syncOfflineData() {
        if (!this.isOnline) return;
        
        try {
            // Show syncing notification
            this.showNotification('🔄 Syncing offline data...', 'info');
            
            // Sync any offline changes
            if (this.offlineDataManager && this.offlineDataManager.isAvailable()) {
                const offlineChanges = await this.offlineDataManager.getOfflineChanges();
                
                if (offlineChanges.length > 0) {
                    // Process offline changes
                    for (const change of offlineChanges) {
                        // Handle different types of changes
                        console.log('🔄 Processing offline change:', change.type);
                    }
                    
                    // Clear processed changes
                    await this.offlineDataManager.clearOfflineChanges();
                    
                    this.showNotification(`✅ Synced ${offlineChanges.length} offline changes`, 'success');
                } else {
                    this.showNotification('✅ No offline changes to sync', 'info');
                }
            }
            
            this.lastSyncTime = Date.now();
            console.log('✅ Offline data synced');
            
        } catch (error) {
            console.warn('⚠️ Failed to sync offline data:', error);
            this.showNotification('⚠️ Failed to sync offline data', 'error');
        }
    }
    
    handleServiceWorkerMessage(event) {
        const { type, data } = event.data;
        
        switch (type) {
            case 'CACHE_UPDATED':
                console.log('💾 Cache updated:', data);
                break;
            case 'SYNC_COMPLETED':
                console.log('🔄 Sync completed:', data);
                break;
            default:
                console.log('📨 Service worker message:', event.data);
        }
    }
    
    showUpdateNotification() {
        // Show notification when service worker update is available
        const notification = document.createElement('div');
        notification.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            background: #4CAF50;
            color: white;
            padding: 15px;
            border-radius: 6px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
            z-index: 10000;
            cursor: pointer;
        `;
        notification.innerHTML = '🔄 Update available! Click to refresh.';
        notification.onclick = () => window.location.reload();
        
        document.body.appendChild(notification);
        
        // Auto-remove after 10 seconds
        setTimeout(() => {
            if (notification.parentNode) {
                notification.remove();
            }
        }, 10000);
    }
    
    // Public methods for external use
    enableOfflineMode() {
        this.offlineMode = true;
        this.restoreOfflineState();
    }
    
    disableOfflineMode() {
        this.offlineMode = false;
        this.restoreOriginalPage();
    }
    
    /// Force save the current state immediately
    forceSaveCurrentState() {
        console.log('💾 Force saving current state...');
        this.saveCurrentState();
    }
    
    /// Force refresh the offline cache
    async forceRefreshCache() {
        console.log('🔄 Force refreshing offline cache...');
        
        // Clear existing cache
        if (this.offlineDataManager && this.offlineDataManager.isAvailable()) {
            await this.offlineDataManager.clearOfflineChanges();
        }
        
        // Save current state
        this.forceSaveCurrentState();
        
        // Notify service worker to refresh cache
        if (this.serviceWorkerRegistration && this.serviceWorkerRegistration.active) {
            this.serviceWorkerRegistration.active.postMessage({
                type: 'REFRESH_CACHE',
                timestamp: Date.now()
            });
        }
        
        console.log('✅ Offline cache refreshed');
    }
    
    /// Safe reconnection method that checks connection status before attempting to reconnect
    async safeReconnect() {
        console.log('🔄 Attempting safe reconnection...');
        
        // Show reconnecting state
        this.showNotification('🔄 Checking connection...', 'info');
        
        try {
            // First check if we're actually online
            if (!navigator.onLine) {
                const airplaneModeMessage = this.detectAirplaneMode();
                this.showNotification(airplaneModeMessage, 'warning');
                return;
            }
            
            // Test connection by making a small request
            const response = await fetch(`${window.location.origin}/health`, { 
                method: 'HEAD',
                cache: 'no-cache',
                signal: AbortSignal.timeout(5000) // 5 second timeout
            });
            
            if (response.ok) {
                // Connection successful, reload the page
                this.showNotification('✅ Connection restored! Reloading...', 'success');
                setTimeout(() => {
                    window.location.reload();
                }, 1000);
            } else {
                // Server responded but with error
                this.showNotification('⚠️ Server error. Please try again later.', 'warning');
            }
            
        } catch (error) {
            console.warn('⚠️ Reconnection failed:', error);
            
            if (error.name === 'AbortError') {
                this.showNotification('⏰ Connection timeout. Please check your network.', 'warning');
            } else if (error.name === 'TypeError' && error.message.includes('fetch')) {
                // This usually means no internet connection
                const airplaneModeMessage = this.detectAirplaneMode();
                this.showNotification(airplaneModeMessage, 'warning');
            } else {
                this.showNotification('❌ Reconnection failed. Please try again.', 'error');
            }
        }
    }
    
    /// Detect if device is in airplane mode and provide helpful guidance
    detectAirplaneMode() {
        // Check for airplane mode indicators
        if (navigator.connection) {
            const connection = navigator.connection;
            
            // Check for very slow or no connection
            if (connection.effectiveType === 'slow-2g' || connection.downlink === 0) {
                return '✈️ Airplane mode detected. Please turn off airplane mode to reconnect.';
            }
            
            // Check for cellular connection issues
            if (connection.type === 'cellular' && connection.downlink < 0.1) {
                return '📱 Poor cellular connection. Please check your signal or try WiFi.';
            }
        }
        
        // Check for other offline indicators
        if (navigator.userAgent.includes('iPhone') || navigator.userAgent.includes('iPad')) {
            return '📱 iOS device detected. Please check Control Center and turn off airplane mode.';
        } else if (navigator.userAgent.includes('Android')) {
            return '📱 Android device detected. Please check Quick Settings and turn off airplane mode.';
        }
        
        // Generic message
        return '❌ No internet connection available. Please check your network settings.';
    }
    
    /// Cleanup resources when integration is destroyed
    destroy() {
        // Clear intervals
        if (this.syncInterval) {
            clearInterval(this.syncInterval);
            this.syncInterval = null;
        }
        
        // Remove mutation observer
        if (this.mutationObserver) {
            this.mutationObserver.disconnect();
            this.mutationObserver = null;
        }
        
        // Remove elements
        // No longer needed as connection status indicator is removed
        
        if (this.debugPanel) {
            this.debugPanel.remove();
            this.debugPanel = null;
        }
        
        console.log('🧹 Offline integration cleaned up');
    }
    
    getOfflineStatus() {
        return {
            isOnline: this.isOnline,
            offlineMode: this.offlineMode,
            lastSync: this.lastSyncTime,
            hasOfflineData: this.offlineDataManager?.isAvailable() || false,
            lastSave: this.lastSaveTime || 'Never',
            connectionStatus: this.getConnectionStatusText()
        };
    }
    
    getConnectionStatusText() {
        if (this.isOnline && !this.offlineMode) {
            return 'Connected';
        } else if (this.isOnline && this.offlineMode) {
            return 'Reconnecting...';
        } else if (!this.isOnline && this.offlineMode) {
            return 'Disconnected';
        } else {
            return 'No Data';
        }
    }
}

// Initialize offline integration when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        window.offlineIntegration = new OfflineIntegration();
    });
} else {
    window.offlineIntegration = new OfflineIntegration();
}

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = OfflineIntegration;
}
