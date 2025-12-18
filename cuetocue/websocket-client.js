//
//  websocket-client.js
//  Cue to Cue
//
//  Created by Corbin Hand on 10/21/24.
//

class WebSocketClient {
    constructor() {
        this.socket = null;
        this.isConnected = false;
        this.reconnectAttempts = 0;
        this.reconnectDelay = 1000; // Start with 1 second
        this.maxReconnectAttempts = 10;
        this.messageQueue = [];
        this.isProcessingQueue = false;
        this.lastMessageTime = 0;
        this.lastPongTime = 0;
        this.pingInterval = null;
        this.connectionTimeout = null;
        
        // Message throttling
        this.throttleDelay = 100; // 100ms throttle for regular messages
        this.criticalThrottleDelay = 10; // 10ms throttle for critical messages
        this.timerThrottleDelay = 100; // 100ms throttle for timer updates
        
        // Connection info
        this.serverPort = null;
        this.serverHost = null;
        this.connectionId = null;
        
        // Authentication
        this.isAuthenticated = false;
        this.authToken = null;
        
        // Message handlers
        this.messageHandlers = new Map();
        
        // Setup default handlers
        this.setupDefaultHandlers();
    }
    
    // MARK: - Connection Management
    
    connect(host = 'localhost', port = null) {
        this.serverHost = host;
        this.serverPort = port || (parseInt(window.location.port) + 4); // Default to HTTP port + 4
        
        const wsUrl = `ws://${this.serverHost}:${this.serverPort}/`;
        console.log(`🔌 Attempting to connect to WebSocket: ${wsUrl}`);
        
        try {
            this.socket = new WebSocket(wsUrl);
            this.setupEventHandlers();
        } catch (error) {
            console.error('❌ Failed to create WebSocket connection:', error);
            this.scheduleReconnect();
        }
    }
    
    disconnect() {
        console.log('🔌 Disconnecting WebSocket...');
        
        if (this.pingInterval) {
            clearInterval(this.pingInterval);
            this.pingInterval = null;
        }
        
        if (this.connectionTimeout) {
            clearTimeout(this.connectionTimeout);
            this.connectionTimeout = null;
        }
        
        if (this.socket) {
            this.socket.close();
            this.socket = null;
        }
        
        this.isConnected = false;
        this.isAuthenticated = false;
        this.reconnectAttempts = 0;
    }
    
    // MARK: - Event Handlers
    
    setupEventHandlers() {
        this.socket.onopen = (event) => {
            console.log('✅ WEBSOCKET CONNECTED - Ready to receive timer updates');
            this.isConnected = true;
            this.reconnectAttempts = 0;
            this.reconnectDelay = 1000; // Reset delay
            
            // Start ping interval
            this.startPingInterval();
            
            // Process any queued messages
            this.processMessageQueue();
            
            // Notify connection success
            this.notifyConnectionChange(true);
        };
        
        this.socket.onmessage = (event) => {
            this.handleMessage(event.data);
        };
        
        this.socket.onclose = (event) => {
            console.log('🔌 WebSocket disconnected:', event.code, event.reason);
            this.isConnected = false;
            this.isAuthenticated = false;
            
            // Stop ping interval
            if (this.pingInterval) {
                clearInterval(this.pingInterval);
                this.pingInterval = null;
            }
            
            // Notify connection change
            this.notifyConnectionChange(false);
            
            // Attempt to reconnect if not a clean close
            if (event.code !== 1000 && this.reconnectAttempts < this.maxReconnectAttempts) {
                this.scheduleReconnect();
            }
        };
        
        this.socket.onerror = (error) => {
            console.error('❌ WebSocket error:', error);
            this.notifyConnectionError(error);
        };
    }
    
    // MARK: - Message Handling
    
    handleMessage(data) {
        try {
            const message = JSON.parse(data);
            const messageType = message.type || 'unknown';
            
            console.log(`📨 Received message: ${messageType}`);
            
            // Update last message time
            this.lastMessageTime = Date.now();
            
            // Handle specific message types
            if (this.messageHandlers.has(messageType)) {
                this.messageHandlers.get(messageType)(message);
            } else {
                console.warn(`⚠️ No handler for message type: "${messageType}"`);
            }
            
        } catch (error) {
            console.error('❌ Failed to parse WebSocket message:', error);
            console.error('❌ Raw message:', data);
        }
    }
    
    setupDefaultHandlers() {
        // Cue update handler
        this.messageHandlers.set('cue_update', (message) => {
            console.log('🎯 Received cue update:', message);
            this.processMessageQueue(); // Process immediately for critical messages
        });
        
        // Cue navigation handler
        this.messageHandlers.set('cue_navigation', (message) => {
            console.log('🧭 Received cue navigation:', message);
            this.processMessageQueue(); // Process immediately for critical messages
        });
        
        // Timer update handler
        this.messageHandlers.set('timer_update', (message) => {
            console.log('⏰ TIMER RECEIVED - Countdown:', message.countdownTime, 's, CountUp:', message.countUpTime, 's, CD Running:', message.countdownRunning, 'CU Running:', message.countUpRunning);
            console.log('⏰ TIMER DATA - Full message:', JSON.stringify(message));
            
            // Actually update the timer display
            if (typeof updateClocks === 'function') {
                updateClocks(message);
            } else {
                console.warn('⚠️ updateClocks function not available');
            }
        });
        
        // Authentication handler
        this.messageHandlers.set('auth_response', (message) => {
            console.log('🔐 Received auth response:', message);
            this.isAuthenticated = message.success || false;
            if (this.isAuthenticated) {
                console.log('✅ Authentication successful');
            } else {
                console.log('❌ Authentication failed');
            }
        });
        
        // Pong handler
        this.messageHandlers.set('pong', (message) => {
            console.log('🏓 Received pong');
            this.lastPongTime = Date.now();
        });
        
        // Connection info handler
        this.messageHandlers.set('connection_info', (message) => {
            console.log('🔌 Received connection info:', message);
            this.connectionId = message.connectionId;
        });
    }
    
    // MARK: - Message Sending
    
    sendMessage(message) {
        if (!this.isConnected || !this.socket) {
            console.warn('⚠️ WebSocket not connected, queuing message');
            this.messageQueue.push(message);
            return;
        }
        
        try {
            const messageStr = typeof message === 'string' ? message : JSON.stringify(message);
            this.socket.send(messageStr);
            console.log(`📤 Sent WebSocket message: ${messageStr.substring(0, 100)}...`);
        } catch (error) {
            console.error('❌ Failed to send WebSocket message:', error);
            this.messageQueue.push(message); // Queue for retry
        }
    }
    
    sendThrottledMessage(message, priority = 'normal') {
        const now = Date.now();
        let throttleDelay = this.throttleDelay;
        
        // Determine throttle delay based on priority
        switch (priority) {
            case 'critical':
                throttleDelay = this.criticalThrottleDelay;
                break;
            case 'timer':
                throttleDelay = this.timerThrottleDelay;
                break;
            default:
                throttleDelay = this.throttleDelay;
        }
        
        // Check if we should throttle this message
        if (now - this.lastMessageTime < throttleDelay) {
            // Add to queue for later processing
            this.messageQueue.push({ message, priority, timestamp: now });
            return;
        }
        
        // Send immediately
        this.sendMessage(message);
        this.lastMessageTime = now;
    }
    
    // MARK: - Message Queue Processing
    
    processMessageQueue() {
        if (this.isProcessingQueue || this.messageQueue.length === 0) {
            return;
        }
        
        this.isProcessingQueue = true;
        
        // Sort messages by priority
        this.messageQueue.sort((a, b) => {
            const priorityOrder = { 'critical': 0, 'normal': 1, 'timer': 2 };
            return (priorityOrder[a.priority] || 1) - (priorityOrder[b.priority] || 1);
        });
        
        // Process messages
        while (this.messageQueue.length > 0) {
            const { message, priority } = this.messageQueue.shift();
            this.sendMessage(message);
            
            // Add delay between messages to prevent overwhelming
            if (this.messageQueue.length > 0) {
                const delay = priority === 'critical' ? this.criticalThrottleDelay : this.throttleDelay;
                setTimeout(() => {
                    this.isProcessingQueue = false;
                    this.processMessageQueue();
                }, delay);
                return;
            }
        }
        
        this.isProcessingQueue = false;
    }
    
    // MARK: - Authentication
    
    authenticate(token) {
        this.authToken = token;
        this.sendMessage({
            type: 'auth',
            token: token
        });
    }
    
    // MARK: - Ping/Pong
    
    startPingInterval() {
        if (this.pingInterval) {
            clearInterval(this.pingInterval);
        }
        
        this.pingInterval = setInterval(() => {
            if (this.isConnected) {
                this.sendMessage('ping');
                console.log('📤 Sent WebSocket message: "ping"');
                
                // Check if we received a pong recently
                const now = Date.now();
                if (this.lastPongTime > 0 && now - this.lastPongTime > 30000) { // 30 seconds
                    console.warn('⚠️ No pong received in 30 seconds, connection may be stale');
                }
            }
        }, 30000); // Ping every 30 seconds
    }
    
    // MARK: - Reconnection
    
    scheduleReconnect() {
        if (this.reconnectAttempts >= this.maxReconnectAttempts) {
            console.error('❌ Max reconnection attempts reached');
            return;
        }
        
        this.reconnectAttempts++;
        const delay = Math.min(this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1), 30000);
        
        console.log(`🔄 Scheduling reconnection attempt ${this.reconnectAttempts} in ${delay}ms`);
        
        this.connectionTimeout = setTimeout(() => {
            console.log(`🔄 Reconnection attempt ${this.reconnectAttempts}`);
            this.connect(this.serverHost, this.serverPort);
        }, delay);
    }
    
    // MARK: - Notifications
    
    notifyConnectionChange(isConnected) {
        // Dispatch custom event for other parts of the app
        const event = new CustomEvent('websocket-connection-change', {
            detail: { isConnected, connectionId: this.connectionId }
        });
        window.dispatchEvent(event);
    }
    
    notifyConnectionError(error) {
        // Dispatch custom event for connection errors
        const event = new CustomEvent('websocket-error', {
            detail: { error: error.message || 'Unknown WebSocket error' }
        });
        window.dispatchEvent(event);
    }
    
    // MARK: - Public API
    
    getConnectionStatus() {
        return {
            isConnected: this.isConnected,
            isAuthenticated: this.isAuthenticated,
            connectionId: this.connectionId,
            reconnectAttempts: this.reconnectAttempts,
            lastMessageTime: this.lastMessageTime,
            lastPongTime: this.lastPongTime
        };
    }
    
    getQueueStatus() {
        return {
            queueLength: this.messageQueue.length,
            isProcessing: this.isProcessingQueue
        };
    }
    
    // MARK: - Message Handlers Registration
    
    registerMessageHandler(messageType, handler) {
        this.messageHandlers.set(messageType, handler);
    }
    
    unregisterMessageHandler(messageType) {
        this.messageHandlers.delete(messageType);
    }
}

// MARK: - Global WebSocket Client Instance

// Create global instance
window.webSocketClient = new WebSocketClient();

// Auto-connect when page loads
document.addEventListener('DOMContentLoaded', () => {
    // Get server info from current page
    const host = window.location.hostname;
    const port = parseInt(window.location.port) + 4; // WebSocket port is HTTP port + 4
    
    console.log('🚀 Initializing WebSocket connection...');
    window.webSocketClient.connect(host, port);
});

// Handle page unload
window.addEventListener('beforeunload', () => {
    if (window.webSocketClient) {
        window.webSocketClient.disconnect();
    }
});

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = WebSocketClient;
}