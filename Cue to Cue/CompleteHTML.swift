//
//  CompleteHTML.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 9/1/24.
//

import Foundation

struct CompleteHTML {
    static let content = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover, user-scalable=no">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <title>Cue to Cue 2.0 Viewer</title>
    <style>
        \(HTMLStyles.content)
        \(HTMLSettingsStyles.content)
    </style>
</head>
<body>
    <div class="header-container">
        <div class="connection-status">
            <div class="status-dot" id="statusDot"></div>
            <span class="status-text" id="statusText">Disconnected</span>
        </div>
        <h1>Cue to Cue 2.0 Viewer</h1>
        <div class="auth-container" id="authContainer">
            <div class="auth-status" id="authStatus">
                <span id="userInfo">Not logged in</span>
                <button id="loginButton" class="auth-button">Login</button>
                <button id="logoutButton" class="auth-button" style="display: none;">Logout</button>
            </div>
        </div>
        <div class="clocks-container">
            <div class="clock-box">
                <div class="clock-label">Current Time</div>
                <div class="clock current-time" id="current-time">--:--:--</div>
                <div class="date" id="current-date">--/--/----</div>
            </div>
            <div class="clock-box">
                <div class="clock-label">Countdown</div>
                <div class="clock countdown" id="countdown">00:00</div>
            </div>
            <div class="clock-box">
                <div class="clock-label">Countdown to Start</div>
                <div class="clock countup" id="countup">00:00</div>
            </div>
        </div>
        <div class="column-header">
            <div class="cue-stack-selector">
                <select id="cueStackDropdown" class="cue-stack-dropdown">
                    <option value="">Loading cue stacks...</option>
                </select>
            </div>
            <div id="columnNames">Cue Stack</div>
            <div class="auto-scroll-toggle">
                <label class="switch">
                    <input type="checkbox" id="autoScrollToggle">
                    <span class="slider"></span>
                </label>
                <span class="toggle-label">Auto Scroll</span>
            </div>
            <button class="menu-button" id="webSettingsButton" title="Color & Display Settings">🎨</button>
            <button class="menu-button" id="columnMenuButton" title="Column Visibility">👁️</button>
            <div class="dropdown-menu" id="columnMenu"></div>
        </div>
    </div>

    <div class="table-container">
        <table id="cueTable">
            <thead></thead>
            <tbody></tbody>
        </table>
    </div>

    <!-- Resize Guide -->
    <div class="resize-guide" id="resizeGuide"></div>

    <!-- Color & Display Settings Panel -->
    <div class="web-settings-panel" id="webSettingsPanel">
        <div class="panel-header">
            <h3>Color & Display Settings</h3>
            <p class="panel-description">Customize highlight colors for better visibility</p>
        </div>
        
        <div class="setting-group">
            <h4>Highlight Color Overrides</h4>
            <p class="setting-description">Override the default highlight colors for specific keywords. Click the original color to reset.</p>
            <div id="colorOverridesContainer"></div>
        </div>
        
        <div class="buttons">
            <button id="resetColorsBtn" class="secondary">Reset All Colors</button>
            <button id="closeSettingsBtn" class="primary">Close</button>
        </div>
    </div>

    <!-- Settings Overlay -->
    <div class="settings-overlay" id="settingsOverlay"></div>

    <!-- Login Modal -->
    <div class="login-modal" id="loginModal">
        <div class="login-content">
            <div class="login-header">
                <h2>Login to Edit</h2>
                <p>Enter your credentials to edit cue data</p>
            </div>
            <form id="loginForm">
                <div class="form-group">
                    <label for="username">Username:</label>
                    <input type="text" id="username" name="username" required>
                </div>
                <div class="form-group">
                    <label for="password">Password:</label>
                    <input type="password" id="password" name="password" required>
                </div>
                <div class="form-actions">
                    <button type="button" id="cancelLogin" class="secondary">Cancel</button>
                    <button type="submit" id="submitLogin" class="primary">Login</button>
                </div>
            </form>
            <div class="login-error" id="loginError" style="display: none;"></div>
        </div>
    </div>

    <!-- Login Overlay -->
    <div class="login-overlay" id="loginOverlay"></div>

    <script>
        \(HTMLJavaScript.content)
    </script>
</body>
</html>
"""
}