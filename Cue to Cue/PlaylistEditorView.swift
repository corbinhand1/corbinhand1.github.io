//
//  PlaylistEditorView.swift
//  Cue to Cue
//
//  Created for playlist editing modal
//

import SwiftUI

struct PlaylistEditorView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataSyncManager: DataSyncManager
    @EnvironmentObject var timerServer: AuthoritativeTimerServer
    
    // Local editing state - don't modify actual playlist until Save
    @State private var editingPlaylist: CountdownPlaylist
    @State private var editingIndex: Int?
    @State private var editingTimeString: String = ""
    @State private var editingLabelString: String = ""
    @State private var isReordering: Bool = false
    
    // New entry state
    @State private var newEntryTime: String = "10:00:00"
    @State private var newEntryLabel: String = ""
    
    init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        // Initialize with empty playlist - will be populated in onAppear
        self._editingPlaylist = State(initialValue: CountdownPlaylist())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Countdown Playlist Editor")
                    .font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Settings Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Playlist Settings")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 16) {
                        Toggle("Loop", isOn: $editingPlaylist.loopPlaylist)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                
                // Entries Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Playlist Entries")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        
                        // Reorder button
                        Button(action: { isReordering.toggle() }) {
                            Image(systemName: isReordering ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                                .foregroundColor(isReordering ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isReordering ? "Done reordering" : "Reorder entries")
                        
                        if let currentIdx = editingPlaylist.currentIndex, currentIdx < editingPlaylist.entries.count {
                            Text("Current: Entry \(currentIdx + 1) of \(editingPlaylist.entries.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if editingPlaylist.entries.isEmpty {
                        Text("No entries. Add your first entry below.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                            .cornerRadius(6)
                    } else {
                        // Table view of entries
                        if isReordering {
                            // Use List for drag and drop reordering
                            List {
                                ForEach(Array(editingPlaylist.entries.enumerated()), id: \.element.id) { index, entry in
                                    PlaylistEditorRow(
                                        entry: entry,
                                        index: index,
                                        isActive: editingPlaylist.currentIndex == index,
                                        isEditing: editingIndex == index,
                                        isReordering: isReordering,
                                        editingTimeString: $editingTimeString,
                                        editingLabelString: $editingLabelString,
                                        onEdit: {
                                            editingIndex = index
                                            editingTimeString = entry.timeString
                                            editingLabelString = entry.label ?? ""
                                        },
                                        onSave: { timeString, label in
                                            editingPlaylist.entries[index].timeString = timeString
                                            editingPlaylist.entries[index].label = label.isEmpty ? nil : label
                                            editingIndex = nil
                                        },
                                        onCancel: {
                                            editingIndex = nil
                                        },
                                        onDelete: {
                                            editingPlaylist.entries.remove(at: index)
                                            // Adjust currentIndex if needed
                                            if let currentIdx = editingPlaylist.currentIndex {
                                                if currentIdx == index {
                                                    editingPlaylist.currentIndex = nil
                                                } else if currentIdx > index {
                                                    editingPlaylist.currentIndex = currentIdx - 1
                                                }
                                            }
                                        }
                                    )
                                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                                    .listRowBackground(Color.clear)
                                }
                                .onMove(perform: movePlaylistEntry)
                            }
                            .listStyle(.plain)
                            .frame(maxHeight: 400)
                            .scrollContentBackground(.hidden)
                        } else {
                            // Use ScrollView for normal viewing/editing
                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(Array(editingPlaylist.entries.enumerated()), id: \.element.id) { index, entry in
                                        PlaylistEditorRow(
                                            entry: entry,
                                            index: index,
                                            isActive: editingPlaylist.currentIndex == index,
                                            isEditing: editingIndex == index,
                                            isReordering: isReordering,
                                            editingTimeString: $editingTimeString,
                                            editingLabelString: $editingLabelString,
                                            onEdit: {
                                                editingIndex = index
                                                editingTimeString = entry.timeString
                                                editingLabelString = entry.label ?? ""
                                            },
                                            onSave: { timeString, label in
                                                editingPlaylist.entries[index].timeString = timeString
                                                editingPlaylist.entries[index].label = label.isEmpty ? nil : label
                                                editingIndex = nil
                                            },
                                            onCancel: {
                                                editingIndex = nil
                                            },
                                            onDelete: {
                                                editingPlaylist.entries.remove(at: index)
                                                // Adjust currentIndex if needed
                                                if let currentIdx = editingPlaylist.currentIndex {
                                                    if currentIdx == index {
                                                        editingPlaylist.currentIndex = nil
                                                    } else if currentIdx > index {
                                                        editingPlaylist.currentIndex = currentIdx - 1
                                                    }
                                                }
                                            }
                                        )
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            .frame(maxHeight: 400)
                        }
                    }
                    
                    // Add Entry Section
                    if editingPlaylist.entries.count < 10 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add New Entry")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Time (HH:mm:ss)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    TextField("10:00:00", text: $newEntryTime)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(width: 120)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Label (optional)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    TextField("Label", text: $newEntryLabel)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(minWidth: 200)
                                }
                                
                                Spacer()
                                
                                Button(action: addNewEntry) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!isValidTimeFormat(newEntryTime))
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                        .cornerRadius(8)
                    } else {
                        Text("Maximum 10 entries reached")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                            .cornerRadius(6)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }
            .padding(20)
            
            Spacer()
            
            // Action Buttons
            Divider()
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                .frame(width: 80)
                
                Button("Save") {
                    savePlaylist()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isPlaylistValid())
                .frame(width: 80)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 640, height: 600)
        .onAppear {
            // Initialize editing state with current playlist
            editingPlaylist = dataSyncManager.countdownPlaylist
        }
    }
    
    // MARK: - Helper Methods
    
    private func movePlaylistEntry(from source: IndexSet, to destination: Int) {
        // Perform the move
        editingPlaylist.entries.move(fromOffsets: source, toOffset: destination)
        
        // Adjust currentIndex if needed
        if let currentIdx = editingPlaylist.currentIndex,
           let movedIndex = source.first {
            if movedIndex == currentIdx {
                // Current entry was moved
                editingPlaylist.currentIndex = (destination > movedIndex) ? (destination - 1) : destination
            } else if movedIndex < currentIdx && destination <= currentIdx {
                // Entry before current was moved forward
                editingPlaylist.currentIndex = currentIdx - 1
            } else if movedIndex > currentIdx && destination <= currentIdx {
                // Entry after current was moved backward
                editingPlaylist.currentIndex = currentIdx + 1
            }
        }
    }
    
    private func addNewEntry() {
        guard isValidTimeFormat(newEntryTime) else { return }
        
        let newEntry = PlaylistEntry(
            timeString: newEntryTime,
            label: newEntryLabel.isEmpty ? nil : newEntryLabel
        )
        editingPlaylist.entries.append(newEntry)
        
        // Reset new entry fields
        newEntryTime = "10:00:00"
        newEntryLabel = ""
    }
    
    private func savePlaylist() {
        // Validate playlist
        guard isPlaylistValid() else { return }
        
        // Ensure isActive is always true (playlist is the only mode)
        editingPlaylist.isActive = true
        
        // Update DataSyncManager
        dataSyncManager.countdownPlaylist = editingPlaylist
        
        // Sync to timer server
        timerServer.syncPlaylistState(editingPlaylist)
        
        // If playlist has current index, update timer target
        if let idx = editingPlaylist.currentIndex,
           idx < editingPlaylist.entries.count {
            let entry = editingPlaylist.entries[idx]
            let command = TimerCommand(
                action: "setCountdownToTime",
                countdownTime: nil,
                countUpTime: nil,
                adjustment: nil,
                targetTimeString: entry.timeString
            )
            timerServer.executeCommand(command)
        }
        
        isPresented = false
    }
    
    private func isPlaylistValid() -> Bool {
        // Check if all entries have valid time formats
        for entry in editingPlaylist.entries {
            if !isValidTimeFormat(entry.timeString) {
                return false
            }
        }
        
        // Must have at least one entry
        if editingPlaylist.entries.isEmpty {
            return false
        }
        
        // currentIndex must be valid if set
        if let idx = editingPlaylist.currentIndex {
            if idx < 0 || idx >= editingPlaylist.entries.count {
                return false
            }
        }
        
        return true
    }
    
    private func isValidTimeFormat(_ timeString: String) -> Bool {
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        return parts.count == 3 &&
               parts[0] >= 0 && parts[0] < 24 &&
               parts[1] >= 0 && parts[1] < 60 &&
               parts[2] >= 0 && parts[2] < 60
    }
}

// MARK: - Playlist Editor Row

struct PlaylistEditorRow: View {
    let entry: PlaylistEntry
    let index: Int
    let isActive: Bool
    let isEditing: Bool
    let isReordering: Bool
    @Binding var editingTimeString: String
    @Binding var editingLabelString: String
    let onEdit: () -> Void
    let onSave: (String, String) -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Reorder handle (only shown when reordering)
            if isReordering {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            } else {
                // Entry number - fixed width
                Text("\(index + 1).")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
            
            // Time field - fixed width
            if isEditing {
                TextField("HH:mm:ss", text: $editingTimeString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 100)
                    .font(.system(.body, design: .monospaced))
            } else {
                Text(entry.timeString)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(isActive ? .blue : .primary)
                    .frame(width: 100, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Only allow editing when not reordering
                        if !isReordering {
                            onEdit()
                        }
                    }
            }
            
            // Label field - flexible width
            if isEditing {
                TextField("Label", text: $editingLabelString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
            } else {
                Text(entry.label ?? "No label")
                    .font(.body)
                    .foregroundColor(entry.label == nil ? .secondary : .primary)
                    .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Only allow editing when not reordering
                        if !isReordering {
                            onEdit()
                        }
                    }
            }
            
            // Active indicator - fixed width
            if isActive && !isEditing {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            } else {
                // Reserve space even when not active
                Circle()
                    .fill(Color.clear)
                    .frame(width: 8, height: 8)
            }
            
            // Action buttons area - FIXED WIDTH to prevent layout jumping
            // Width calculation: Save (64) + spacing (8) + Cancel (64) = 136pt
            HStack(spacing: 8) {
                if isEditing {
                    Button("Save") {
                        onSave(editingTimeString, editingLabelString)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(width: 64)
                    
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: 64)
                } else {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Delete entry")
                    .frame(width: 20)
                    
                    // Reserve remaining space to prevent layout shift
                    Spacer()
                        .frame(width: 108) // 136 - 20 (delete) - 8 (spacing) = 108
                }
            }
            .frame(width: 136, alignment: .trailing) // Fixed width prevents jumping
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

