//
//  HTMLStyles.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 9/1/24.
//

import Foundation

struct HTMLStyles {
    static let content = """
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
    """
}
