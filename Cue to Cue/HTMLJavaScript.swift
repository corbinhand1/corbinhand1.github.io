//
//  HTMLJavaScript.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 9/1/24.
//

import Foundation

struct HTMLJavaScript {
    static let content = """
        // State
        const state = {
            autoScrollEnabled: true,
            columnVisibility: {},
            columnWidths: {},
            columns: [],
            data: null,
            resizing: null,
            connectionStatus: 'disconnected',
            connectionAttempts: 0,
            connectionTimer: null,
            colorOverrides: {},
            originalHighlightColors: [],
            lastHighlightColorsStructure: null,
            colorOverrideUpdateTimer: null,
            // Authentication state
            authToken: null,
            currentUser: null,
            userPermissions: [],
            isAuthenticated: false,
            // Editing state
            isEditing: false,
            editingCell: null,
            // Track recently edited cells to prevent overwriting
            recentlyEditedCells: new Map(),
            lastEditTime: 0
        };

        // Cookie Management
        function loadSettings() {
            const cookie = document.cookie.match(/(?:^|; )cueSettings=([^;]+)/);
            if (!cookie) return;
            try {
                const settings = JSON.parse(decodeURIComponent(cookie[1]));
                state.columnVisibility = settings.columnVisibility || {};
                state.columnWidths = settings.columnWidths || {};
                state.colorOverrides = settings.colorOverrides || {};
            } catch(e) {
                console.error("Failed to load settings:", e);
            }
        }

        function saveSettings() {
            const settings = {
                columnVisibility: state.columnVisibility,
                columnWidths: state.columnWidths,
                colorOverrides: state.colorOverrides
            };
            document.cookie = `cueSettings=${encodeURIComponent(JSON.stringify(settings))}; path=/; max-age=${60*60*24*365}`;
        }

        // Authentication Functions
        function loadAuthToken() {
            const token = localStorage.getItem('authToken');
            if (token) {
                state.authToken = token;
                state.isAuthenticated = true;
                updateAuthUI();
                fetchUserInfo();
                fetchUserPermissions(); // Also fetch permissions when loading saved token
                // Ensure table is refreshed after permissions are loaded
                setTimeout(() => {
                    refreshTableEditability();
                }, 100);
            }
        }

        function saveAuthToken(token) {
            localStorage.setItem('authToken', token);
            state.authToken = token;
            state.isAuthenticated = true;
        }

        function clearAuthToken() {
            localStorage.removeItem('authToken');
            state.authToken = null;
            state.isAuthenticated = false;
            state.currentUser = null;
            state.userPermissions = [];
            updateAuthUI();
        }

        async function login(username, password) {
            // Show loading state
            const submitButton = document.getElementById('submitLogin');
            const originalText = submitButton.textContent;
            submitButton.textContent = 'Logging in...';
            submitButton.disabled = true;
            
            try {
                
                const response = await fetch('/auth/login', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({ username, password })
                });

                const data = await response.json();
                
                if (response.ok && data.success && data.token) {
                    saveAuthToken(data.token);
                    state.currentUser = data.user;
                    updateAuthUI();
                    hideLoginModal();
                    // Fetch permissions and refresh table editability
                    try {
                        await fetchUserPermissions();
                        // Double-check that permissions are loaded and refresh table
                        setTimeout(() => {
                            refreshTableEditability();
                        }, 200);
                    } catch (error) {
                        console.error('Error loading permissions after login:', error);
                    }
                    return true;
                } else {
                    // Handle different error types
                    let errorMessage = 'Login failed';
                    if (response.status === 401) {
                        errorMessage = 'Invalid username or password';
                    } else if (response.status === 429) {
                        errorMessage = 'Too many login attempts. Please try again later.';
                    } else if (response.status >= 500) {
                        errorMessage = 'Server error. Please try again later.';
                    } else if (data.message) {
                        errorMessage = data.message;
                    }
                    showLoginError(errorMessage);
                    return false;
                }
            } catch (error) {
                console.error('Login error:', error);
                let errorMessage = 'Network error. Please check your connection and try again.';
                
                if (error.name === 'TypeError' && error.message.includes('fetch')) {
                    errorMessage = 'Cannot connect to server. Please check your connection.';
                } else if (error.name === 'AbortError') {
                    errorMessage = 'Request timed out. Please try again.';
                }
                
                showLoginError(errorMessage);
                return false;
            } finally {
                // Restore button state
                const submitButton = document.getElementById('submitLogin');
                submitButton.textContent = originalText;
                submitButton.disabled = false;
            }
        }

        async function logout() {
            try {
                if (state.authToken) {
                    await fetch('/auth/logout', {
                        method: 'POST',
                        headers: {
                            'Authorization': `Bearer ${state.authToken}`
                        }
                    });
                }
            } catch (error) {
                console.error('Logout error:', error);
            } finally {
                clearAuthToken();
            }
        }

        async function fetchUserInfo() {
            if (!state.authToken) {
                return;
            }
            
            try {
                const response = await fetch('/auth/me', {
                    headers: {
                        'Authorization': `Bearer ${state.authToken}`
                    }
                });

                if (response.ok) {
                    const userData = await response.json();
                    state.currentUser = userData;
                    updateAuthUI();
                } else if (response.status === 401) {
                    console.log("🔍 Token expired, clearing auth");
                    // Token expired, clear it
                    clearAuthToken();
                } else {
                    console.warn('Failed to fetch user info:', response.status);
                }
            } catch (error) {
                console.error('Error fetching user info:', error);
                // Don't clear token on network errors, just log
            }
        }

        async function fetchUserPermissions() {
            if (!state.authToken) {
                return;
            }
            
            try {
                const response = await fetch('/auth/permissions', {
                    headers: {
                        'Authorization': `Bearer ${state.authToken}`
                    }
                });

                if (response.ok) {
                    const permissions = await response.json();
                    state.userPermissions = permissions;
                    console.log("✅ User permissions loaded");
                    updateTablePermissions();
                    // Also refresh the table to make cells editable
                    refreshTableEditability();
                } else if (response.status === 401) {
                    console.log("🔍 Token expired, clearing auth");
                    // Token expired, clear it
                    clearAuthToken();
                } else {
                    console.warn('Failed to fetch permissions:', response.status);
                }
            } catch (error) {
                console.error('Error fetching permissions:', error);
                // Don't clear token on network errors, just log
            }
        }

        function updateAuthUI() {
            const userInfo = document.getElementById('userInfo');
            const loginButton = document.getElementById('loginButton');
            const logoutButton = document.getElementById('logoutButton');

            if (state.isAuthenticated && state.currentUser) {
                userInfo.textContent = `Logged in as: ${state.currentUser.username}${state.currentUser.isAdmin ? ' (Admin)' : ''}`;
                loginButton.style.display = 'none';
                logoutButton.style.display = 'inline-block';
            } else {
                userInfo.textContent = 'Not logged in';
                loginButton.style.display = 'inline-block';
                logoutButton.style.display = 'none';
            }
        }

        function showLoginModal() {
            document.getElementById('loginModal').classList.add('show');
            document.getElementById('loginOverlay').classList.add('show');
        }

        function hideLoginModal() {
            document.getElementById('loginModal').classList.remove('show');
            document.getElementById('loginOverlay').classList.remove('show');
            document.getElementById('loginError').style.display = 'none';
            document.getElementById('loginForm').reset();
        }

        function showLoginError(message) {
            const errorDiv = document.getElementById('loginError');
            errorDiv.textContent = message;
            errorDiv.style.display = 'block';
        }

        function canUserEditColumn(columnIndex) {
            // Must be authenticated and have data
            if (!state.isAuthenticated || !state.data) {
                return false;
            }
            
            // Admin users can edit all columns
            if (state.currentUser && state.currentUser.isAdmin) {
                return true;
            }
            
            // Get column name from index
            if (columnIndex >= state.data.columns.length) {
                return false;
            }
            
            const columnName = state.data.columns[columnIndex].name;
            
            // Check user permissions for current cue stack using cueStackId
            const currentCueStackId = state.data.cueStackId;
            if (!currentCueStackId) {
                return false;
            }
            
            const permission = state.userPermissions.find(p => p.cueStackId === currentCueStackId);
            if (!permission) {
                return false;
            }
            
            // Check if user can edit this column by name
            const canEditByName = permission.allowedColumns.includes(columnName);
            
            // Check legacy index-based permissions for backward compatibility
            let canEditByIndex = false;
            if (permission.allowedColumnIndices && permission.allowedColumnIndices.includes(columnIndex)) {
                canEditByIndex = true;
            }
            
            return canEditByName || canEditByIndex;
        }

        function updateTablePermissions() {
            // This will be called after table is built to add edit indicators
            if (state.data && state.data.cues) {
                const tbody = document.querySelector('#cueTable tbody');
                if (tbody) {
                    const rows = tbody.querySelectorAll('tr');
                    rows.forEach((row, rowIndex) => {
                        const cells = row.querySelectorAll('td');
                        cells.forEach((cell, cellIndex) => {
                            if (cellIndex < state.data.columns.length) { // Skip timer column
                                const shouldBeEditable = canUserEditColumn(cellIndex);
                                
                                if (shouldBeEditable) {
                                    cell.classList.add('editable-cell');
                                    cell.classList.remove('readonly-cell');
                                } else {
                                    cell.classList.add('readonly-cell');
                                    cell.classList.remove('editable-cell');
                                }
                            }
                        });
                    });
                }
            }
        }

        function refreshTableEditability() {
            // Refresh the editability of all cells after permissions are loaded
            if (state.data && state.data.cues) {
                const tbody = document.querySelector('#cueTable tbody');
                if (tbody) {
                    const rows = tbody.querySelectorAll('tr');
                    rows.forEach((row, rowIndex) => {
                        const cells = row.querySelectorAll('td');
                        cells.forEach((cell, cellIndex) => {
                            if (cellIndex < state.data.columns.length) { // Skip timer column
                                // Get the cue ID for this row
                                const cue = state.data.cues[rowIndex];
                                if (cue) {
                                    // Remove existing event listeners by cloning the cell
                                    const newCell = cell.cloneNode(true);
                                    cell.parentNode.replaceChild(newCell, cell);
                                    
                                    // Make the new cell editable
                                    makeCellEditable(newCell, cue.id, cellIndex);
                                    
                                    // Update visual indicators
                                    const shouldBeEditable = canUserEditColumn(cellIndex);
                                    if (shouldBeEditable) {
                                        newCell.classList.add('editable-cell');
                                        newCell.classList.remove('readonly-cell');
                                    } else {
                                        newCell.classList.add('readonly-cell');
                                        newCell.classList.remove('editable-cell');
                                    }
                                }
                            }
                        });
                    });
                }
            }
        }

        // Cell Editing Functions
        function makeCellEditable(cell, cueId, columnIndex) {
            // Always add the click listener, but check permissions when clicked
            cell.addEventListener('click', () => {
                // Check permissions at click time, not setup time
                if (!canUserEditColumn(columnIndex)) {
                    return;
                }
                
                // Set editing state
                state.isEditing = true;
                state.editingCell = cell;
                
                const originalValue = cell.textContent;
                const input = document.createElement('input');
                input.type = 'text';
                input.value = originalValue;
                input.style.width = '100%';
                input.style.border = 'none';
                input.style.background = 'transparent';
                input.style.color = 'inherit';
                input.style.font = 'inherit';
                
                cell.innerHTML = '';
                cell.appendChild(input);
                input.focus();
                input.select();
                
                const finishEdit = async () => {
                    // Clear editing state
                    state.isEditing = false;
                    state.editingCell = null;
                    
                    const newValue = input.value.trim();
                    if (newValue !== originalValue) {
                        await updateCueValue(cueId, columnIndex, newValue);
                    }
                    cell.textContent = newValue || originalValue;
                };
                
                const cancelEdit = () => {
                    // Clear editing state
                    state.isEditing = false;
                    state.editingCell = null;
                    
                    cell.textContent = originalValue;
                };
                
                input.addEventListener('blur', finishEdit);
                input.addEventListener('keydown', (e) => {
                    if (e.key === 'Enter') {
                        e.preventDefault();
                        finishEdit();
                    } else if (e.key === 'Escape') {
                        e.preventDefault();
                        cancelEdit();
                    }
                });
            });
        }

        async function updateCueValue(cueId, columnIndex, newValue) {
            console.log('💾 Saving:', { cueId, columnIndex, newValue });
            
            // Double-check permissions before sending request
            if (!canUserEditColumn(columnIndex)) {
                const errorMessage = 'You do not have permission to edit this column.';
                console.error('❌ Permission denied:', errorMessage);
                showNotification(errorMessage, 'error');
                return;
            }
            
            try {
                const response = await authenticatedFetch(`/cues/${cueId}`, {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        cueId: cueId,
                        columnIndex: columnIndex,
                        newValue: newValue
                    })
                });

                console.log('💾 Response status:', response.status);
                console.log('💾 Response ok:', response.ok);

                if (!response.ok) {
                    const errorData = await response.json();
                    console.log('💾 Error response:', errorData);
                    let errorMessage = 'Failed to update cue';
                    
                    if (response.status === 401) {
                        errorMessage = 'Session expired. Please log in again.';
                        clearAuthToken();
                        showLoginModal();
                    } else if (response.status === 403) {
                        errorMessage = 'You do not have permission to edit this column.';
                    } else if (response.status === 404) {
                        errorMessage = 'Cue not found. It may have been deleted.';
                    } else if (response.status >= 500) {
                        errorMessage = 'Server error. Please try again later.';
                    } else if (errorData.message) {
                        errorMessage = errorData.message;
                    }
                    
                    throw new Error(errorMessage);
                }
                
                const responseData = await response.json();
                console.log('💾 Response data:', responseData);
                console.log('✅ Save successful!');
                
                // Track this cell as recently edited to prevent overwriting
                const cellKey = `${cueId}-${columnIndex}`;
                state.recentlyEditedCells.set(cellKey, {
                    value: newValue,
                    timestamp: Date.now()
                });
                state.lastEditTime = Date.now();
                
                // Show success notification
                showNotification('Cue updated successfully', 'success');
                
                // Wait a moment before refreshing to ensure backend has processed the change
                setTimeout(() => {
                    fetchCues();
                }, 100);
                
            } catch (error) {
                console.error('❌ Save failed:', error.message);
                showNotification(error.message, 'error');
            }
        }

        // Notification System
        function showNotification(message, type = 'info') {
            // Create notification element
            const notification = document.createElement('div');
            notification.className = `notification notification-${type}`;
            notification.textContent = message;
            
            // Add styles
            notification.style.cssText = `
                position: fixed;
                top: 20px;
                right: 20px;
                padding: 12px 20px;
                border-radius: 8px;
                color: white;
                font-size: 14px;
                font-weight: 500;
                z-index: 10001;
                max-width: 300px;
                box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
                transform: translateX(100%);
                transition: transform 0.3s ease;
            `;
            
            // Set background color based on type
            switch (type) {
                case 'error':
                    notification.style.backgroundColor = '#ff4444';
                    break;
                case 'success':
                    notification.style.backgroundColor = '#00aa44';
                    break;
                case 'warning':
                    notification.style.backgroundColor = '#ffaa00';
                    break;
                default:
                    notification.style.backgroundColor = '#007AFF';
            }
            
            // Add to DOM
            document.body.appendChild(notification);
            
            // Animate in
            setTimeout(() => {
                notification.style.transform = 'translateX(0)';
            }, 10);
            
            // Auto remove after 5 seconds
            setTimeout(() => {
                notification.style.transform = 'translateX(100%)';
                setTimeout(() => {
                    if (notification.parentNode) {
                        notification.parentNode.removeChild(notification);
                    }
                }, 300);
            }, 5000);
        }

        // Retry mechanism for authentication requests
        async function retryRequest(requestFn, maxRetries = 3, delay = 1000) {
            for (let attempt = 1; attempt <= maxRetries; attempt++) {
                try {
                    return await requestFn();
                } catch (error) {
                    console.warn(`Request attempt ${attempt} failed:`, error);
                    
                    if (attempt === maxRetries) {
                        throw error;
                    }
                    
                    // Wait before retrying
                    await new Promise(resolve => setTimeout(resolve, delay * attempt));
                }
            }
        }

        // Token refresh logic
        function isTokenExpired(token) {
            try {
                // For UUID-based tokens, we'll check with the server
                // This is a simple implementation - in production you might want to decode JWT tokens
                return false; // Let the server handle expiration
            } catch (error) {
                return true;
            }
        }

        async function refreshTokenIfNeeded() {
            if (!state.authToken) return false;
            
            try {
                // Try to fetch user info to check if token is still valid
                const response = await fetch('/auth/me', {
                    headers: {
                        'Authorization': `Bearer ${state.authToken}`
                    }
                });
                
                if (response.ok) {
                    return true; // Token is still valid
                } else if (response.status === 401) {
                    // Token expired, clear it
                    clearAuthToken();
                    return false;
                }
                
                return true; // Other errors, assume token is still valid
            } catch (error) {
                console.warn('Token validation failed:', error);
                return true; // Network error, assume token is still valid
            }
        }

        // Enhanced fetch with automatic token refresh
        async function authenticatedFetch(url, options = {}) {
            // Ensure we have a valid token
            const tokenValid = await refreshTokenIfNeeded();
            if (!tokenValid) {
                throw new Error('Authentication required');
            }
            
            // Add authorization header
            const headers = {
                'Authorization': `Bearer ${state.authToken}`,
                ...options.headers
            };
            
            return fetch(url, {
                ...options,
                headers
            });
        }

        // Connection Status Management
        function updateConnectionStatus(status) {
            if (state.connectionStatus === status) return;
            
            // Clear any existing timer
            if (state.connectionTimer) {
                clearTimeout(state.connectionTimer);
                state.connectionTimer = null;
            }
            
            state.connectionStatus = status;
            const statusDot = document.getElementById('statusDot');
            const statusText = document.getElementById('statusText');
            
            // Remove all status classes
            statusDot.classList.remove('connected', 'attempting', 'disconnected');
            
            // Add new status class and update text
            switch (status) {
                case 'connected':
                    statusDot.classList.add('connected');
                    statusText.textContent = 'Connected';
                    state.connectionAttempts = 0;
                    break;
                case 'attempting':
                    statusDot.classList.add('attempting');
                    statusText.textContent = 'Connecting...';
                    break;
                case 'disconnected':
                    statusDot.classList.add('disconnected');
                    statusText.textContent = 'Disconnected. Local Save Only';
                    break;
            }
        }

        // Delayed status update with 5-second delay
        function updateConnectionStatusWithDelay(status, delay = 5000) {
            if (state.connectionStatus === status) return;
            
            // Clear any existing timer
            if (state.connectionTimer) {
                clearTimeout(state.connectionTimer);
                state.connectionTimer = null;
            }
            
            // Set timer for delayed status change
            state.connectionTimer = setTimeout(() => {
                updateConnectionStatus(status);
            }, delay);
        }

        // Robust fetch wrapper to handle network errors gracefully
        async function robustFetch(url, options = {}) {
            try {
                const controller = new AbortController();
                const timeoutId = setTimeout(() => controller.abort(), options.timeout || 5000);
                
                const response = await fetch(url, {
                    ...options,
                    signal: controller.signal
                });
                
                clearTimeout(timeoutId);
                return response;
            } catch (error) {
                // Handle timeout and network errors gracefully
                if (error.name === 'AbortError') {
                    throw new Error('Request timeout');
                }
                throw error;
            }
        }
        
        // Data Fetching
        // Add request deduplication to prevent multiple simultaneous requests
        let activeRequests = new Set();
        
        async function fetchCues() {
            // Skip updates if user is currently editing
            if (state.isEditing) {
                return;
            }
            
            // Clean up old recently edited cells (older than 10 seconds)
            const now = Date.now();
            for (const [key, edit] of state.recentlyEditedCells.entries()) {
                if (now - edit.timestamp > 10000) {
                    state.recentlyEditedCells.delete(key);
                }
            }
            
            // Prevent multiple simultaneous requests
            if (activeRequests.has('cues')) {
                return;
            }
            
            try {
                activeRequests.add('cues');
                
                // Only show "attempting" if we're not already connected
                if (state.connectionStatus !== 'connected') {
                    updateConnectionStatus('attempting');
                }
                
                const response = await robustFetch(`${window.location.origin}/cues`, { timeout: 5000 });
                
                if (!response.ok) throw new Error(response.statusText);
                
                // Check if response has content before parsing
                const text = await response.text();
                if (!text || text.trim() === '') {
                    throw new Error('Empty response received');
                }
                
                // Additional validation - check if it looks like JSON
                if (!text.trim().startsWith('{') && !text.trim().startsWith('[')) {
                    throw new Error('Response is not JSON format');
                }
                
                const data = JSON.parse(text);
                state.data = data;
                console.log("🔍 Cues data received");
                updateUI(data);
                updateConnectionStatus('connected');
                
                // If user is authenticated, refresh table editability after data loads
                if (state.isAuthenticated) {
                    setTimeout(() => {
                        refreshTableEditability();
                    }, 100);
                }
            } catch(err) {
                // Handle different types of errors appropriately
                if (err.name === 'AbortError') {
                    // Request was aborted due to timeout - this is normal
                    return;
                }
                
                // Silently handle other fetch errors - this is normal when offline or server unavailable
                state.connectionAttempts++;
                
                // If we've failed multiple times, show as disconnected
                if (state.connectionAttempts >= 3) {
                    updateConnectionStatus('disconnected');
                } else {
                    // Use delayed status update to prevent jittery behavior
                    // Only show "attempting" after 5 seconds of being connected
                    if (state.connectionStatus === 'connected') {
                        updateConnectionStatusWithDelay('attempting', 5000);
                    } else {
                        updateConnectionStatus('attempting');
                    }
                }
            } finally {
                activeRequests.delete('cues');
            }
        }


        // Handle real-time clock updates from the server
        function handleClockUpdate(data) {
            if (data.action === 'updateClocks') {
                // Handle both old format (direct properties) and new format (nested under 'data' key)
                const clockData = data.data || data;
                
                // Update countdown timer
                if (clockData.countdownTime !== undefined) {
                    const countdownElement = document.getElementById('countdown');
                    if (countdownElement) {
                        countdownElement.textContent = formatTime(clockData.countdownTime);
                    }
                }
                
                // Update countdown to time timer
                if (clockData.countUpTime !== undefined) {
                    const countupElement = document.getElementById('countup');
                    if (countupElement) {
                        countupElement.textContent = formatTime(clockData.countUpTime);
                    }
                }
                
                // Update current time if provided
                if (clockData.currentTime !== undefined) {
                    const currentTimeElement = document.getElementById('current-time');
                    if (currentTimeElement) {
                        const date = new Date(clockData.currentTime * 1000);
                        currentTimeElement.textContent = date.toLocaleTimeString([], {
                            hour: '2-digit', minute: '2-digit', second: '2-digit'
                        });
                    }
                }
            }
        }

        
        // Update countdown timers from server data
        function updateCountdownTimers() {
            if (!state.data) return;
            
            // Update countdown timer
            if (state.data.countdownTime !== undefined) {
                const countdownElement = document.getElementById('countdown');
                if (countdownElement) {
                    countdownElement.textContent = formatTime(state.data.countdownTime);
                }
            }
            
            // Update countdown to time timer
            if (state.data.countUpTime !== undefined) {
                const countupElement = document.getElementById('countup');
                if (countupElement) {
                    countupElement.textContent = formatTime(state.data.countUpTime);
                }
            }
        }
        

        // Parse time string (HH:MM:SS or MM:SS) to seconds
        function parseTimeString(timeString) {
            if (!timeString || typeof timeString !== 'string') return 0;
            
            const parts = timeString.split(':').map(part => parseInt(part, 10) || 0);
            if (parts.length === 2) {
                // MM:SS format
                return parts[0] * 60 + parts[1];
            } else if (parts.length === 3) {
                // HH:MM:SS format
                return parts[0] * 3600 + parts[1] * 60 + parts[2];
            }
            return 0;
        }

        // Format time from seconds to MM:SS or HH:MM:SS
        function formatTime(seconds) {
            if (seconds === undefined || seconds === null) return '00:00';
            
            // Handle both string and number inputs
            if (typeof seconds === 'string') {
                seconds = parseTimeString(seconds);
            }
            
            const isNegative = seconds < 0;
            const absSeconds = Math.abs(seconds);
            const hours = Math.floor(absSeconds / 3600);
            const minutes = Math.floor((absSeconds % 3600) / 60);
            const remainingSeconds = absSeconds % 60;
            
            if (hours > 0) {
                return `${isNegative ? '-' : ''}${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(remainingSeconds).padStart(2, '0')}`;
            } else {
                return `${isNegative ? '-' : ''}${String(minutes).padStart(2, '0')}:${String(remainingSeconds).padStart(2, '0')}`;
            }
        }

        function updateUI(data) {
            updateClocks(data);
            
            // Only rebuild table if structure changed
            if (!state.columns || state.columns.length !== data.columns.length + 1) {
                state.columns = [...data.columns, { name: 'Timer' }];
                initializeSettings();
                buildTable(data);
                updateColumnMenu();
            } else {
                updateTableData(data);
            }
            
            // Update color overrides if highlight colors changed
            if (data.highlightColors) {
                const currentColors = JSON.stringify(data.highlightColors.map(h => ({ keyword: h.keyword, color: h.color })));
                const lastColors = state.lastHighlightColorsStructure;
                
                if (currentColors !== lastColors) {
                    state.lastHighlightColorsStructure = currentColors;
                    
                    // Debounce the update to prevent excessive calls
                    if (state.colorOverrideUpdateTimer) {
                        clearTimeout(state.colorOverrideUpdateTimer);
                    }
                    state.colorOverrideUpdateTimer = setTimeout(() => {
                        updateColorOverrides();
                    }, 100);
                }
            }
            
            handleAutoScroll(data);
            document.getElementById('columnNames').textContent = data.cueStackName || 'Cue Stack';
            
            // Update table permissions after data is loaded
            updateTablePermissions();
        }

        function updateClocks(data) {
            // Handle both old format (direct properties) and new format (nested under 'data' key)
            const clockData = data.data || data;
            
            if (clockData.countdownTime !== undefined) {
                const formattedTime = formatTime(clockData.countdownTime);
                document.getElementById('countdown').textContent = formattedTime;
            }
            if (clockData.countUpTime !== undefined) {
                const formattedTime = formatTime(clockData.countUpTime);
                document.getElementById('countup').textContent = formattedTime;
            }
            const now = new Date();
            document.getElementById('current-time').textContent = now.toLocaleTimeString([], {
                hour: '2-digit', minute: '2-digit', second: '2-digit'
            });
            document.getElementById('current-date').textContent = now.toLocaleDateString();
        }

        // Table Building
        function initializeSettings() {
            state.columns.forEach((col, index) => {
                const colId = `col-${index}`;
                if (!(colId in state.columnVisibility)) {
                    state.columnVisibility[colId] = true;
                }
                if (!(colId in state.columnWidths)) {
                    // Set default widths based on column type
                    if (index === 0) state.columnWidths[colId] = 60;  // # column
                    else if (index === state.columns.length - 1) state.columnWidths[colId] = 100; // Timer
                    else state.columnWidths[colId] = 200; // Content columns
                }
            });
        }

        function buildTable(data) {
            const table = document.getElementById('cueTable');
            const thead = table.querySelector('thead');
            const tbody = table.querySelector('tbody');
            
            // Build header
            thead.innerHTML = '';
            const headerRow = document.createElement('tr');
            
            state.columns.forEach((col, index) => {
                const th = document.createElement('th');
                const colId = `col-${index}`;
                
                th.className = colId;
                th.style.width = state.columnWidths[colId] + 'px';
                th.style.minWidth = state.columnWidths[colId] + 'px';
                th.style.maxWidth = state.columnWidths[colId] + 'px';
                th.textContent = col.name;
                
                if (!state.columnVisibility[colId]) {
                    th.classList.add('hidden');
                }
                
                // Add resizer
                const resizer = document.createElement('div');
                resizer.className = 'resizer';
                resizer.dataset.col = colId;
                resizer.dataset.index = index;
                th.appendChild(resizer);
                
                headerRow.appendChild(th);
            });
            
            thead.appendChild(headerRow);
            
            // Build body
            tbody.innerHTML = '';
            data.cues.forEach((cue, rowIndex) => {
                const row = document.createElement('tr');
                
                if (rowIndex === data.selectedCueIndex) {
                    row.classList.add('selected');
                } else if (rowIndex === data.selectedCueIndex + 1) {
                    row.classList.add('next');
                }
                
                state.columns.forEach((col, colIndex) => {
                    const td = document.createElement('td');
                    const colId = `col-${colIndex}`;
                    
                    td.className = colId;
                    td.style.width = state.columnWidths[colId] + 'px';
                    td.style.minWidth = state.columnWidths[colId] + 'px';
                    td.style.maxWidth = state.columnWidths[colId] + 'px';
                    
                    if (colIndex < data.columns.length) {
                        td.textContent = cue.values[colIndex] || '';
                        const shouldStrike = cue.isStruckThrough;
                        if (shouldStrike) {
                            td.classList.add('struck');
                        }
                        // Make cell editable if user has permission
                        makeCellEditable(td, cue.id, colIndex);
                    } else {
                        // Timer column
                        td.textContent = cue.timerValue || '';
                        td.classList.add('timer-cell');
                    }
                    
                    if (!state.columnVisibility[colId]) {
                        td.classList.add('hidden');
                    }
                    
                    row.appendChild(td);
                });
                
                // Apply row-level highlighting after all cells are added
                applyRowHighlighting(row, cue, data.highlightColors);
                
                tbody.appendChild(row);
            });
            
            attachResizeHandlers();
            saveSettings();
            // Update table permissions after building
            updateTablePermissions();
        }

        function updateTableData(data) {
            const tbody = document.querySelector('#cueTable tbody');
            const rows = tbody.querySelectorAll('tr');
            
            data.cues.forEach((cue, rowIndex) => {
                let row = rows[rowIndex];
                if (!row) {
                    row = document.createElement('tr');
                    tbody.appendChild(row);
                }
                
                // Update row classes
                row.className = '';
                if (rowIndex === data.selectedCueIndex) {
                    row.classList.add('selected');
                } else if (rowIndex === data.selectedCueIndex + 1) {
                    row.classList.add('next');
                }
                
                // Update cells
                state.columns.forEach((col, colIndex) => {
                    let td = row.children[colIndex];
                    if (!td) {
                        td = document.createElement('td');
                        row.appendChild(td);
                    }
                    
                    const colId = `col-${colIndex}`;
                    td.className = colId;
                    td.style.width = state.columnWidths[colId] + 'px';
                    td.style.minWidth = state.columnWidths[colId] + 'px';
                    td.style.maxWidth = state.columnWidths[colId] + 'px';
                    
                    if (colIndex < data.columns.length) {
                        // Check if this cell was recently edited (within last 5 seconds)
                        const cellKey = `${cue.id}-${colIndex}`;
                        const recentEdit = state.recentlyEditedCells.get(cellKey);
                        const now = Date.now();
                        
                        if (recentEdit && (now - recentEdit.timestamp) < 5000) {
                            // Don't overwrite recently edited cells
                            console.log(`🛡️ Preserving recent edit for cell ${cellKey}: ${recentEdit.value}`);
                        } else {
                            // Only update if the content has actually changed
                            const currentContent = td.textContent || '';
                            const newContent = cue.values[colIndex] || '';
                            if (currentContent !== newContent) {
                                td.textContent = newContent;
                            }
                        }
                        
                        const shouldStrike = cue.isStruckThrough;
                        td.classList.toggle('struck', shouldStrike);
                    } else {
                        td.textContent = cue.timerValue || '';
                        td.classList.add('timer-cell');
                    }
                    
                    td.classList.toggle('hidden', !state.columnVisibility[colId]);
                });
                
                // Apply row-level highlighting after all cells are updated
                applyRowHighlighting(row, cue, data.highlightColors);
            });
            
            // Remove extra rows
            while (tbody.children.length > data.cues.length) {
                tbody.removeChild(tbody.lastChild);
            }
        }

        // Column Resizing
        function attachResizeHandlers() {
            document.querySelectorAll('.resizer').forEach(resizer => {
                resizer.addEventListener('mousedown', startResize);
                resizer.addEventListener('touchstart', startResize, { passive: false });
            });
        }

        function startResize(e) {
            e.preventDefault();
            e.stopPropagation();
            
            const resizer = e.currentTarget;
            const colId = resizer.dataset.col;
            const th = resizer.parentElement;
            
            state.resizing = {
                colId: colId,
                startX: e.type.includes('touch') ? e.touches[0].pageX : e.pageX,
                startWidth: th.offsetWidth,
                th: th
            };
            
            document.body.classList.add('resizing');
            resizer.classList.add('active');
            
            const guide = document.getElementById('resizeGuide');
            const rect = th.getBoundingClientRect();
            guide.style.left = (rect.right - 2) + 'px';
            guide.classList.add('active');
            
            document.addEventListener('mousemove', doResize);
            document.addEventListener('mouseup', endResize);
            document.addEventListener('touchmove', doResize, { passive: false });
            document.addEventListener('touchend', endResize);
        }

        function doResize(e) {
            if (!state.resizing) return;
            
            e.preventDefault();
            
            const currentX = e.type.includes('touch') ? e.touches[0].pageX : e.pageX;
            const diff = currentX - state.resizing.startX;
            const newWidth = Math.max(40, state.resizing.startWidth + diff);
            
            // Update guide position
            const guide = document.getElementById('resizeGuide');
            guide.style.left = currentX + 'px';
            
            // Update column width
            const elements = document.querySelectorAll(`.${state.resizing.colId}`);
            elements.forEach(el => {
                el.style.width = newWidth + 'px';
                el.style.minWidth = newWidth + 'px';
                el.style.maxWidth = newWidth + 'px';
            });
            
            state.columnWidths[state.resizing.colId] = newWidth;
        }

        function endResize() {
            if (!state.resizing) return;
            
            document.body.classList.remove('resizing');
            document.querySelector('.resizer.active')?.classList.remove('active');
            document.getElementById('resizeGuide').classList.remove('active');
            
            document.removeEventListener('mousemove', doResize);
            document.removeEventListener('mouseup', endResize);
            document.removeEventListener('touchmove', doResize);
            document.removeEventListener('touchend', endResize);
            
            saveSettings();
            state.resizing = null;
        }

        // Column Visibility
        function updateColumnMenu() {
            const menu = document.getElementById('columnMenu');
            menu.innerHTML = '<h3>Column Visibility</h3><p class="menu-description">Choose which columns to display in the table</p><div class="columns-container"></div>';
            
            const columnsContainer = menu.querySelector('.columns-container');
            
            state.columns.forEach((col, index) => {
                const colId = `col-${index}`;
                
                const label = document.createElement('label');
                const checkbox = document.createElement('input');
                
                checkbox.type = 'checkbox';
                checkbox.checked = state.columnVisibility[colId];
                checkbox.addEventListener('change', (e) => {
                    state.columnVisibility[colId] = e.target.checked;
                    
                    const elements = document.querySelectorAll(`.${colId}`);
                    elements.forEach(el => {
                        el.classList.toggle('hidden', !e.target.checked);
                    });
                    
                    saveSettings();
                });
                
                label.appendChild(checkbox);
                label.appendChild(document.createTextNode(col.name));
                columnsContainer.appendChild(label);
            });
        }

        // Auto Scroll
        function handleAutoScroll(data) {
            if (state.autoScrollEnabled && data.selectedCueIndex != null) {
                const tbody = document.querySelector('#cueTable tbody');
                if (tbody && tbody.children[data.selectedCueIndex]) {
                    tbody.children[data.selectedCueIndex].scrollIntoView({ 
                        behavior: 'smooth', 
                        block: 'center' 
                    });
                }
            }
        }
        
        // Row-level Highlight Color Application
        function applyRowHighlighting(row, cue, highlightColors) {
            if (!highlightColors || !Array.isArray(highlightColors)) {
                return;
            }
            
            // Reset all cell colors in the row first
            const cells = row.querySelectorAll('td');
            cells.forEach(cell => {
                cell.style.color = '';
            });
            
            // Check each cell for highlight keywords and apply row-level highlighting
            for (let colIndex = 0; colIndex < cue.values.length; colIndex++) {
                const cellText = cue.values[colIndex];
                if (!cellText) continue;
                
                for (const highlight of highlightColors) {
                    if (highlight.keyword && highlight.color && 
                        cellText.toLowerCase().includes(highlight.keyword.toLowerCase())) {
                        
                        // Check if user has overridden this color
                        const overrideKey = `${highlight.keyword}_${highlight.color}`;
                        const colorToApply = state.colorOverrides[overrideKey] || highlight.color;
                        
                        // Apply color to all cells in the row
                        cells.forEach(cell => {
                            cell.style.color = '#' + colorToApply;
                        });
                        
                        return; // Exit after first match
                    }
                }
            }
        }
        
        // Highlight Color Application (legacy function - kept for compatibility)
        function applyHighlightColor(td, text, highlightColors) {
            if (!highlightColors || !Array.isArray(highlightColors)) {
                return;
            }
            
            // Reset any existing highlight colors
            td.style.color = '';
            
            // Check if any highlight color should be applied
            for (const highlight of highlightColors) {
                if (highlight.keyword && highlight.color && 
                    text && text.toLowerCase().includes(highlight.keyword.toLowerCase())) {
                    
                    // Check if user has overridden this color
                    const overrideKey = `${highlight.keyword}_${highlight.color}`;
                    const colorToApply = state.colorOverrides[overrideKey] || highlight.color;
                    
                    // Apply color to the entire row instead of just this cell
                    const row = td.closest('tr');
                    if (row) {
                        // Apply color to all cells in the row
                        const cells = row.querySelectorAll('td');
                        cells.forEach(cell => {
                            cell.style.color = '#' + colorToApply;
                        });
                    } else {
                        // Fallback to cell-only highlighting if row not found
                        td.style.color = '#' + colorToApply;
                    }
                    break; // Use the first matching highlight
                }
            }
        }
        
        // Color Override Management
        function updateColorOverrides() {
            if (!state.data || !state.data.highlightColors) return;
            
            // Store original colors if not already stored
            if (state.originalHighlightColors.length === 0) {
                state.originalHighlightColors = [...state.data.highlightColors];
            }
            
            const container = document.getElementById('colorOverridesContainer');
            if (!container) return;
            
            // Only rebuild if the structure has actually changed
            const currentStructure = JSON.stringify(state.data.highlightColors.map(h => ({ keyword: h.keyword, color: h.color })));
            const lastStructure = container.dataset.lastStructure;
            
            if (currentStructure === lastStructure) {
                // Structure hasn't changed, just update values if needed
                updateExistingColorOverrides();
                return;
            }
            
            // Structure has changed, rebuild the panel
            const savedValues = preserveColorPickerState();
            container.innerHTML = '';
            container.dataset.lastStructure = currentStructure;
            
            state.data.highlightColors.forEach(highlight => {
                const overrideKey = `${highlight.keyword}_${highlight.color}`;
                const currentOverride = state.colorOverrides[overrideKey];
                
                const overrideDiv = document.createElement('div');
                overrideDiv.className = 'color-override';
                overrideDiv.dataset.keyword = highlight.keyword;
                overrideDiv.dataset.originalColor = highlight.color;
                overrideDiv.dataset.overrideKey = overrideKey;
                
                const keywordSpan = document.createElement('span');
                keywordSpan.className = 'keyword';
                keywordSpan.textContent = highlight.keyword;
                
                const colorControls = document.createElement('div');
                colorControls.className = 'color-controls';
                
                // Original color indicator
                const originalColor = document.createElement('div');
                originalColor.className = 'original-color';
                originalColor.style.backgroundColor = '#' + highlight.color;
                originalColor.title = 'Reset to original color';
                originalColor.onclick = () => {
                    delete state.colorOverrides[overrideKey];
                    saveSettings();
                    updateExistingColorOverrides();
                    refreshTableColors();
                };
                
                // Custom color picker
                const customColor = document.createElement('input');
                customColor.type = 'color';
                customColor.className = 'custom-color';
                customColor.value = currentOverride ? '#' + currentOverride : '#' + highlight.color;
                customColor.title = 'Customize highlight color';
                customColor.onchange = (e) => {
                    const newColor = e.target.value.substring(1); // Remove # prefix
                    if (newColor !== highlight.color) {
                        state.colorOverrides[overrideKey] = newColor;
                    } else {
                        delete state.colorOverrides[overrideKey];
                    }
                    saveSettings();
                    refreshTableColors();
                };
                
                colorControls.appendChild(originalColor);
                colorControls.appendChild(customColor);
                
                overrideDiv.appendChild(keywordSpan);
                overrideDiv.appendChild(colorControls);
                container.appendChild(overrideDiv);
            });
            
            // Restore color picker values if we had them
            if (savedValues) {
                restoreColorPickerState(savedValues);
            }
        }
        
        function updateExistingColorOverrides() {
            if (!state.data || !state.data.highlightColors) return;
            
            const container = document.getElementById('colorOverridesContainer');
            if (!container) return;
            
            // Update existing elements without recreating them
            state.data.highlightColors.forEach(highlight => {
                const overrideKey = `${highlight.keyword}_${highlight.color}`;
                const currentOverride = state.colorOverrides[overrideKey];
                
                // Find existing element
                const existingElement = container.querySelector(`[data-override-key="${overrideKey}"]`);
                if (existingElement) {
                    // Update the color picker value if needed
                    const colorPicker = existingElement.querySelector('.custom-color');
                    if (colorPicker) {
                        const newValue = currentOverride ? '#' + currentOverride : '#' + highlight.color;
                        if (colorPicker.value !== newValue) {
                            colorPicker.value = newValue;
                        }
                    }
                    
                    // Update original color indicator if needed
                    const originalColor = existingElement.querySelector('.original-color');
                    if (originalColor && originalColor.style.backgroundColor !== '#' + highlight.color) {
                        originalColor.style.backgroundColor = '#' + highlight.color;
                    }
                }
            });
        }
        
        function refreshTableColors() {
            if (!state.data || !state.data.cues) return;
            
            const tbody = document.querySelector('#cueTable tbody');
            if (!tbody) return;
            
            const rows = tbody.querySelectorAll('tr');
            rows.forEach((row, rowIndex) => {
                const cue = state.data.cues[rowIndex];
                if (!cue) return;
                
                // Reset all cell colors in the row first
                const cells = row.querySelectorAll('td');
                cells.forEach(cell => {
                    cell.style.color = '';
                });
                
                // Check each cell for highlight keywords and apply row-level highlighting
                let rowHighlighted = false;
                state.columns.forEach((col, colIndex) => {
                    if (colIndex < state.data.columns.length && !rowHighlighted) {
                        const td = row.children[colIndex];
                        if (td && cue.values[colIndex]) {
                            // Check if this cell should trigger row highlighting
                            for (const highlight of state.data.highlightColors) {
                                if (highlight.keyword && highlight.color && 
                                    cue.values[colIndex].toLowerCase().includes(highlight.keyword.toLowerCase())) {
                                    
                                    // Apply color to entire row
                                    const overrideKey = `${highlight.keyword}_${highlight.color}`;
                                    const colorToApply = state.colorOverrides[overrideKey] || highlight.color;
                                    
                                    cells.forEach(cell => {
                                        cell.style.color = '#' + colorToApply;
                                    });
                                    
                                    rowHighlighted = true;
                                    break; // Use the first matching highlight
                                }
                            }
                        }
                    }
                });
            });
        }
        
        // Prevent color picker destruction during table updates
        function preserveColorPickerState() {
            const container = document.getElementById('colorOverridesContainer');
            if (!container) return;
            
            // Store current color picker values
            const colorPickers = container.querySelectorAll('.custom-color');
            const savedValues = {};
            
            colorPickers.forEach(picker => {
                const overrideKey = picker.closest('.color-override').dataset.overrideKey;
                if (overrideKey) {
                    savedValues[overrideKey] = picker.value;
                }
            });
            
            return savedValues;
        }
        
        function restoreColorPickerState(savedValues) {
            const container = document.getElementById('colorOverridesContainer');
            if (!container || !savedValues) return;
            
            // Restore color picker values
            Object.keys(savedValues).forEach(overrideKey => {
                const colorPicker = container.querySelector(`[data-override-key="${overrideKey}"] .custom-color`);
                if (colorPicker && colorPicker.value !== savedValues[overrideKey]) {
                    colorPicker.value = savedValues[overrideKey];
                }
            });
        }

        // Event Handlers
        document.getElementById('autoScrollToggle').addEventListener('change', (e) => {
            state.autoScrollEnabled = e.target.checked;
        });

        document.getElementById('webSettingsButton').addEventListener('click', (e) => {
            e.stopPropagation();
            const panel = document.getElementById('webSettingsPanel');
            const overlay = document.getElementById('settingsOverlay');
            panel.classList.add('active');
            overlay.classList.add('active');
            
            // Only update if the panel is empty or if highlight colors have changed
            const container = document.getElementById('colorOverridesContainer');
            if (!container.children.length || container.dataset.lastStructure !== state.lastHighlightColorsStructure) {
                updateColorOverrides();
            }
            
            // Mobile positioning optimization
            if (window.innerWidth <= 768) {
                setTimeout(() => {
                    optimizeColorPanelPosition(panel);
                }, 100);
                preventBodyScroll(true);
            }
            
            // Focus management for accessibility
            setTimeout(() => {
                const closeBtn = document.getElementById('closeSettingsBtn');
                if (closeBtn) closeBtn.focus();
            }, 150);
        });

        document.getElementById('closeSettingsBtn').addEventListener('click', () => {
            const panel = document.getElementById('webSettingsPanel');
            const overlay = document.getElementById('settingsOverlay');
            
            // Reset any custom positioning before closing
            if (window.innerWidth <= 768) {
                panel.style.top = '';
                panel.style.transform = '';
                panel.style.width = '';
                panel.style.maxWidth = '';
            }
            
            panel.classList.add('closing');
            setTimeout(() => {
                panel.classList.remove('active', 'closing');
                overlay.classList.remove('active');
            }, 200);
            
            // Restore body scroll on mobile
            if (window.innerWidth <= 768) {
                preventBodyScroll(false);
            }
        });

        document.getElementById('resetColorsBtn').addEventListener('click', () => {
            state.colorOverrides = {};
            saveSettings();
            updateColorOverrides();
            refreshTableColors();
        });

        document.getElementById('columnMenuButton').addEventListener('click', (e) => {
            e.stopPropagation();
            const menu = document.getElementById('columnMenu');
            menu.classList.toggle('active');
            
            // Mobile positioning optimization
            if (menu.classList.contains('active')) {
                setTimeout(() => {
                    optimizeMenuPosition(menu);
                    const firstCheckbox = menu.querySelector('input[type="checkbox"]');
                    if (firstCheckbox) firstCheckbox.focus();
                }, 150); // Increased delay to ensure menu is fully rendered
            }
        });
        
        // Function to optimize menu position for mobile
        function optimizeMenuPosition(menu) {
            if (window.innerWidth <= 768) {
                const buttonRect = document.getElementById('columnMenuButton').getBoundingClientRect();
                const viewportHeight = window.innerHeight;
                const viewportWidth = window.innerWidth;
                
                // Calculate available space above and below the button
                const spaceAbove = buttonRect.top;
                const spaceBelow = viewportHeight - buttonRect.bottom;
                const menuHeight = 400; // Approximate menu height
                
                // Reset any previous positioning
                menu.style.top = '';
                menu.style.bottom = '';
                menu.style.right = '';
                menu.style.marginTop = '';
                menu.style.marginBottom = '';
                menu.style.left = '';
                
                // Determine optimal position based on available space
                if (spaceBelow >= menuHeight + 20 || spaceBelow > spaceAbove) {
                    // Position below button (preferred)
                    menu.style.top = '100%';
                    menu.style.bottom = 'auto';
                    menu.style.marginTop = '8px';
                    menu.style.marginBottom = '0';
                } else {
                    // Position above button if more space available
                    menu.style.top = 'auto';
                    menu.style.bottom = '100%';
                    menu.style.marginTop = '0';
                    menu.style.marginBottom = '8px';
                }
                
                // Adjust horizontal positioning to stay within viewport
                if (buttonRect.right + 200 > viewportWidth - 20) {
                    // Menu would go off right edge, position it to the left
                    menu.style.right = '0';
                    menu.style.left = 'auto';
                } else if (buttonRect.left - 200 < 20) {
                    // Menu would go off left edge, position it to the right
                    menu.style.left = '0';
                    menu.style.right = 'auto';
                }
            }
        }
        
        // Function to optimize color panel position for mobile
        function optimizeColorPanelPosition(panel) {
            if (window.innerWidth <= 768) {
                const viewportHeight = window.innerHeight;
                const viewportWidth = window.innerWidth;
                const panelRect = panel.getBoundingClientRect();
                
                // Calculate optimal vertical position
                let optimalTop = 40; // Default 40% from top
                
                if (viewportHeight <= 600) {
                    // Very small screens - position higher
                    optimalTop = 25;
                } else if (viewportHeight <= 800) {
                    // Small screens - position at 35%
                    optimalTop = 35;
                }
                
                // Apply optimal positioning
                panel.style.top = optimalTop + '%';
                panel.style.transform = `translate(-50%, -${optimalTop}%)`;
                
                // Ensure panel doesn't go off-screen horizontally
                if (panelRect.width > viewportWidth - 40) {
                    panel.style.width = 'calc(100vw - 40px)';
                    panel.style.maxWidth = 'none';
                }
            }
        }

        document.addEventListener('click', (e) => {
            const menu = document.getElementById('columnMenu');
            const button = document.getElementById('columnMenuButton');
            if (!menu.contains(e.target) && !button.contains(e.target)) {
                menu.classList.remove('active');
            }
            
            // Close settings panel when clicking outside
            const settingsPanel = document.getElementById('webSettingsPanel');
            const settingsButton = document.getElementById('webSettingsButton');
            if (settingsPanel && settingsPanel.classList.contains('active') && 
                !settingsPanel.contains(e.target) && !settingsButton.contains(e.target)) {
                const overlay = document.getElementById('settingsOverlay');
                
                // Reset any custom positioning before closing
                if (window.innerWidth <= 768) {
                    settingsPanel.style.top = '';
                    settingsPanel.style.transform = '';
                    settingsPanel.style.width = '';
                    settingsPanel.style.maxWidth = '';
                }
                
                settingsPanel.classList.add('closing');
                setTimeout(() => {
                    settingsPanel.classList.remove('active', 'closing');
                    overlay.classList.remove('active');
                }, 200);
                
                // Restore body scroll on mobile
                if (window.innerWidth <= 768) {
                    preventBodyScroll(false);
                }
            }
        });
        
        // Keyboard support for accessibility
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                const settingsPanel = document.getElementById('webSettingsPanel');
                const columnMenu = document.getElementById('columnMenu');
                
                if (settingsPanel && settingsPanel.classList.contains('active')) {
                    const overlay = document.getElementById('settingsOverlay');
                    
                    // Reset any custom positioning before closing
                    if (window.innerWidth <= 768) {
                        settingsPanel.style.top = '';
                        settingsPanel.style.transform = '';
                        settingsPanel.style.width = '';
                        settingsPanel.style.maxWidth = '';
                    }
                    
                    settingsPanel.classList.add('closing');
                    setTimeout(() => {
                        settingsPanel.classList.remove('active', 'closing');
                        overlay.classList.remove('active');
                    }, 200);
                    
                    // Restore body scroll on mobile
                    if (window.innerWidth <= 768) {
                        preventBodyScroll(false);
                    }
                }
                
                if (columnMenu && columnMenu.classList.contains('active')) {
                    columnMenu.classList.remove('active');
                }
            }
        });

        // iOS-specific viewport handling
        function handleIOSViewport() {
            if (/iPad|iPhone|iPod/.test(navigator.userAgent)) {
                // Force viewport recalculation on iOS
                const viewport = document.querySelector('meta[name="viewport"]');
                if (viewport) {
                    viewport.setAttribute('content', 'width=device-width, initial-scale=1.0, viewport-fit=cover, user-scalable=no');
                }
                
                // Handle iOS Safari 100vh issue
                const vh = window.innerHeight * 0.01;
                document.documentElement.style.setProperty('--vh', `${vh}px`);
                
                // Update on orientation change
                window.addEventListener('orientationchange', () => {
                    setTimeout(() => {
                        const vh = window.innerHeight * 0.01;
                        document.documentElement.style.setProperty('--vh', `${vh}px`);
                    }, 100);
                });
            }
        }
        
        // Mobile scroll prevention when menus are open
        function preventBodyScroll(prevent) {
            if (prevent) {
                document.body.style.overflow = 'hidden';
                document.body.style.position = 'fixed';
                document.body.style.width = '100%';
            } else {
                document.body.style.overflow = '';
                document.body.style.position = '';
                document.body.style.width = '';
            }
        }

        // Initialize
        window.addEventListener('DOMContentLoaded', () => {
            handleIOSViewport();
            loadSettings();
            loadAuthToken(); // Load authentication token
            updateConnectionStatus('disconnected'); // Start with disconnected status
            fetchCues();
            // Single timer for all updates to prevent conflicts
            setInterval(fetchCues, 1000); // Update every 1 second for smooth timer display
            
            // Authentication event listeners
            document.getElementById('loginButton').addEventListener('click', showLoginModal);
            document.getElementById('logoutButton').addEventListener('click', logout);
            document.getElementById('cancelLogin').addEventListener('click', hideLoginModal);
            document.getElementById('loginOverlay').addEventListener('click', hideLoginModal);
            
            document.getElementById('loginForm').addEventListener('submit', async (e) => {
                e.preventDefault();
                const username = document.getElementById('username').value;
                const password = document.getElementById('password').value;
                
                if (username && password) {
                    await login(username, password);
                }
            });
            
            // Suppress fetch-related errors in console to reduce noise
            window.addEventListener('unhandledrejection', (event) => {
                if (event.reason && event.reason.message && 
                    (event.reason.message.includes('fetch') || 
                     event.reason.message.includes('Failed to load resource') ||
                     event.reason.message.includes('Load failed') ||
                     event.reason.message.includes('cannot parse response'))) {
                    event.preventDefault(); // Suppress the error
                }
            });
            
            // Add global error handler for network errors
            window.addEventListener('error', (event) => {
                if (event.message && 
                    (event.message.includes('Failed to load resource') ||
                     event.message.includes('cannot parse response'))) {
                    event.preventDefault(); // Suppress the error
                }
            });
        });
        
        // Offline Functionality Integration
        // Load offline scripts dynamically to avoid blocking main app
        function loadOfflineScripts() {
            const scripts = [
                '/offline-data-manager.js',
                '/offline-state-manager.js',
                '/offline-integration.js'
            ];
            
            scripts.forEach(src => {
                const script = document.createElement('script');
                script.src = src;
                script.async = true;
                script.onerror = () => console.warn('Failed to load offline script:', src);
                document.head.appendChild(script);
            });
            
            // Load offline styles
            const link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = '/offline-styles.css';
            link.onerror = () => console.warn('Failed to load offline styles');
            document.head.appendChild(link);
        }
        
        // Load offline functionality after main app is ready
        setTimeout(loadOfflineScripts, 1000);
    """
}
