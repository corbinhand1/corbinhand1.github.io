/**
 * Nebula Creative Site Admin Configuration
 * Password management for site-wide analytics dashboard
 */

const ADMIN_CONFIG = {
    // SHA-256 hash of admin password (default: "nebula2024")
    adminPassword: "feb1309f32e2ae98e20fcebea40c43e24fe1e961d917bafd62ea5ca3ad901f0c", // "nebula2024"
    
    // Session management
    sessionTimeout: 24 * 60 * 60 * 1000, // 24 hours in milliseconds
    sessionKey: 'nebula_admin_session',
    
    // Data management
    visitorsKey: 'nebula_visitors',
    maxVisitors: 10000, // Maximum number of visitors to store
    visitorRetentionDays: 30 // Days to keep visitor data
};

/**
 * Professional password hashing function
 * Uses SHA-256 with salt for security
 */
async function hashPassword(password) {
    try {
        const encoder = new TextEncoder();
        const data = encoder.encode(password + 'nebula_salt');
        const hashBuffer = await crypto.subtle.digest('SHA-256', data);
        const hashArray = Array.from(new Uint8Array(hashBuffer));
        return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
    } catch (error) {
        console.error('Password hashing error:', error);
        // Fallback to simple hash if crypto.subtle is not available
        return btoa(password + 'nebula_salt');
    }
}

/**
 * Check if admin session is still valid
 */
function isAdminSessionValid() {
    const sessionData = localStorage.getItem(ADMIN_CONFIG.sessionKey);
    if (!sessionData) return false;
    
    const session = JSON.parse(sessionData);
    const now = Date.now();
    
    if (now > session.expires) {
        // Session expired
        localStorage.removeItem(ADMIN_CONFIG.sessionKey);
        return false;
    }
    
    return true;
}

/**
 * Create new admin session
 */
function createAdminSession() {
    const session = {
        created: Date.now(),
        expires: Date.now() + ADMIN_CONFIG.sessionTimeout
    };
    localStorage.setItem(ADMIN_CONFIG.sessionKey, JSON.stringify(session));
}

/**
 * Clear admin session
 */
function clearAdminSession() {
    localStorage.removeItem(ADMIN_CONFIG.sessionKey);
}

// Export for use in other files
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        ADMIN_CONFIG,
        hashPassword,
        isAdminSessionValid,
        createAdminSession,
        clearAdminSession
    };
}
