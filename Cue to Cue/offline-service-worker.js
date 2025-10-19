// Enhanced Offline Service Worker for Cue to Cue
// This service worker provides comprehensive offline functionality with data persistence

const CACHE_NAME = 'cue-to-cue-offline-v3';
const DATA_CACHE_NAME = 'cue-to-cue-data-v3';
const APP_CACHE_NAME = 'cue-to-cue-app-v3';

// Files to cache for offline functionality
const STATIC_CACHE_URLS = [
    '/',
    '/offline.html',
    '/offline-data-manager.js',
    '/offline-state-manager.js',
    '/offline-styles.css',
    '/offline-integration.js',
    '/manifest.json'
];

// Install event - cache essential files and set up offline storage
self.addEventListener('install', (event) => {
    console.log('🔄 Enhanced Offline Service Worker installing...');
    event.waitUntil(
        Promise.all([
            // Cache static files
            caches.open(CACHE_NAME).then(cache => {
                console.log('📦 Caching static offline files');
                return cache.addAll(STATIC_CACHE_URLS);
            }),
            // Initialize data cache
            caches.open(DATA_CACHE_NAME).then(cache => {
                console.log('💾 Data cache initialized');
                return cache;
            }),
            // Initialize app cache
            caches.open(APP_CACHE_NAME).then(cache => {
                console.log('📱 App cache initialized');
                return cache;
            })
        ]).catch(error => {
            console.warn('⚠️ Offline caching failed:', error);
            // Don't fail the install - offline mode is optional
        })
    );
});

// Fetch event - serve cached content when offline
self.addEventListener('fetch', (event) => {
    const { request } = event;
    const url = new URL(request.url);
    
    // Handle different types of requests
    if (request.mode === 'navigate') {
        // Navigation requests - serve cached version or offline page
        event.respondWith(handleNavigationRequest(request));
    } else if (request.destination === 'script' || request.destination === 'style') {
        // Static resources - serve from cache if available
        event.respondWith(handleStaticResourceRequest(request));
    } else if (url.pathname === '/cues') {
        // API requests - serve cached data when offline
        event.respondWith(handleAPIRequest(request));
    } else if (url.pathname === '/') {
        // Main app page - cache and serve from cache when offline
        event.respondWith(handleMainAppRequest(request));
    } else {
        // Other requests - try network first, fallback to cache
        event.respondWith(handleOtherRequest(request));
    }
});

// Handle main app page requests (root path)
async function handleMainAppRequest(request) {
    try {
        // Try to fetch from network first
        const response = await fetch(request);
        
        // Cache successful responses for offline use
        if (response.ok) {
            const responseClone = response.clone();
            caches.open(APP_CACHE_NAME).then(cache => {
                cache.put(request, responseClone);
                console.log('💾 Main app page cached for offline use');
            });
        }
        
        return response;
    } catch (error) {
        console.log('🌐 Network failed, serving main app from cache:', request.url);
        
        // Try to serve from app cache first
        const cachedResponse = await caches.match(request, { cacheName: APP_CACHE_NAME });
        if (cachedResponse) {
            console.log('📱 Serving main app from cache');
            return cachedResponse;
        }
        
        // Fallback to static cache
        const staticResponse = await caches.match(request, { cacheName: CACHE_NAME });
        if (staticResponse) {
            return staticResponse;
        }
        
        // Last resort - return offline page
        const offlineResponse = await caches.match('/offline.html');
        if (offlineResponse) {
            return offlineResponse;
        }
        
        // Final fallback
        return new Response(
            '<html><body><h1>Offline</h1><p>Please check your connection.</p></body></html>',
            { headers: { 'Content-Type': 'text/html' } }
        );
    }
}

// Handle navigation requests (main app pages)
async function handleNavigationRequest(request) {
    try {
        // Try to fetch from network first
        const response = await fetch(request);
        
        // Cache successful responses for offline use
        if (response.ok) {
            const responseClone = response.clone();
            caches.open(APP_CACHE_NAME).then(cache => {
                cache.put(request, responseClone);
            });
        }
        
        return response;
    } catch (error) {
        console.log('🌐 Network failed, serving from cache:', request.url);
        
        // Try to serve from app cache first
        const cachedResponse = await caches.match(request, { cacheName: APP_CACHE_NAME });
        if (cachedResponse) {
            return cachedResponse;
        }
        
        // Try static cache
        const staticResponse = await caches.match(request, { cacheName: CACHE_NAME });
        if (staticResponse) {
            return staticResponse;
        }
        
        // Fallback to offline page
        const offlineResponse = await caches.match('/offline.html');
        if (offlineResponse) {
            return offlineResponse;
        }
        
        // Last resort - return a basic offline message
        return new Response(
            '<html><body><h1>Offline</h1><p>Please check your connection.</p></body></html>',
            { headers: { 'Content-Type': 'text/html' } }
        );
    }
}

// Handle static resource requests
async function handleStaticResourceRequest(request) {
    try {
        // Try network first
        const response = await fetch(request);
        if (response.ok) {
            // Cache for offline use
            const responseClone = response.clone();
            caches.open(CACHE_NAME).then(cache => {
                cache.put(request, responseClone);
            });
        }
        return response;
    } catch (error) {
        // Serve from cache if available
        const cachedResponse = await caches.match(request);
        if (cachedResponse) {
            return cachedResponse;
        }
        
        // Return empty response for missing resources
        return new Response('', { status: 404 });
    }
}

// Handle API requests (like /cues endpoint)
async function handleAPIRequest(request) {
    try {
        // Try network first
        const response = await fetch(request);
        
        if (response.ok) {
            // Cache the response data for offline use
            const responseClone = response.clone();
            caches.open(DATA_CACHE_NAME).then(cache => {
                cache.put(request, responseClone);
            });
        }
        
        return response;
    } catch (error) {
        console.log('📡 API request failed, serving cached data:', request.url);
        
        // Serve cached data when offline
        const cachedResponse = await caches.match(request);
        if (cachedResponse) {
            return cachedResponse;
        }
        
        // Return empty data if nothing cached
        return new Response(
            JSON.stringify({ error: 'Offline - no cached data available' }),
            { 
                headers: { 'Content-Type': 'application/json' },
                status: 503
            }
        );
    }
}

// Handle other requests
async function handleOtherRequest(request) {
    try {
        const response = await fetch(request);
        return response;
    } catch (error) {
        // Try cache as fallback
        const cachedResponse = await caches.match(request);
        if (cachedResponse) {
            return cachedResponse;
        }
        
        // Return error response
        return new Response('Offline', { status: 503 });
    }
}

// Background sync for offline data
self.addEventListener('sync', (event) => {
    if (event.tag === 'background-sync-cues') {
        console.log('🔄 Background sync triggered for cues');
        event.waitUntil(syncOfflineData());
    }
});

// Sync offline data when connection is restored
async function syncOfflineData() {
    try {
        // Get cached data
        const cache = await caches.open(DATA_CACHE_NAME);
        const cachedRequests = await cache.keys();
        
        // Try to sync each cached request
        for (const request of cachedRequests) {
            if (request.url.includes('/cues')) {
                try {
                    await fetch(request);
                    console.log('✅ Synced cached data:', request.url);
                } catch (error) {
                    console.warn('❌ Failed to sync:', request.url, error);
                }
            }
        }
    } catch (error) {
        console.warn('⚠️ Background sync failed:', error);
    }
}

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
    console.log('🚀 Enhanced Offline Service Worker activating...');
    event.waitUntil(
        caches.keys().then(cacheNames => {
            return Promise.all(
                cacheNames.map(cacheName => {
                    if (cacheName !== CACHE_NAME && cacheName !== DATA_CACHE_NAME && cacheName !== APP_CACHE_NAME) {
                        console.log('🗑️ Deleting old cache:', cacheName);
                        return caches.delete(cacheName);
                    }
                })
            );
        })
    );
});

// Message handling for communication with main thread
self.addEventListener('message', (event) => {
    if (event.data && event.data.type === 'SKIP_WAITING') {
        self.skipWaiting();
    } else if (event.data && event.data.type === 'CACHE_DATA') {
        // Cache data sent from main thread
        event.waitUntil(cacheDataFromMainThread(event.data));
    }
});

// Cache data sent from main thread
async function cacheDataFromMainThread(data) {
    try {
        const cache = await caches.open(DATA_CACHE_NAME);
        
        if (data.cues) {
            // Cache cues data
            const cuesRequest = new Request('/cues');
            const cuesResponse = new Response(JSON.stringify(data.cues), {
                headers: { 'Content-Type': 'application/json' }
            });
            await cache.put(cuesRequest, cuesResponse);
            console.log('💾 Cached cues data from main thread');
        }
        
        if (data.html) {
            // Cache main HTML
            const htmlRequest = new Request('/');
            const htmlResponse = new Response(data.html, {
                headers: { 'Content-Type': 'text/html' }
            });
            await cache.put(htmlRequest, htmlResponse);
            console.log('💾 Cached HTML from main thread');
        }
    } catch (error) {
        console.warn('⚠️ Failed to cache data from main thread:', error);
    }
}

// Periodic cache cleanup
setInterval(async () => {
    try {
        const cache = await caches.open(DATA_CACHE_NAME);
        const requests = await cache.keys();
        
        // Keep only recent data (last 24 hours)
        const cutoffTime = Date.now() - (24 * 60 * 60 * 1000);
        
        for (const request of requests) {
            const response = await cache.match(request);
            if (response) {
                const headers = response.headers;
                const lastModified = headers.get('last-modified') || headers.get('date');
                
                if (lastModified) {
                    const responseTime = new Date(lastModified).getTime();
                    if (responseTime < cutoffTime) {
                        await cache.delete(request);
                        console.log('🧹 Cleaned up old cached data:', request.url);
                    }
                }
            }
        }
    } catch (error) {
        console.warn('⚠️ Cache cleanup failed:', error);
    }
}, 60 * 60 * 1000); // Run every hour
