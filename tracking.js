/**
 * Nebula Creative Site-Wide Visitor Tracking
 * Invisible tracking system for comprehensive analytics
 */

(function() {
    'use strict';
    
    // Configuration
    const TRACKING_CONFIG = {
        visitorsKey: 'nebula_visitors',
        maxVisitors: 10000,
        sessionTimeout: 30 * 60 * 1000, // 30 minutes
        heartbeatInterval: 5 * 60 * 1000, // 5 minutes
        batchSize: 50
    };
    
    // Generate unique session ID
    function generateSessionId() {
        return 'session_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
    }
    
    // Get or create visitor session
    function getVisitorSession() {
        let sessionId = sessionStorage.getItem('nebula_session_id');
        if (!sessionId) {
            sessionId = generateSessionId();
            sessionStorage.setItem('nebula_session_id', sessionId);
        }
        return sessionId;
    }
    
    // Collect comprehensive device information
    async function collectDeviceInfo() {
        const userAgent = navigator.userAgent;
        const screenInfo = {
            width: screen.width,
            height: screen.height,
            colorDepth: screen.colorDepth,
            pixelRatio: window.devicePixelRatio,
            availWidth: screen.availWidth,
            availHeight: screen.availHeight
        };
        
        const browserInfo = getBrowserInfo(userAgent);
        const osInfo = getOSInfo(userAgent);
        const deviceInfo = getDeviceInfo(userAgent, screenInfo);
        
        return {
            userAgent: userAgent,
            browser: browserInfo,
            os: osInfo,
            device: deviceInfo,
            screen: screenInfo,
            language: navigator.language,
            languages: navigator.languages,
            timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
            platform: navigator.platform,
            cookieEnabled: navigator.cookieEnabled,
            onLine: navigator.onLine,
            hardwareConcurrency: navigator.hardwareConcurrency,
            maxTouchPoints: navigator.maxTouchPoints,
            connection: navigator.connection ? {
                effectiveType: navigator.connection.effectiveType,
                downlink: navigator.connection.downlink,
                rtt: navigator.connection.rtt,
                saveData: navigator.connection.saveData
            } : null,
            // IP and location data
            ipAddress: await getClientIP(),
            location: await getLocationData()
        };
    }
    
    // Get browser information
    function getBrowserInfo(userAgent) {
        const browsers = [
            { name: 'Chrome', pattern: /Chrome\/(\d+\.\d+)/ },
            { name: 'Firefox', pattern: /Firefox\/(\d+\.\d+)/ },
            { name: 'Safari', pattern: /Safari\/(\d+\.\d+)/ },
            { name: 'Edge', pattern: /Edg\/(\d+\.\d+)/ },
            { name: 'Opera', pattern: /OPR\/(\d+\.\d+)/ },
            { name: 'Internet Explorer', pattern: /MSIE (\d+\.\d+)/ }
        ];
        
        for (const browser of browsers) {
            const match = userAgent.match(browser.pattern);
            if (match) {
                return {
                    name: browser.name,
                    version: match[1]
                };
            }
        }
        
        return { name: 'Unknown', version: 'Unknown' };
    }
    
    // Get operating system information
    function getOSInfo(userAgent) {
        const osPatterns = [
            { name: 'Windows', pattern: /Windows NT (\d+\.\d+)/ },
            { name: 'macOS', pattern: /Mac OS X (\d+[._]\d+)/ },
            { name: 'Linux', pattern: /Linux/ },
            { name: 'iOS', pattern: /OS (\d+[._]\d+)/ },
            { name: 'Android', pattern: /Android (\d+\.\d+)/ },
            { name: 'Chrome OS', pattern: /CrOS/ }
        ];
        
        for (const os of osPatterns) {
            const match = userAgent.match(os.pattern);
            if (match) {
                return {
                    name: os.name,
                    version: match[1] ? match[1].replace('_', '.') : 'Unknown'
                };
            }
        }
        
        return { name: 'Unknown', version: 'Unknown' };
    }
    
    // Get device information
    function getDeviceInfo(userAgent, screenInfo) {
        let deviceType = 'Desktop';
        let deviceName = 'Unknown Device';
        
        if (/Mobile|Android|iPhone|iPad/.test(userAgent)) {
            deviceType = 'Mobile';
            if (/iPhone/.test(userAgent)) {
                deviceName = 'iPhone';
            } else if (/iPad/.test(userAgent)) {
                deviceName = 'iPad';
                deviceType = 'Tablet';
            } else if (/Android/.test(userAgent)) {
                deviceName = 'Android Device';
            }
        } else if (/Tablet|iPad/.test(userAgent)) {
            deviceType = 'Tablet';
            deviceName = 'Tablet';
        }
        
        return {
            type: deviceType,
            name: deviceName,
            screen: screenInfo
        };
    }
    
    // Get client IP address
    async function getClientIP() {
        try {
            const ipServices = [
                'https://api.ipify.org?format=json',
                'https://ipinfo.io/json',
                'https://ipapi.co/json/'
            ];
            
            for (const service of ipServices) {
                try {
                    const response = await fetch(service, { timeout: 5000 });
                    const data = await response.json();
                    
                    if (data.ip) {
                        return data.ip;
                    }
                } catch (error) {
                    console.warn(`Failed to get IP from ${service}:`, error);
                    continue;
                }
            }
            
            return '127.0.0.1'; // Fallback for local development
        } catch (error) {
            console.error('Error getting client IP:', error);
            return '127.0.0.1';
        }
    }
    
    // Get location data
    async function getLocationData() {
        try {
            const response = await fetch('https://ipinfo.io/json', { timeout: 5000 });
            const data = await response.json();
            
            if (data.error) {
                throw new Error(data.reason);
            }
            
            return {
                country: data.country || 'Unknown',
                countryCode: data.country_code || 'Unknown',
                region: data.region || 'Unknown',
                regionCode: data.region_code || 'Unknown',
                city: data.city || 'Unknown',
                zipCode: data.postal || 'Unknown',
                latitude: data.latitude || null,
                longitude: data.longitude || null,
                timezone: data.timezone || Intl.DateTimeFormat().resolvedOptions().timeZone,
                isp: data.org || 'Unknown',
                asn: data.asn || 'Unknown',
                accuracy: data.accuracy || 'Unknown'
            };
        } catch (error) {
            console.error('Error getting location data:', error);
            
            // Fallback location data
            return {
                country: 'United States',
                countryCode: 'US',
                region: 'Local',
                regionCode: 'Local',
                city: 'Local',
                zipCode: '00000',
                latitude: null,
                longitude: null,
                timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
                isp: 'Local Development',
                asn: 'Unknown',
                accuracy: 'Unknown'
            };
        }
    }
    
    // Track page visit
    async function trackPageVisit() {
        try {
            const sessionId = getVisitorSession();
            const deviceInfo = await collectDeviceInfo();
            const currentPage = window.location.pathname + window.location.search;
            const referrer = document.referrer || 'Direct';
            const timestamp = new Date().toISOString();
            
            // Get existing visitors
            const existingVisitors = JSON.parse(localStorage.getItem(TRACKING_CONFIG.visitorsKey) || '[]');
            
            // Find existing visitor or create new one
            let visitor = existingVisitors.find(v => v.sessionId === sessionId);
            
            if (visitor) {
                // Update existing visitor
                visitor.lastActivity = timestamp;
                visitor.pageViews = (visitor.pageViews || 1) + 1;
                visitor.currentPage = currentPage;
                visitor.referrer = referrer;
                
                // Update device info if it changed (rare)
                if (JSON.stringify(visitor.deviceInfo) !== JSON.stringify(deviceInfo)) {
                    visitor.deviceInfo = deviceInfo;
                }
            } else {
                // Create new visitor
                visitor = {
                    sessionId: sessionId,
                    deviceInfo: deviceInfo,
                    ipAddress: deviceInfo.ipAddress,
                    location: deviceInfo.location,
                    browser: deviceInfo.browser,
                    os: deviceInfo.os,
                    device: deviceInfo.device,
                    firstVisit: timestamp,
                    lastActivity: timestamp,
                    currentPage: currentPage,
                    referrer: referrer,
                    pageViews: 1,
                    visits: 1
                };
                
                existingVisitors.push(visitor);
            }
            
            // Limit number of stored visitors
            if (existingVisitors.length > TRACKING_CONFIG.maxVisitors) {
                existingVisitors.sort((a, b) => new Date(b.lastActivity) - new Date(a.lastActivity));
                existingVisitors.splice(TRACKING_CONFIG.maxVisitors);
            }
            
            // Save to localStorage
            localStorage.setItem(TRACKING_CONFIG.visitorsKey, JSON.stringify(existingVisitors));
            
            console.log('Page visit tracked:', {
                sessionId: sessionId,
                page: currentPage,
                referrer: referrer,
                totalVisitors: existingVisitors.length
            });
            
        } catch (error) {
            console.error('Error tracking page visit:', error);
        }
    }
    
    // Heartbeat to keep session alive
    function startHeartbeat() {
        setInterval(() => {
            const sessionId = getVisitorSession();
            const existingVisitors = JSON.parse(localStorage.getItem(TRACKING_CONFIG.visitorsKey) || '[]');
            const visitor = existingVisitors.find(v => v.sessionId === sessionId);
            
            if (visitor) {
                visitor.lastActivity = new Date().toISOString();
                localStorage.setItem(TRACKING_CONFIG.visitorsKey, JSON.stringify(existingVisitors));
            }
        }, TRACKING_CONFIG.heartbeatInterval);
    }
    
    // Track page visibility changes
    function trackVisibilityChanges() {
        document.addEventListener('visibilitychange', () => {
            if (!document.hidden) {
                // Page became visible, update activity
                const sessionId = getVisitorSession();
                const existingVisitors = JSON.parse(localStorage.getItem(TRACKING_CONFIG.visitorsKey) || '[]');
                const visitor = existingVisitors.find(v => v.sessionId === sessionId);
                
                if (visitor) {
                    visitor.lastActivity = new Date().toISOString();
                    localStorage.setItem(TRACKING_CONFIG.visitorsKey, JSON.stringify(existingVisitors));
                }
            }
        });
    }
    
    // Track page unload
    function trackPageUnload() {
        window.addEventListener('beforeunload', () => {
            const sessionId = getVisitorSession();
            const existingVisitors = JSON.parse(localStorage.getItem(TRACKING_CONFIG.visitorsKey) || '[]');
            const visitor = existingVisitors.find(v => v.sessionId === sessionId);
            
            if (visitor) {
                visitor.lastActivity = new Date().toISOString();
                localStorage.setItem(TRACKING_CONFIG.visitorsKey, JSON.stringify(existingVisitors));
            }
        });
    }
    
    // Initialize tracking
    function initTracking() {
        // Wait for page to load
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', trackPageVisit);
        } else {
            trackPageVisit();
        }
        
        // Start heartbeat
        startHeartbeat();
        
        // Track visibility changes
        trackVisibilityChanges();
        
        // Track page unload
        trackPageUnload();
        
        console.log('Nebula Creative visitor tracking initialized');
    }
    
    // Start tracking
    initTracking();
    
})();
