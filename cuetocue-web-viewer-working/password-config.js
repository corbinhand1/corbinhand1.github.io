/**
 * Password Configuration System
 * Professional password management for Cue to Cue Viewer
 * 
 * SECURITY NOTES:
 * - Passwords are hashed with SHA-256 + salt
 * - Session management with timeout
 * - Rate limiting to prevent brute force
 * - Graceful degradation if system fails
 */

const PASSWORD_CONFIG = {
    // SHA-256 hashes with salt for security
    viewerPassword: "2a142dddf2bfac0df9bf023dc939b4b9534e4588d3bfa36771c3281453d29338", // "KeynoteEvents"
    adminPassword: "191ee6ac91907b3f6b8016b39925c6968926e04d0f9c61d40da7f568dd6ae6e7", // "admin123"
    
    // Session management
    sessionTimeout: 12 * 60 * 60 * 1000, // 12 hours in milliseconds
    sessionKey: 'cuetocue_session',
    
    // Security settings
    maxAttempts: 5,
    lockoutTime: 15 * 60 * 1000, // 15 minutes
    attemptsKey: 'cuetocue_attempts',
    lockoutKey: 'cuetocue_lockout'
};

/**
 * Professional password hashing function
 * Uses SHA-256 with salt for security
 */
async function hashPassword(password) {
    try {
        const encoder = new TextEncoder();
        const data = encoder.encode(password + 'salt');
        const hashBuffer = await crypto.subtle.digest('SHA-256', data);
        const hashArray = Array.from(new Uint8Array(hashBuffer));
        return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
    } catch (error) {
        console.error('Password hashing error:', error);
        // Fallback to simple hash if crypto.subtle is not available
        return btoa(password + 'salt');
    }
}

/**
 * Check if user is currently locked out
 */
function isLockedOut() {
    const lockoutData = localStorage.getItem(PASSWORD_CONFIG.lockoutKey);
    if (!lockoutData) return false;
    
    const lockout = JSON.parse(lockoutData);
    const now = Date.now();
    
    if (now > lockout.until) {
        // Lockout expired, clear it
        localStorage.removeItem(PASSWORD_CONFIG.lockoutKey);
        localStorage.removeItem(PASSWORD_CONFIG.attemptsKey);
        return false;
    }
    
    return true;
}

/**
 * Record failed login attempt
 */
function recordFailedAttempt() {
    const attemptsData = localStorage.getItem(PASSWORD_CONFIG.attemptsKey);
    let attempts = attemptsData ? JSON.parse(attemptsData) : { count: 0, firstAttempt: Date.now() };
    
    attempts.count++;
    
    if (attempts.count >= PASSWORD_CONFIG.maxAttempts) {
        // Lock out user
        const lockout = {
            until: Date.now() + PASSWORD_CONFIG.lockoutTime
        };
        localStorage.setItem(PASSWORD_CONFIG.lockoutKey, JSON.stringify(lockout));
    }
    
    localStorage.setItem(PASSWORD_CONFIG.attemptsKey, JSON.stringify(attempts));
}

/**
 * Clear failed attempts on successful login
 */
function clearFailedAttempts() {
    localStorage.removeItem(PASSWORD_CONFIG.attemptsKey);
    localStorage.removeItem(PASSWORD_CONFIG.lockoutKey);
}

/**
 * Check if session is still valid
 */
function isSessionValid() {
    const sessionData = localStorage.getItem(PASSWORD_CONFIG.sessionKey);
    if (!sessionData) return false;
    
    const session = JSON.parse(sessionData);
    const now = Date.now();
    
    if (now > session.expires) {
        // Session expired
        localStorage.removeItem(PASSWORD_CONFIG.sessionKey);
        return false;
    }
    
    return true;
}

/**
 * Create new session
 */
function createSession() {
    const session = {
        created: Date.now(),
        expires: Date.now() + PASSWORD_CONFIG.sessionTimeout
    };
    localStorage.setItem(PASSWORD_CONFIG.sessionKey, JSON.stringify(session));
}

/**
 * Clear session
 */
function clearSession() {
    localStorage.removeItem(PASSWORD_CONFIG.sessionKey);
}

// Export for use in other files
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        PASSWORD_CONFIG,
        hashPassword,
        isLockedOut,
        recordFailedAttempt,
        clearFailedAttempts,
        isSessionValid,
        createSession,
        clearSession
    };
}
