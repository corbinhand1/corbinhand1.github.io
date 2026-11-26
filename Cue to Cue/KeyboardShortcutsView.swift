//
//  KeyboardShortcutsView.swift
//  Cue to Cue
//
//  Professional keyboard shortcuts editor
//

import SwiftUI
import AppKit

struct KeyboardShortcutsView: View {
    @ObservedObject var shortcutsManager: KeyboardShortcutsManager
    @State private var editingShortcutId: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 24, weight: .bold))
                
                Text("Click a shortcut to change it. Press the keys you want to use.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // Shortcuts list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(shortcutsManager.shortcutsByCategory.keys.sorted()), id: \.self) { category in
                        CategorySection(
                            category: category,
                            shortcuts: shortcutsManager.shortcutsByCategory[category] ?? [],
                            editingShortcutId: $editingShortcutId,
                            onUpdate: { id, key, modifiers in
                                shortcutsManager.updateShortcut(id: id, key: key, modifiers: modifiers)
                                editingShortcutId = nil
                            },
                            onCancel: {
                                editingShortcutId = nil
                            }
                        )
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            // Footer with reset button
            HStack {
                Spacer()
                Button("Restore Defaults") {
                    shortcutsManager.resetToDefaults()
                    editingShortcutId = nil
                }
                .buttonStyle(.bordered)
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Category Section

struct CategorySection: View {
    let category: String
    let shortcuts: [KeyboardShortcut]
    @Binding var editingShortcutId: String?
    let onUpdate: (String, String, [String]) -> Void
    let onCancel: () -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header
            Text(category)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            
            // Shortcuts in this category - 2 column grid
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(shortcuts) { shortcut in
                    ShortcutRowView(
                        shortcut: shortcut,
                        isEditing: editingShortcutId == shortcut.id,
                        onEdit: {
                            editingShortcutId = shortcut.id
                        },
                        onUpdate: { key, modifiers in
                            onUpdate(shortcut.id, key, modifiers)
                        },
                        onCancel: onCancel
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Shortcut Row View

struct ShortcutRowView: View {
    let shortcut: KeyboardShortcut
    let isEditing: Bool
    let onEdit: () -> Void
    let onUpdate: (String, [String]) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Command name
            Text(shortcut.command)
                .font(.system(size: 12))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Shortcut display/edit
            if isEditing {
                KeyRecorderView(
                    initialKey: shortcut.key,
                    initialModifiers: shortcut.modifiers,
                    onRecord: { key, modifiers in
                        onUpdate(key, modifiers)
                    },
                    onCancel: onCancel
                )
            } else {
                Button(action: onEdit) {
                    HStack(spacing: 4) {
                        ForEach(shortcut.modifiers, id: \.self) { modifier in
                            ModifierKeyView(modifier: modifier)
                        }
                        if !shortcut.key.isEmpty {
                            KeyView(key: shortcut.key)
                        } else {
                            Text("—")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(isEditing ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Modifier Key View

struct ModifierKeyView: View {
    let modifier: String
    
    var body: some View {
        Text(modifierSymbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary)
            .frame(minWidth: 20, alignment: .center)
    }
    
    private var modifierSymbol: String {
        switch modifier.lowercased() {
        case "command": return "⌘"
        case "shift": return "⇧"
        case "option": return "⌥"
        case "control": return "⌃"
        default: return ""
        }
    }
}

// MARK: - Key View

struct KeyView: View {
    let key: String
    
    var body: some View {
        Text(key.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 4)
    }
}

// MARK: - Key Recorder View

struct KeyRecorderView: View {
    let initialKey: String
    let initialModifiers: [String]
    let onRecord: (String, [String]) -> Void
    let onCancel: () -> Void
    
    @State private var capturedKey: String = ""
    @State private var capturedModifiers: [String] = []
    @State private var eventMonitor: Any?
    @State private var isRecording = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Recording indicator and key display
            HStack(spacing: 4) {
                if isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .opacity(0.8)
                }
                
                if capturedKey.isEmpty && capturedModifiers.isEmpty {
                    Text("Press keys...")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                } else {
                    ForEach(capturedModifiers, id: \.self) { modifier in
                        ModifierKeyView(modifier: modifier)
                    }
                    if !capturedKey.isEmpty {
                        KeyView(key: capturedKey)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minWidth: 150, alignment: .leading)
            .background(isRecording ? Color.red.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isRecording ? Color.red : Color.clear, lineWidth: 1)
            )
            
            // Action buttons
            Button(action: {
                if !capturedKey.isEmpty || !capturedModifiers.isEmpty {
                    onRecord(capturedKey, capturedModifiers)
                } else {
                    onCancel()
                }
            }) {
                Image(systemName: "checkmark")
                    .accessibilityLabel(Text("Save Shortcut"))
                    .help("Save Shortcut")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(capturedKey.isEmpty && capturedModifiers.isEmpty)
            
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .accessibilityLabel(Text("Cancel"))
                    .help("Cancel")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .onAppear {
            capturedKey = initialKey
            capturedModifiers = initialModifiers
            startRecording()
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleKeyEvent(event)
            return nil // Consume the event
        }
    }
    
    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        isRecording = false
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        // Handle special keys
        if event.type == .keyDown {
            if event.keyCode == 36 { // Return
                if !capturedKey.isEmpty || !capturedModifiers.isEmpty {
                    onRecord(capturedKey, capturedModifiers)
                }
                return
            }
            if event.keyCode == 53 { // Escape
                onCancel()
                return
            }
        }
        
        // Update modifiers
        var newModifiers: [String] = []
        if event.modifierFlags.contains(.command) {
            newModifiers.append("command")
        }
        if event.modifierFlags.contains(.shift) {
            newModifiers.append("shift")
        }
        if event.modifierFlags.contains(.option) {
            newModifiers.append("option")
        }
        if event.modifierFlags.contains(.control) {
            newModifiers.append("control")
        }
        
        // Handle regular key presses
        if event.type == .keyDown {
            // Get the character, ignoring modifiers for display
            let keyChar: String
            if let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty {
                let char = characters.first ?? Character("")
                // Filter out non-printable characters
                if char.isLetter || char.isNumber || ".,;:'\"[]{}()<>?/\\|`~!@#$%^&*-_=+".contains(char) {
                    keyChar = String(char)
                } else {
                    keyChar = keyCodeToCharacter(event.keyCode)
                }
            } else {
                keyChar = keyCodeToCharacter(event.keyCode)
            }
            
            if !keyChar.isEmpty {
                capturedKey = keyChar
                capturedModifiers = newModifiers
            }
        } else if event.type == .flagsChanged {
            // Just modifiers changed
            capturedModifiers = newModifiers
        }
    }
    
    private func keyCodeToCharacter(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 36: return "\r" // Return
        case 48: return "\t" // Tab
        case 49: return " "  // Space
        case 51: return "⌫"  // Delete
        case 53: return "⎋"  // Escape
        case 123: return "←" // Left Arrow
        case 124: return "→" // Right Arrow
        case 125: return "↓" // Down Arrow
        case 126: return "↑" // Up Arrow
        case 115: return "↖" // Home
        case 119: return "↘" // End
        case 116: return "⇞" // Page Up
        case 121: return "⇟" // Page Down
        default: return ""
        }
    }
}
