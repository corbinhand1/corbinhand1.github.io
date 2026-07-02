//
//  WebTimerClient.js
//  Cue to Cue
//
//  Created by Corbin Hand on 1/15/25.
//

class WebTimerClient {
    constructor() {
        this.ws = null;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 10;
        this.reconnectDelay = 1000;
        this.maxReconnectDelay = 30000;
        this.heartbeatInterval = null;
        this.lastPingTime = 0;
        this.lastPongTime = 0;
        
        // Timer state
        this.timerState = {
            currentTime: new Date(),
            countdownTime: 0,
            countUpTime: 0,
            countdownRunning: false,
            countUpRunning: false,
            sequenceNumber: 0,
            timestamp: 0
        };
        
        // Display state for smooth updates
        this.displayState = { ...this.timerState };
        this.displayLink = null;
        this.lastDisplayUpdate = 0;
        this.targetFrameRate = 60;
        
        // Connection state
        this.isConnected = false;
        this.isConnecting = false;
        this.connectionStartTime = 0;
        
        // Message handling
        this.messageHandlers = new Map();
        this.setupMessageHandlers();
        
        // Performance monitoring
        this.stats = {
            messagesReceived: 0,
            messagesSent: 0,
            lastMessageTime: 0,
            averageLatency: 0,
            connectionUptime: 0
        };
        
        console.log('🕐 WebTimerClient initialized');
    }
    
    // MARK: - Connection Management
    
    connect(url = null) {
        if (this.isConnecting || this.isConnected) {
            console.log('⚠️ Already connecting or connected');
            return;
        }
        
        this.isConnecting = true;
        this.connectionStartTime = Date.now();
        
        const wsUrl = url || this.getWebSocketUrl();
        console.log(`🔌 Connecting to WebSocket: ${wsUrl}`);
        
        try {
            this.ws = new WebSocket(wsUrl);
            this.setupWebSocketHandlers();
        } catch (error) {
            console.error('❌ WebSocket connection failed:', error);
            this.handleConnectionError();
        }
    }
    
    disconnect() {
        console.log('🔌 Disconnecting WebSocket');
        this.isConnecting = false;
        this.isConnected = false;
        
        if (this.ws) {
            this.ws.close();
            this.ws = null;
        }
        
        this.stopHeartbeat();
        this.stopDisplayUpdates();
    }
    
    getWebSocketUrl() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const host = window.location.host;
        return `${protocol}//${host}`;
    }
    
    setupWebSocketHandlers() {
        this.ws.onopen = (event) => {
            console.log('✅ WebSocket connected');
            this.isConnected = true;
            this.isConnecting = false;
            this.reconnectAttempts = 0;
            this.startHeartbeat();
            this.startDisplayUpdates();
            this.updateConnectionStatus('connected');
        };
        
        this.ws.onmessage = (event) => {
            this.handleMessage(event.data);
        };
        
        this.ws.onclose = (event) => {
            console.log('🔌 WebSocket disconnected:', event.code, event.reason);
            this.isConnected = false;
            this.isConnecting = false;
            this.stopHeartbeat();
            this.updateConnectionStatus('disconnected');
            
            if (!event.wasClean) {
                this.scheduleReconnect();
            }
        };
        
        this.ws.onerror = (error) => {
            console.error('❌ WebSocket error:', error);
            this.handleConnectionError();
        };
    }
    
    // MARK: - Message Handling
    
    setupMessageHandlers() {
        this.messageHandlers.set('timer_update', (data) => this.handleTimerUpdate(data));
        this.messageHandlers.set('timer_sync', (data) => this.handleTimerSync(data));
        this.messageHandlers.set('timer_command', (data) => this.handleTimerCommand(data));
        this.messageHandlers.set('ping', (data) => this.handlePing(data));
        this.messageHandlers.set('pong', (data) => this.handlePong(data));
    }
    
    handleMessage(data) {
        try {
            const message = JSON.parse(data);
            this.stats.messagesReceived++;
            this.stats.lastMessageTime = Date.now();
            
            const handler = this.messageHandlers.get(message.type);
            if (handler) {
                handler(message.data);
            } else {
                console.warn('⚠️ Unknown message type:', message.type);
            }
        } catch (error) {
            console.error('❌ Error parsing message:', error);
        }
    }
    
    handleTimerUpdate(data) {
        // Update timer state
        this.timerState = {
            currentTime: new Date(data.currentTime),
            countdownTime: data.countdownTime,
            countUpTime: data.countUpTime,
            countdownRunning: data.countdownRunning,
            countUpRunning: data.countUpRunning,
            sequenceNumber: data.sequenceNumber || 0,
            timestamp: data.timestamp || Date.now()
        };
        
        // Update display elements
        this.updateDisplayElements();
    }
    
    handleTimerSync(data) {
        // Full synchronization
        this.handleTimerUpdate(data);
        console.log('🔄 Timer synchronized');
    }
    
    handleTimerCommand(data) {
        console.log('🎯 Timer command received:', data.action);
        // Commands are handled by the server, client just logs
    }
    
    handlePing(data) {
        this.lastPingTime = Date.now();
        this.sendPong();
    }
    
    handlePong(data) {
        this.lastPongTime = Date.now();
        const latency = this.lastPongTime - this.lastPingTime;
        this.stats.averageLatency = (this.stats.averageLatency + latency) / 2;
    }
    
    // MARK: - Display Updates
    
    startDisplayUpdates() {
        if (this.displayLink) return;
        
        this.displayLink = setInterval(() => {
            this.updateDisplay();
        }, 1000 / this.targetFrameRate);
        
        console.log(`🖥️ Started display updates at ${this.targetFrameRate} FPS`);
    }
    
    stopDisplayUpdates() {
        if (this.displayLink) {
            clearInterval(this.displayLink);
            this.displayLink = null;
            console.log('⏹️ Stopped display updates');
        }
    }
    
    updateDisplay() {
        const now = Date.now();
        
        // Smooth interpolation for countdown timer
        if (this.timerState.countdownRunning) {
            const timeSinceUpdate = (now - this.timerState.timestamp) / 1000;
            this.displayState.countdownTime = Math.max(0, this.timerState.countdownTime - timeSinceUpdate);
        } else {
            this.displayState.countdownTime = this.timerState.countdownTime;
        }
        
        // Smooth interpolation for countdown-to-start (remaining seconds decrease)
        if (this.timerState.countUpRunning) {
            const timeSinceUpdate = (now - this.timerState.timestamp) / 1000;
            this.displayState.countUpTime = Math.max(0, this.timerState.countUpTime - timeSinceUpdate);
        } else {
            this.displayState.countUpTime = this.timerState.countUpTime;
        }
        
        // Update current time
        this.displayState.currentTime = new Date();
        
        // Update display elements
        this.updateDisplayElements();
    }
    
    updateDisplayElements() {
        // Update countdown display
        const countdownElement = document.getElementById('countdown');
        if (countdownElement) {
            countdownElement.textContent = this.formatTime(this.displayState.countdownTime);
        }
        
        // Update count-up display (countdown-to-start)
        const countupElement = document.getElementById('countup');
        if (countupElement) {
            if (this.timerState.countUpRunning) {
                countupElement.textContent = this.formatTime(this.displayState.countUpTime);
            } else {
                countupElement.textContent = '--:--:--';
            }
        }
        
        // Update current time display
        const currentTimeElement = document.getElementById('current-time');
        if (currentTimeElement) {
            const timeString = this.displayState.currentTime.toLocaleTimeString([], {
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });
            currentTimeElement.textContent = timeString;
        }
        
        // Update current date display
        const currentDateElement = document.getElementById('current-date');
        if (currentDateElement) {
            currentDateElement.textContent = this.displayState.currentTime.toLocaleDateString();
        }
    }
    
    // MARK: - Heartbeat Management
    
    startHeartbeat() {
        this.stopHeartbeat();
        this.heartbeatInterval = setInterval(() => {
            this.sendPing();
        }, 30000); // Send ping every 30 seconds
    }
    
    stopHeartbeat() {
        if (this.heartbeatInterval) {
            clearInterval(this.heartbeatInterval);
            this.heartbeatInterval = null;
        }
    }
    
    sendPing() {
        if (this.isConnected && this.ws.readyState === WebSocket.OPEN) {
            const message = {
                type: 'ping',
                data: { timestamp: Date.now() },
                sequenceNumber: this.timerState.sequenceNumber
            };
            this.sendMessage(message);
        }
    }
    
    sendPong() {
        if (this.isConnected && this.ws.readyState === WebSocket.OPEN) {
            const message = {
                type: 'pong',
                data: { timestamp: Date.now() },
                sequenceNumber: this.timerState.sequenceNumber
            };
            this.sendMessage(message);
        }
    }
    
    // MARK: - Reconnection Logic
    
    scheduleReconnect() {
        if (this.reconnectAttempts >= this.maxReconnectAttempts) {
            console.error('❌ Max reconnection attempts reached');
            this.updateConnectionStatus('failed');
            return;
        }
        
        this.reconnectAttempts++;
        const delay = Math.min(this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1), this.maxReconnectDelay);
        
        console.log(`🔄 Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts})`);
        this.updateConnectionStatus('reconnecting');
        
        setTimeout(() => {
            this.connect();
        }, delay);
    }
    
    handleConnectionError() {
        this.isConnecting = false;
        this.isConnected = false;
        this.updateConnectionStatus('error');
        this.scheduleReconnect();
    }
    
    // MARK: - Utility Methods
    
    sendMessage(message) {
        if (this.isConnected && this.ws.readyState === WebSocket.OPEN) {
            try {
                this.ws.send(JSON.stringify(message));
                this.stats.messagesSent++;
            } catch (error) {
                console.error('❌ Error sending message:', error);
            }
        }
    }
    
    formatTime(seconds) {
        const isNegative = seconds < 0;
        const absSeconds = Math.abs(seconds);
        const hours = Math.floor(absSeconds / 3600);
        const minutes = Math.floor((absSeconds % 3600) / 60);
        const remainingSeconds = Math.floor(absSeconds % 60);
        
        if (hours > 0) {
            return `${isNegative ? '-' : ''}${hours}:${minutes.toString().padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
        } else {
            return `${isNegative ? '-' : ''}${minutes.toString().padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
        }
    }
    
    updateConnectionStatus(status) {
        // Update connection status indicator
        const statusElement = document.getElementById('connection-status');
        if (statusElement) {
            statusElement.textContent = status;
            statusElement.className = `connection-status ${status}`;
        }
        
        // Update connection stats
        this.stats.connectionUptime = this.isConnected ? Date.now() - this.connectionStartTime : 0;
    }
    
    // MARK: - Public API
    
    getStats() {
        return {
            ...this.stats,
            isConnected: this.isConnected,
            isConnecting: this.isConnecting,
            reconnectAttempts: this.reconnectAttempts,
            timerState: this.timerState,
            displayState: this.displayState
        };
    }
    
    forceReconnect() {
        console.log('🔄 Force reconnecting...');
        this.disconnect();
        setTimeout(() => {
            this.reconnectAttempts = 0;
            this.connect();
        }, 1000);
    }
    
    setTargetFrameRate(frameRate) {
        this.targetFrameRate = Math.max(10, Math.min(120, frameRate));
        if (this.displayLink) {
            this.stopDisplayUpdates();
            this.startDisplayUpdates();
        }
        console.log(`🖥️ Updated target frame rate to ${this.targetFrameRate} FPS`);
    }
}

// MARK: - Global Instance
window.timerClient = new WebTimerClient();

// Auto-connect when page loads
document.addEventListener('DOMContentLoaded', () => {
    console.log('🚀 Starting WebTimerClient...');
    window.timerClient.connect();
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    if (window.timerClient) {
        window.timerClient.disconnect();
    }
});




