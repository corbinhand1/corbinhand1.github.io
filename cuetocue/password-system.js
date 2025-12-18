/**
 * Password Protection System
 * Professional password overlay for Cue to Cue Viewer
 * 
 * FEATURES:
 * - Non-invasive overlay that preserves all existing functionality
 * - Professional styling matching the dark theme
 * - Session management with timeout
 * - Rate limiting and lockout protection
 * - Graceful degradation if system fails
 */

class PasswordSystem {
    constructor() {
        this.isAuthenticated = false;
        this.sessionStart = null;
        this.overlay = null;
        this.initCallback = null;
    }
    
    loadCustomSettings() {
        try {
            const settings = JSON.parse(localStorage.getItem('cuetocue_settings') || '{}');
            
            // Update PASSWORD_CONFIG with custom settings
            if (settings.viewerPasswordHash) {
                PASSWORD_CONFIG.viewerPassword = settings.viewerPasswordHash;
            }
            
            if (settings.sessionTimeoutHours) {
                PASSWORD_CONFIG.sessionTimeout = settings.sessionTimeoutHours * 60 * 60 * 1000; // Convert to milliseconds
            }
            
            if (settings.maxAttempts) {
                PASSWORD_CONFIG.maxAttempts = settings.maxAttempts;
            }
            
            console.log('Custom settings loaded:', {
                hasCustomPassword: !!settings.viewerPasswordHash,
                sessionTimeoutHours: settings.sessionTimeoutHours || 12,
                maxAttempts: settings.maxAttempts || 5
            });
            
        } catch (error) {
            console.error('Error loading custom settings:', error);
        }
    }
    
    async init(callback) {
        this.initCallback = callback;
        try {
            // Load custom settings from localStorage
            this.loadCustomSettings();
            
            // Check if already authenticated
            if (isSessionValid()) {
                this.showContent();
                return;
            }
            
            // Check if user is locked out
            if (isLockedOut()) {
                this.showLockoutMessage();
                return;
            }
            
            // Show password prompt
            this.createPasswordOverlay();
            
        } catch (error) {
            console.error('Password system initialization error:', error);
            // Graceful degradation - show content if password system fails
            this.showContent();
        }
    }
    
    createPasswordOverlay() {
        // Create overlay HTML
        const overlayHTML = `
            <div id="passwordOverlay" class="password-overlay">
                <div class="password-prompt">
                    <div class="password-header">
                        <h2>🔒 Cue to Cue Viewer</h2>
                        <p>Enter password to access</p>
                    </div>
                    <div class="password-form">
                        <input type="password" id="passwordInput" placeholder="Password" autocomplete="current-password">
                        <div class="password-toggle">
                            <input type="checkbox" id="showPasswordToggle">
                            <label for="showPasswordToggle">Show password</label>
                        </div>
                        <button id="passwordSubmit" type="button">Enter</button>
                    </div>
                    <div id="passwordError" class="error-message"></div>
                    <div class="password-footer">
                        <small>Session expires in 12 hours</small>
                    </div>
                </div>
            </div>
        `;
        
        // Add overlay to page
        document.body.insertAdjacentHTML('afterbegin', overlayHTML);
        this.overlay = document.getElementById('passwordOverlay');
        
        // Add event listeners
        this.setupEventListeners();
        
        // Add CSS styles
        this.addPasswordStyles();
    }
    
    addPasswordStyles() {
        const styles = `
            <style id="passwordStyles">
                .password-overlay {
                    position: fixed;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    background: rgba(18, 18, 18, 0.98);
                    backdrop-filter: blur(10px);
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    z-index: 10000;
                    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                }
                
                .password-prompt {
                    background: rgba(255, 255, 255, 0.05);
                    border: 1px solid rgba(255, 255, 255, 0.1);
                    border-radius: 16px;
                    padding: 40px;
                    max-width: 400px;
                    width: 90%;
                    text-align: center;
                    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
                }
                
                .password-header h2 {
                    color: #ffffff;
                    font-size: 1.8rem;
                    font-weight: 600;
                    margin: 0 0 8px 0;
                }
                
                .password-header p {
                    color: #b0b0b0;
                    font-size: 1rem;
                    margin: 0 0 30px 0;
                }
                
                .password-form {
                    display: flex;
                    flex-direction: column;
                    gap: 16px;
                    margin-bottom: 20px;
                }
                
                .password-form input {
                    padding: 16px;
                    border: 1px solid rgba(255, 255, 255, 0.2);
                    border-radius: 8px;
                    background: rgba(255, 255, 255, 0.05);
                    color: #ffffff;
                    font-size: 16px;
                    font-family: inherit;
                    transition: border-color 0.3s ease;
                }
                
                .password-form input:focus {
                    outline: none;
                    border-color: #4CAF50;
                    box-shadow: 0 0 0 2px rgba(76, 175, 80, 0.2);
                }
                
                .password-form input::placeholder {
                    color: #666;
                }
                
                .password-form button {
                    padding: 16px;
                    background: #4CAF50;
                    color: white;
                    border: none;
                    border-radius: 8px;
                    font-size: 16px;
                    font-weight: 600;
                    cursor: pointer;
                    transition: background-color 0.3s ease;
                    font-family: inherit;
                }
                
                .password-form button:hover {
                    background: #45a049;
                }
                
                .password-form button:active {
                    transform: translateY(1px);
                }
                
                .password-toggle {
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    margin: 8px 0;
                }
                
                .password-toggle input[type="checkbox"] {
                    width: 16px;
                    height: 16px;
                    margin: 0;
                }
                
                .password-toggle label {
                    color: #b0b0b0;
                    font-size: 0.9rem;
                    cursor: pointer;
                    user-select: none;
                }
                
                .password-toggle label:hover {
                    color: #ffffff;
                }
                
                .error-message {
                    color: #ff6b6b;
                    font-size: 14px;
                    margin-top: 10px;
                    min-height: 20px;
                }
                
                .password-footer {
                    margin-top: 20px;
                }
                
                .password-footer small {
                    color: #666;
                    font-size: 12px;
                }
                
                /* Mobile responsive */
                @media (max-width: 480px) {
                    .password-prompt {
                        padding: 30px 20px;
                        margin: 20px;
                    }
                    
                    .password-header h2 {
                        font-size: 1.5rem;
                    }
                    
                    .password-form input,
                    .password-form button {
                        padding: 14px;
                    }
                }
            </style>
        `;
        
        document.head.insertAdjacentHTML('beforeend', styles);
    }
    
    setupEventListeners() {
        const passwordInput = document.getElementById('passwordInput');
        const passwordSubmit = document.getElementById('passwordSubmit');
        const showPasswordToggle = document.getElementById('showPasswordToggle');
        
        // Password visibility toggle
        showPasswordToggle.addEventListener('change', () => {
            passwordInput.type = showPasswordToggle.checked ? 'text' : 'password';
        });
        
        // Enter key submission
        passwordInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                this.handlePasswordSubmit();
            }
        });
        
        // Button click submission
        passwordSubmit.addEventListener('click', () => {
            this.handlePasswordSubmit();
        });
        
        // Focus on input when overlay loads
        setTimeout(() => {
            passwordInput.focus();
        }, 100);
    }
    
    async handlePasswordSubmit() {
        const passwordInput = document.getElementById('passwordInput');
        const passwordError = document.getElementById('passwordError');
        const password = passwordInput.value.trim();
        
        if (!password) {
            this.showError('Please enter a password');
            return;
        }
        
        try {
            // Hash the entered password
            const hashedPassword = await hashPassword(password);
            
            // Check against stored hash (custom settings take precedence)
            if (hashedPassword === PASSWORD_CONFIG.viewerPassword) {
                // Success - clear failed attempts and create session
                clearFailedAttempts();
                createSession();
                this.showContent();
            } else {
                // Failed - record attempt and show error
                recordFailedAttempt();
                this.showError('Incorrect password');
                passwordInput.value = '';
                passwordInput.focus();
            }
            
        } catch (error) {
            console.error('Password validation error:', error);
            this.showError('Authentication error. Please try again.');
        }
    }
    
    showError(message) {
        const passwordError = document.getElementById('passwordError');
        passwordError.textContent = message;
        
        // Clear error after 3 seconds
        setTimeout(() => {
            passwordError.textContent = '';
        }, 3000);
    }
    
    showLockoutMessage() {
        const lockoutData = localStorage.getItem(PASSWORD_CONFIG.lockoutKey);
        const lockout = JSON.parse(lockoutData);
        const remainingTime = Math.ceil((lockout.until - Date.now()) / 1000 / 60);
        
        const overlayHTML = `
            <div id="passwordOverlay" class="password-overlay">
                <div class="password-prompt">
                    <div class="password-header">
                        <h2>🔒 Account Locked</h2>
                        <p>Too many failed attempts</p>
                    </div>
                    <div class="password-footer">
                        <p>Please wait ${remainingTime} minutes before trying again</p>
                        <button onclick="location.reload()" style="margin-top: 20px; padding: 12px 24px; background: #666; color: white; border: none; border-radius: 6px; cursor: pointer;">Refresh</button>
                    </div>
                </div>
            </div>
        `;
        
        document.body.insertAdjacentHTML('afterbegin', overlayHTML);
    }
    
    showContent() {
        // Hide password overlay
        if (this.overlay) {
            this.overlay.style.display = 'none';
        }
        
        // Show main content
        const mainContent = document.getElementById('mainContent');
        if (mainContent) {
            mainContent.style.display = 'block';
        }
        
        // Initialize CueToCueViewer using the callback
        if (this.initCallback) {
            try {
                this.initCallback();
            } catch (error) {
                console.error('Error initializing CueToCueViewer:', error);
            }
        }
        
        this.isAuthenticated = true;
    }
    
    // Public method to logout
    logout() {
        clearSession();
        location.reload();
    }
}

// Password system is initialized manually in index.html
