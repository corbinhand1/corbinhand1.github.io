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
    <title>Cue to Cue Viewer</title>
    <style>
        @font-face {
            font-family: 'Digital-7Mono';
            src: url('path/to/Digital-7Mono.woff2') format('woff2');
        }
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
            font-family: 'Digital-7Mono', monospace;
            font-size: 2rem;
            color: #ffffff;
        }
        .current-time { color: #4a90e2; }
        .countdown, .countup { color: #ff6b6b; } /* countdown and countdown-to-time */
        .date {
            font-size: 0.9rem;
            margin-bottom: 5px;
            color: #b0b0b0;
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
        
        /* Mobile responsiveness */
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
        
        /* Mobile 2-column layout */
        @media (max-width: 768px) {
            .dropdown-menu .columns-container {
                grid-template-columns: 1fr 1fr;
                gap: 4px;
            }
            
            /* Adjust label sizing for 2-column layout */
            .dropdown-menu label {
                font-size: 0.75rem;
                padding: 5px 6px;
                margin-bottom: 1px;
            }
            
            .dropdown-menu input[type="checkbox"] {
                transform: scale(1.0);
                margin-right: 6px;
            }
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
            font-family: 'Source Code Pro', monospace;
            text-align: center;
            background-color: #555555 !important;
            border-radius: 4px;
            padding: 6px !important;
        }

        .struck {
            text-decoration: line-through;
            opacity: 0.7;
        }
        
        /* Debug: Add a background color to see if the class is being applied */
        .struck {
            background-color: rgba(255, 0, 0, 0.1) !important;
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
    </style>
</head>
<body>
    <div class="header-container">
        <div class="connection-status">
            <div class="status-dot" id="statusDot"></div>
            <span class="status-text" id="statusText">Disconnected</span>
        </div>
        <h1>Cue to Cue Viewer</h1>
        <div class="clocks-container">
            <div class="clock-box">
                <div id="current-date" class="date current-time"></div>
                <div id="current-time" class="clock current-time">00:00:00 PM</div>
            </div>
            <div class="clock-box">
                <div class="clock-label">Countdown</div>
                <div id="countdown" class="clock countdown">00:00</div>
            </div>
            <div class="clock-box">
                <div class="clock-label">Countdown to Start</div>
                <div id="countup" class="clock countup">00:00</div>
            </div>
        </div>
        <div class="column-header">
            <div id="columnNames">Cue Stack Name</div>
            <div class="auto-scroll-toggle">
                <label class="switch">
                    <input type="checkbox" id="autoScrollToggle" checked>
                    <span class="slider"></span>
                </label>
                <span class="toggle-label">Auto Scroll</span>
            </div>
            <button class="menu-button" id="webSettingsButton" title="Color & Display Settings">🎨</button>
            <button class="menu-button" id="columnMenuButton" title="Column Visibility">👁️</button>
            <div class="dropdown-menu" id="columnMenu"></div>
        </div>
    </div>
    
    <div class="table-container" id="tableContainer">
        <table id="cueTable">
            <thead></thead>
            <tbody></tbody>
        </table>
    </div>
    
    <div class="resize-guide" id="resizeGuide"></div>
    
    <!-- Color & Display Settings Panel -->
    <div class="settings-overlay" id="settingsOverlay"></div>
    <div class="web-settings-panel" id="webSettingsPanel">
        <div class="panel-header">
            <h3>Color & Display Settings</h3>
            <p class="panel-description">Customize highlight colors and visual appearance</p>
        </div>
        
        <div class="setting-group">
            <h4>Highlight Colors</h4>
            <p class="setting-description">Click on a color to customize, or tap the original color to reset</p>
            <div id="colorOverridesContainer">
                <!-- Color overrides will be populated here -->
            </div>
        </div>
        
        <div class="buttons">
            <button id="resetColorsBtn" class="secondary">Reset All Colors</button>
            <button id="closeSettingsBtn" class="primary">Done</button>
        </div>
    </div>
    


    <script>
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
            colorOverrideUpdateTimer: null
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
                    statusText.textContent = 'Disconnected';
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

        // Data Fetching
        async function fetchCues() {
            try {
                // Only show "attempting" if we're not already connected
                if (state.connectionStatus !== 'connected') {
                    updateConnectionStatus('attempting');
                }
                
                const response = await fetch('/cues');
                if (!response.ok) throw new Error(response.statusText);
                const data = await response.json();
                state.data = data;
                updateUI(data);
                updateConnectionStatus('connected');
            } catch(err) {
                console.error('Error fetching cues:', err);
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
            }

        }

        // Fetch clock updates more frequently for real-time countdown
        async function fetchClockUpdates() {
            try {
                const response = await fetch('/cues');
                if (!response.ok) return;
                const data = await response.json();
                
                // Update countdown timer in real-time
                if (data.countdownTime !== undefined) {
                    const countdownElement = document.getElementById('countdown');
                    if (countdownElement) {
                        const formattedTime = formatTime(data.countdownTime);
                        countdownElement.textContent = formattedTime;
                    }
                }
                
                // Update countdown to time timer in real-time
                if (data.countUpTime !== undefined) {
                    const countupElement = document.getElementById('countup');
                    if (countupElement) {
                        const formattedTime = formatTime(data.countUpTime);
                        countupElement.textContent = formattedTime;
                    }
                }
            } catch(err) {
                // Silently fail for clock updates to avoid connection status changes
                // console.error('Error fetching clock updates:', err);
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
                        const shouldStrike = cue.struck && cue.struck[colIndex];
                        if (shouldStrike) {
                            td.classList.add('struck');
                        }
                        
                        // Apply highlight colors
                        applyHighlightColor(td, cue.values[colIndex], data.highlightColors);
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
                
                tbody.appendChild(row);
            });
            
            attachResizeHandlers();
            saveSettings();
        }

        function updateTableData(data) {
            const tbody = document.querySelector('#cueTable tbody');
            const rows = tbody.querySelectorAll('tr');
            
            // Debug: Log the first cue to see its structure
            if (data.cues.length > 0) {
                
            }
            
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
                        td.textContent = cue.values[colIndex] || '';
                        const shouldStrike = cue.struck && cue.struck[colIndex];
                        td.classList.toggle('struck', shouldStrike);
                        
                        // Apply highlight colors
                        applyHighlightColor(td, cue.values[colIndex], data.highlightColors);

                    } else {
                        td.textContent = cue.timerValue || '';
                        td.classList.add('timer-cell');
                    }
                    
                    td.classList.toggle('hidden', !state.columnVisibility[colId]);
                });
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
        
        // Highlight Color Application
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
                    if (state.colorOverrides[overrideKey]) {
                        td.style.color = '#' + state.colorOverrides[overrideKey];
                    } else {
                        td.style.color = '#' + highlight.color;
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
                
                state.columns.forEach((col, colIndex) => {
                    if (colIndex < state.data.columns.length) {
                        const td = row.children[colIndex];
                        if (td) {
                            applyHighlightColor(td, cue.values[colIndex], state.data.highlightColors);
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
            updateConnectionStatus('disconnected'); // Start with disconnected status
            fetchCues();
            setInterval(fetchCues, 1000);
            
            // Also fetch clock updates more frequently for real-time countdown
            setInterval(fetchClockUpdates, 100);
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
    </script>
</body>
</html>
"""
}


