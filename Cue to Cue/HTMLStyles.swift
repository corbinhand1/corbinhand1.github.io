//
//  HTMLStyles.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 9/1/24.
//

import Foundation

struct HTMLStyles {
    static let content = """
        /* Digital-7Mono font for timer displays - same as macOS app */
        /* Digital Clock Font - Commented out due to missing font file
        @font-face {
            font-family: 'Digital-7Mono';
            src: url('/digital-7-mono.ttf') format('truetype');
            font-weight: normal;
            font-style: normal;
        }
        */
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600&family=Source+Code+Pro&display=swap');
        
        /* Reset and Base Styles */
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }
        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
            background-color: #121212;
            color: #e0e0e0;
            line-height: 1.6;
            height: 100vh;
            height: 100dvh; /* Dynamic viewport height for iOS */
            height: calc(var(--vh, 1vh) * 100); /* Fallback for iOS */
            display: flex;
            flex-direction: column;
            overflow: hidden;
            /* iOS safe area handling */
            padding-top: env(safe-area-inset-top);
            padding-bottom: env(safe-area-inset-bottom);
            padding-left: env(safe-area-inset-left);
            padding-right: env(safe-area-inset-right);
        }

        /* Header Container */
        .header-container {
            background: rgba(18, 18, 18, 0.95);
            padding: 5px 20px;
            padding-top: max(5px, env(safe-area-inset-top) + 5px);
            box-shadow: 0 2px 4px rgba(0,0,0,0.5);
            backdrop-filter: blur(10px);
            flex-shrink: 0;
            /* Ensure header is visible on iOS */
            position: relative;
            z-index: 1000;
        }

        /* Connection Status Indicator */
        .connection-status {
            position: absolute;
            top: max(5px, env(safe-area-inset-top) + 5px);
            right: 20px;
            display: flex;
            align-items: center;
            gap: 8px;
            z-index: 1001;
        }

        .status-dot {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background-color: #666;
            transition: background-color 0.3s ease;
        }

        .status-dot.connected {
            background-color: #4CAF50;
            box-shadow: 0 0 8px rgba(76, 175, 80, 0.6);
        }

        .status-dot.attempting {
            background-color: #FF9800;
            box-shadow: 0 0 8px rgba(255, 152, 0, 0.6);
            animation: pulse 1.5s infinite;
        }

        .status-dot.disconnected {
            background-color: #F44336;
            box-shadow: 0 0 8px rgba(244, 67, 54, 0.6);
        }

        .status-text {
            font-size: 0.8rem;
            color: #e0e0e0;
            font-weight: 500;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }
        .header-container h1 {
            font-size: 1.3rem;
            text-align: center;
            margin-bottom: 10px;
            color: #ffffff;
            letter-spacing: 1px;
        }

        /* Clocks Container */
        .clocks-container {
            display: flex;
            justify-content: space-around;
            align-items: center;
            background-color: rgba(30, 30, 30, 0.85);
            padding: 15px;
            border-radius: 12px;
            margin-bottom: 20px;
        }
        .clock-box {
            text-align: center;
            margin: 0 10px;
            flex: 1;
            min-width: 80px;
        }
        .clock-label {
            font-size: 0.85rem;
            color: #b0b0b0;
            margin-bottom: 5px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .clock {
            font-family: 'Courier New', 'Monaco', 'Consolas', monospace;
            font-size: 2rem;
            color: #ffffff;
            letter-spacing: 1px;
            font-weight: bold;
        }
        .current-time { color: #4a90e2; }
        .countdown, .countup { color: #ff6b6b; } /* countdown and countdown-to-time */
        .date {
            font-family: 'Courier New', 'Monaco', 'Consolas', monospace;
            font-size: 0.9rem;
            margin-bottom: 5px;
            color: #b0b0b0;
            letter-spacing: 0.5px;
        }

        /* Column Header Controls */
        .column-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            background-color: #1e1e1e;
            padding: 12px 20px;
            border-radius: 8px;
            margin-bottom: 10px;
            box-shadow: 0 2px 6px rgba(0,0,0,0.5);
            position: relative;
            z-index: 100;
        }
        #columnNames {
            font-weight: 600;
            font-size: 1.1rem;
            flex: 1;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            color: #ffffff;
        }
        .auto-scroll-toggle {
            display: flex;
            align-items: center;
        }
        .switch {
            position: relative;
            display: inline-block;
            width: 50px;
            height: 26px;
            margin-right: 8px;
        }
        .switch input {
            opacity: 0;
            width: 0;
            height: 0;
        }
        .slider {
            position: absolute;
            cursor: pointer;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background-color: #ccc;
            transition: .4s;
            border-radius: 26px;
        }
        .slider:before {
            position: absolute;
            content: "";
            height: 20px;
            width: 20px;
            left: 3px;
            bottom: 3px;
            background-color: white;
            transition: .4s;
            border-radius: 50%;
        }
        input:checked + .slider { background-color: #2196F3; }
        input:checked + .slider:before { transform: translateX(24px); }
        .toggle-label {
            color: #ffffff;
            font-size: 0.9rem;
            user-select: none;
        }
        .menu-button {
            background: none;
            border: none;
            color: #ffffff;
            font-size: 1.5rem;
            cursor: pointer;
            padding: 6px 10px;
            margin-left: 20px;
            border-radius: 6px;
            transition: all 0.2s ease;
            border: 1px solid transparent;
        }
        
        .menu-button:hover {
            background-color: rgba(255, 255, 255, 0.1);
            border-color: rgba(255, 255, 255, 0.2);
            transform: translateY(-1px);
        }
        
        .menu-button:active {
            transform: translateY(0);
        }

        /* Table Container - Single table approach */
        .table-container {
            flex: 1;
            overflow: auto;
            background-color: #1e1e1e;
            position: relative;
            /* Ensure proper positioning on iOS */
            -webkit-overflow-scrolling: touch;
        }

        /* Single Table with sticky header */
        #cueTable {
            width: 100%;
            border-collapse: separate;
            border-spacing: 0;
            table-layout: fixed;
            min-width: max-content;
        }

        #cueTable thead {
            position: sticky;
            top: 0;
            z-index: 10;
        }

        #cueTable th {
            background-color: #333333;
            color: #ffffff;
            font-weight: 600;
            font-size: 0.95rem;
            padding: 6px 4px;
            text-align: left;
            border-right: 1px solid #444444;
            border-bottom: 2px solid #444444;
            position: relative;
            user-select: none;
            white-space: normal; /* Allow wrapping */
            word-wrap: break-word;
            vertical-align: middle;
        }

        #cueTable th:last-child {
            border-right: none;
        }

        #cueTable td {
            background-color: #1e1e1e;
            color: #e0e0e0;
            padding: 10px 8px;
            font-size: 0.95rem;
            border-right: 1px solid #2a2a2a;
            border-bottom: 1px solid #2a2a2a;
            white-space: normal; /* Allow wrapping */
            word-wrap: break-word;
            overflow-wrap: break-word;
            vertical-align: middle;
        }

        #cueTable td:last-child {
            border-right: none;
        }

        #cueTable tbody tr:nth-child(even) td {
            background-color: #2a2a2a;
        }

        #cueTable tbody tr:hover td {
            background-color: #3a3a3a;
        }

        #cueTable tbody tr.selected td {
            background-color: rgba(58, 122, 34, 0.5);
        }

        #cueTable tbody tr.next td {
            background-color: rgba(186, 176, 32, 0.5);
        }

        .timer-cell {
            font-family: 'Digital-7Mono', 'Source Code Pro', monospace;
            text-align: center;
            background-color: #555555 !important;
            border-radius: 4px;
            padding: 6px !important;
            letter-spacing: 0.5px;
        }

        .struck {
            text-decoration: line-through;
            opacity: 0.7;
        }

        /* Column Resizer - positioned on the right edge */
        .resizer {
            position: absolute;
            right: 0;
            top: 0;
            bottom: 0;
            width: 5px;
            cursor: col-resize;
            background: linear-gradient(to right, transparent, rgba(255,255,255,0.1));
            transition: background 0.2s;
        }

        .resizer:hover {
            background: linear-gradient(to right, transparent, #4a90e2);
        }

        .resizer.active {
            background: linear-gradient(to right, transparent, #2196F3);
        }

        /* Resize Guide */
        .resize-guide {
            position: fixed;
            top: 0;
            bottom: 0;
            width: 2px;
            background-color: #2196F3;
            z-index: 10000;
            pointer-events: none;
            display: none;
        }

        .resize-guide.active {
            display: block;
        }

        /* Prevent selection during resize */
        body.resizing {
            user-select: none;
            cursor: col-resize !important;
        }
        body.resizing * {
            cursor: col-resize !important;
        }

        /* Hide column */
        .hidden {
            display: none !important;
        }

        /* iOS-specific fixes */
        @supports (-webkit-touch-callout: none) {
            body {
                /* iOS Safari specific adjustments */
                -webkit-overflow-scrolling: touch;
                -webkit-tap-highlight-color: transparent;
            }
            
            .header-container {
                /* Ensure header is above iOS Safari UI */
                -webkit-transform: translateZ(0);
                transform: translateZ(0);
            }
        }

        /* Responsive */
        @media (max-width: 768px) {
            .header-container h1 { font-size: 1.1rem; }
            .clock { font-size: 1.5rem; }
            #cueTable th, #cueTable td { padding: 8px 6px; font-size: 0.85rem; }
        }

        @media (max-width: 480px) {
            .header-container h1 { font-size: 1rem; }
            .clock { font-size: 1.25rem; }
            #cueTable th, #cueTable td { padding: 6px 4px; font-size: 0.75rem; }
            
            /* Adjust connection status for small screens */
            .connection-status {
                right: 15px;
                gap: 6px;
            }
            
            .status-dot {
                width: 10px;
                height: 10px;
            }
            
            .status-text {
                font-size: 0.7rem;
            }
            
            /* Adjust auth container for small screens */
            .auth-container {
                left: 15px;
                gap: 8px;
            }
            
            .auth-status {
                gap: 8px;
                font-size: 12px;
            }
            
            .auth-button {
                padding: 4px 8px;
                font-size: 11px;
            }
        }

        /* iPhone-specific clock sizing */
        @media (max-width: 480px) {
            .clocks-container {
                padding: 10px;
                margin-bottom: 15px;
            }
            
            .clock-box {
                margin: 0 5px;
                min-width: 60px;
            }
            
            .clock-label {
                font-size: 0.7rem;
                margin-bottom: 3px;
            }
            
            .clock {
                font-size: 1rem;
            }
            
            .date {
                font-size: 0.75rem;
                margin-bottom: 3px;
            }
        }

        /* Extra small iPhone adjustments */
        @media (max-width: 375px) {
            .clocks-container {
                padding: 8px;
                margin-bottom: 12px;
            }
            
            .clock-box {
                margin: 0 3px;
                min-width: 50px;
            }
            
            .clock {
                font-size: 0.9rem;
            }
            
            .clock-label {
                font-size: 0.65rem;
            }
            
            .date {
                font-size: 0.7rem;
            }
            
            /* Adjust connection status for very small screens */
            .connection-status {
                right: 10px;
                gap: 4px;
            }
            
            .status-dot {
                width: 8px;
                height: 8px;
            }
            
            .status-text {
                font-size: 0.65rem;
            }
        }

        /* iOS Safari specific fixes */
        @media screen and (-webkit-min-device-pixel-ratio: 0) {
            .header-container {
                /* Fix for iOS Safari rendering issues */
                -webkit-backface-visibility: hidden;
                backface-visibility: hidden;
            }
        }

        /* Dropdown Menu */
        .dropdown-menu {
            display: none;
            position: absolute;
            top: 100%;
            right: 0;
            background-color: rgba(28, 28, 30, 0.95);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 12px;
            padding: 12px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3), 0 0 0 1px rgba(255, 255, 255, 0.05);
            z-index: 99999;
            max-height: 400px;
            overflow-y: auto;
            min-width: 200px;
            margin-top: 8px;
            animation: dropdownSlideIn 0.2s cubic-bezier(0.25, 0.46, 0.45, 0.94);
            /* Ensure menu doesn't go off-screen */
            max-width: calc(100vw - 40px);
            /* Prevent positioning jumps */
            transition: none;
            transform: none;
        }
        
        .dropdown-menu.active {
            display: block;
        }
        
        @keyframes dropdownSlideIn {
            from {
                opacity: 0;
                transform: translateY(-8px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        /* Color & Display Settings Panel */
        .web-settings-panel {
            display: none;
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background-color: rgba(28, 28, 30, 0.95);
            backdrop-filter: blur(20px);
            -webkit-backdrop-filter: blur(20px);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 16px;
            padding: 24px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3), 0 0 0 1px rgba(255, 255, 255, 0.05);
            z-index: 10000;
            max-width: 520px;
            width: 90%;
            max-height: 80vh;
            overflow-y: auto;
            animation: panelSlideIn 0.3s cubic-bezier(0.25, 0.46, 0.45, 0.94);
        }
        
        .web-settings-panel.active {
            display: block;
            animation: panelSlideIn 0.3s cubic-bezier(0.25, 0.46, 0.45, 0.94);
        }
        
        .web-settings-panel.closing {
            animation: panelSlideOut 0.2s cubic-bezier(0.55, 0.055, 0.675, 0.19);
        }
        
        @keyframes panelSlideOut {
            from {
                opacity: 1;
                transform: translate(-50%, -50%) scale(1);
            }
            to {
                opacity: 0;
                transform: translate(-50%, -50%) scale(0.95);
            }
        }
        
        .panel-header {
            text-align: center;
            margin-bottom: 24px;
        }
        
        .web-settings-panel h3 {
            margin: 0 0 8px 0;
            color: #ffffff;
            font-size: 1.25rem;
            font-weight: 600;
            letter-spacing: -0.01em;
        }
        
        .panel-description {
            color: #8e8e93;
            font-size: 0.9rem;
            margin: 0;
            line-height: 1.4;
        }
        
        @keyframes panelSlideIn {
            from {
                opacity: 0;
                transform: translate(-50%, -50%) scale(0.95);
            }
            to {
                opacity: 1;
                transform: translate(-50%, -50%) scale(1);
            }
        }
        
        .web-settings-panel .setting-group {
            margin-bottom: 20px;
        }
        
        .web-settings-panel .setting-group h4 {
            color: #ffffff;
            font-size: 1rem;
            margin: 0 0 8px 0;
            font-weight: 600;
            letter-spacing: -0.005em;
        }
        
        .setting-description {
            color: #8e8e93;
            font-size: 0.85rem;
            margin: 0 0 16px 0;
            line-height: 1.4;
        }
        
        .web-settings-panel .color-override {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 12px;
            padding: 16px;
            background-color: rgba(58, 58, 60, 0.6);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 12px;
            transition: all 0.2s ease;
        }
        
        .web-settings-panel .color-override:hover {
            background-color: rgba(58, 58, 60, 0.8);
            border-color: rgba(255, 255, 255, 0.15);
            transform: translateY(-1px);
        }
        
        .web-settings-panel .color-override .keyword {
            color: #ffffff;
            font-size: 0.95rem;
            font-weight: 500;
            flex: 1;
            margin-right: 16px;
        }
        
        .web-settings-panel .color-override .color-controls {
            display: flex;
            align-items: center;
            gap: 12px;
        }
        
        .web-settings-panel .color-override .original-color {
            width: 28px;
            height: 28px;
            border-radius: 50%;
            border: 2px solid rgba(255, 255, 255, 0.2);
            cursor: pointer;
            position: relative;
            transition: all 0.2s ease;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
        }
        
        .web-settings-panel .color-override .original-color:hover {
            border-color: rgba(255, 255, 255, 0.4);
            transform: scale(1.1);
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
        }
        
        .web-settings-panel .color-override .original-color:hover::after {
            content: "Reset to Original";
            position: absolute;
            bottom: -35px;
            left: 50%;
            transform: translateX(-50%);
            background-color: rgba(0, 0, 0, 0.9);
            color: #fff;
            padding: 6px 10px;
            border-radius: 6px;
            font-size: 0.75rem;
            white-space: nowrap;
            z-index: 10001;
            backdrop-filter: blur(10px);
            -webkit-backdrop-filter: blur(10px);
        }
        
        .web-settings-panel .color-override .custom-color {
            width: 28px;
            height: 28px;
            border-radius: 50%;
            border: 2px solid rgba(255, 255, 255, 0.2);
            cursor: pointer;
            padding: 0;
            background: none;
            transition: all 0.2s ease;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
        }
        
        .web-settings-panel .color-override .custom-color:hover {
            border-color: #007AFF;
            transform: scale(1.1);
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
        }
        
        .web-settings-panel .color-override .custom-color::-webkit-color-swatch-wrapper {
            padding: 0;
        }
        
        .web-settings-panel .color-override .custom-color::-webkit-color-swatch {
            border: none;
            border-radius: 50%;
        }
        
        .web-settings-panel .buttons {
            display: flex;
            gap: 12px;
            justify-content: center;
            margin-top: 24px;
        }
        
        .web-settings-panel button {
            background-color: #007AFF;
            color: white;
            border: none;
            padding: 12px 20px;
            border-radius: 10px;
            cursor: pointer;
            font-size: 0.95rem;
            font-weight: 500;
            transition: all 0.2s ease;
            min-width: 100px;
            letter-spacing: -0.01em;
        }
        
        .web-settings-panel button:hover {
            background-color: #0056CC;
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(0, 122, 255, 0.3);
        }
        
        .web-settings-panel button:active {
            transform: translateY(0);
            box-shadow: 0 2px 6px rgba(0, 122, 255, 0.2);
        }
        
        .web-settings-panel button.secondary {
            background-color: rgba(255, 255, 255, 0.1);
            color: #ffffff;
            border: 1px solid rgba(255, 255, 255, 0.2);
        }
        
        .web-settings-panel button.secondary:hover {
            background-color: rgba(255, 255, 255, 0.15);
            border-color: rgba(255, 255, 255, 0.3);
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(255, 255, 255, 0.1);
        }
        
        .web-settings-panel button.primary {
            background-color: #007AFF;
        }
        
        .web-settings-panel button.primary:hover {
            background-color: #0056CC;
        }
        
        /* Overlay for settings panel */
        .settings-overlay {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background-color: rgba(0, 0, 0, 0.5);
            z-index: 9999;
        }
        
        .settings-overlay.active {
            display: block;
        }

        .dropdown-menu h3 {
            margin: 0 0 6px 0;
            color: #ffffff;
            font-size: 0.9rem;
            font-weight: 600;
            text-align: center;
            border-bottom: 1px solid rgba(255, 255, 255, 0.1);
            padding-bottom: 6px;
            letter-spacing: -0.005em;
        }
        
        .dropdown-menu .menu-description {
            color: #8e8e93;
            font-size: 0.75rem;
            margin: 0 0 10px 0;
            text-align: center;
            line-height: 1.3;
        }
        .dropdown-menu .columns-container {
            display: grid;
            grid-template-columns: 1fr;
            gap: 2px;
        }
        
        .dropdown-menu label {
            display: flex;
            align-items: center;
            margin-bottom: 2px;
            color: #ffffff;
            font-size: 0.8rem;
            font-weight: 500;
            cursor: pointer;
            padding: 6px 8px;
            border-radius: 6px;
            transition: all 0.2s ease;
            border: 1px solid transparent;
        }
        
        .dropdown-menu label:hover {
            background-color: rgba(255, 255, 255, 0.1);
            border-color: rgba(255, 255, 255, 0.2);
            transform: translateX(2px);
        }
        
        .dropdown-menu input[type="checkbox"] {
            margin-right: 8px;
            cursor: pointer;
            transform: scale(1.1);
            accent-color: #007AFF;
            width: 14px;
            height: 14px;
        }
        
        /* Custom checkbox styling for better visual appeal */
        .dropdown-menu input[type="checkbox"]:checked {
            accent-color: #007AFF;
        }

        /* Mobile responsiveness for settings panel */
        @media (max-width: 768px) {
            /* Web Settings Panel Mobile Optimization */
            .web-settings-panel {
                width: 95%;
                max-width: none;
                padding: 20px;
                border-radius: 12px;
                max-height: 85vh;
                top: 40% !important;
                transform: translate(-50%, -40%) !important;
                /* Ensure stable positioning on mobile */
                position: fixed;
                left: 50% !important;
                right: auto !important;
            }
            
            .web-settings-panel .color-override {
                padding: 12px;
                flex-direction: column;
                align-items: flex-start;
                gap: 12px;
            }
            
            .web-settings-panel .color-override .color-controls {
                align-self: flex-end;
            }
            
            .web-settings-panel .buttons {
                flex-direction: column;
                gap: 8px;
            }
            
            .web-settings-panel button {
                min-width: auto;
                width: 100%;
                padding: 14px 20px;
                font-size: 1rem;
            }
            
            /* Dropdown Menu Mobile Optimization */
            .dropdown-menu {
                min-width: 320px;
                right: -20px;
                max-height: 70vh;
                padding: 16px;
                /* Ensure stable positioning on mobile */
                position: absolute;
                top: 100% !important;
                bottom: auto !important;
                margin-top: 8px !important;
                margin-bottom: 0 !important;
            }
            
            .dropdown-menu h3 {
                font-size: 1rem;
                margin-bottom: 8px;
            }
            
            .dropdown-menu .menu-description {
                font-size: 0.8rem;
                margin-bottom: 12px;
            }
            
            .dropdown-menu label {
                padding: 8px 10px;
                font-size: 0.9rem;
                margin-bottom: 3px;
            }
            
            .dropdown-menu input[type="checkbox"] {
                transform: scale(1.2);
                margin-right: 10px;
            }
            
            /* Menu Button Mobile Optimization */
            .menu-button {
                padding: 8px 12px;
                font-size: 1.3rem;
                margin-left: 15px;
            }
        }
        
        /* Small Mobile Devices */
        @media (max-width: 480px) {
            .web-settings-panel {
                width: 98%;
                padding: 16px;
                top: 35% !important;
                transform: translate(-50%, -35%) !important;
                /* Maintain stable positioning on small mobile */
                position: fixed;
                left: 50% !important;
                right: auto !important;
            }
            
            .dropdown-menu {
                min-width: 300px;
                right: -30px;
                padding: 14px;
                /* Maintain stable positioning on small mobile */
                top: 100% !important;
                bottom: auto !important;
                margin-top: 8px !important;
                margin-bottom: 0 !important;
            }
            
            .dropdown-menu label {
                padding: 6px 7px;
                font-size: 0.8rem;
            }
            
            .menu-button {
                padding: 6px 10px;
                font-size: 1.2rem;
                margin-left: 10px;
            }
        }
        
        /* Touch-friendly improvements for mobile */
        @media (max-width: 768px) {
            .dropdown-menu label {
                min-height: 36px; /* Reduced but still touch-friendly */
                display: flex;
                align-items: center;
            }
            
            .dropdown-menu input[type="checkbox"] {
                min-width: 36px;
                min-height: 36px;
            }
            
            .web-settings-panel .color-override {
                min-height: 44px;
            }
            
            .web-settings-panel button {
                min-height: 44px;
            }
        }

        /* Authentication Styles */
        .auth-container {
            position: absolute;
            top: max(5px, env(safe-area-inset-top) + 5px);
            left: 20px;
            display: flex;
            align-items: center;
            gap: 10px;
            z-index: 1001;
        }

        .auth-status {
            display: flex;
            align-items: center;
            gap: 10px;
            font-size: 14px;
        }

        .auth-button {
            background: #007AFF;
            color: white;
            border: none;
            padding: 6px 12px;
            border-radius: 6px;
            font-size: 12px;
            cursor: pointer;
            transition: background-color 0.2s;
        }

        .auth-button:hover {
            background: #0056CC;
        }

        .auth-button:active {
            background: #004499;
        }

        /* Login Modal */
        .login-modal {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.8);
            display: none;
            justify-content: center;
            align-items: center;
            z-index: 10000;
        }

        .login-modal.show {
            display: flex;
        }

        .login-content {
            background: #1e1e1e;
            border-radius: 12px;
            padding: 30px;
            width: 90%;
            max-width: 400px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.5);
        }

        .login-header {
            text-align: center;
            margin-bottom: 25px;
        }

        .login-header h2 {
            color: #ffffff;
            margin-bottom: 8px;
            font-size: 24px;
        }

        .login-header p {
            color: #a0a0a0;
            font-size: 14px;
        }

        .form-group {
            margin-bottom: 20px;
        }

        .form-group label {
            display: block;
            margin-bottom: 6px;
            color: #e0e0e0;
            font-size: 14px;
            font-weight: 500;
        }

        .form-group input {
            width: 100%;
            padding: 12px;
            border: 1px solid #404040;
            border-radius: 8px;
            background: #2a2a2a;
            color: #ffffff;
            font-size: 16px;
            transition: border-color 0.2s;
        }

        .form-group input:focus {
            outline: none;
            border-color: #007AFF;
        }

        .form-actions {
            display: flex;
            gap: 12px;
            justify-content: flex-end;
            margin-top: 25px;
        }

        .form-actions button {
            padding: 10px 20px;
            border: none;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s;
        }

        .form-actions .primary {
            background: #007AFF;
            color: white;
        }

        .form-actions .primary:hover {
            background: #0056CC;
        }

        .form-actions .secondary {
            background: #404040;
            color: #e0e0e0;
        }

        .form-actions .secondary:hover {
            background: #505050;
        }

        .login-error {
            background: #ff4444;
            color: white;
            padding: 12px;
            border-radius: 8px;
            margin-top: 15px;
            font-size: 14px;
            text-align: center;
        }

        /* Login Overlay */
        .login-overlay {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.5);
            display: none;
            z-index: 9999;
        }

        .login-overlay.show {
            display: block;
        }

        /* Edit Indicators - Production Ready */
        .editable-cell {
            position: relative;
            cursor: pointer;
            transition: all 0.2s ease;
        }

        .editable-cell:hover {
            background: rgba(0, 122, 255, 0.1) !important;
            border: 1px solid rgba(0, 122, 255, 0.3) !important;
        }

        .editable-cell::before {
            content: "✏";
            position: absolute;
            top: 4px;
            right: 4px;
            font-size: 12px;
            opacity: 0;
            transition: opacity 0.2s;
            pointer-events: none;
            z-index: 10;
            color: #007AFF;
        }

        .editable-cell:hover::before {
            opacity: 0.7;
        }

        .readonly-cell {
            cursor: default;
            opacity: 0.9;
        }

        .readonly-cell:hover {
            background: rgba(128, 128, 128, 0.05) !important;
        }

        .readonly-cell::before {
            content: "🔒";
            position: absolute;
            top: 4px;
            right: 4px;
            font-size: 10px;
            opacity: 0;
            transition: opacity 0.2s;
            pointer-events: none;
            z-index: 10;
            color: #666;
        }

        .readonly-cell:hover::before {
            opacity: 0.5;
        }
    """
}
