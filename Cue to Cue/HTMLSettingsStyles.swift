//
//  HTMLSettingsStyles.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 9/1/24.
//

import Foundation

struct HTMLSettingsStyles {
    static let content = """
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
    """
}
