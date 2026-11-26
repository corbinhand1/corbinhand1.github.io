//
//  SettingsView.swift
//  Cue to Cue
//
//  The app's Settings window (Cue to Cue ▸ Settings…, ⌘,): a standard macOS
//  Settings scene with toolbar tabs and grouped forms. Website publishing
//  has its own panel (File ▸ Website…).
//

import SwiftUI

struct SettingsView: View {
    enum Tab: String, Hashable, CaseIterable {
        case general, appearance, clocks, highlights, shortcuts
    }

    /// Persisted so menus can open a specific tab (Help ▸ Keyboard Shortcuts…).
    static let selectedTabKey = "settings.selectedTab"

    @ObservedObject var settingsManager: SettingsManager
    @AppStorage(SettingsView.selectedTabKey) private var selectedTab: Tab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsPane(settingsManager: settingsManager)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            AppearanceSettingsPane(settingsManager: settingsManager)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(Tab.appearance)
            ClockSettingsPane(settingsManager: settingsManager)
                .tabItem { Label("Clocks", systemImage: "clock") }
                .tag(Tab.clocks)
            HighlightSettingsPane(settingsManager: settingsManager)
                .tabItem { Label("Highlights", systemImage: "highlighter") }
                .tag(Tab.highlights)
            KeyboardShortcutsView(shortcutsManager: settingsManager.shortcutsManager)
                .frame(minHeight: 420)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(Tab.shortcuts)
        }
        .frame(width: 560)
    }
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @ObservedObject var settingsManager: SettingsManager

    var body: some View {
        Form {
            Section {
                LabeledContent("Cue text size") {
                    HStack(spacing: 10) {
                        Slider(value: $settingsManager.settings.fontSize, in: 10...24, step: 1)
                            .frame(width: 200)
                        Text("\(Int(settingsManager.settings.fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Cue Sheet")
            } footer: {
                Text("Sets the size of text in the cue table.")
            }

            Section {
                Toggle("Stop countdown at zero", isOn: $settingsManager.settings.stopAtZero)
            } header: {
                Text("Countdown")
            } footer: {
                Text("When off, the countdown keeps running past zero.")
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 300)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsPane: View {
    @ObservedObject var settingsManager: SettingsManager

    var body: some View {
        Form {
            Section {
                ColorPicker("Text", selection: $settingsManager.settings.fontColor, supportsOpacity: false)
                ColorPicker("Window background", selection: $settingsManager.settings.backgroundColor, supportsOpacity: false)
                ColorPicker("Row background", selection: $settingsManager.settings.tableBackgroundColor, supportsOpacity: false)
            } header: {
                Text("Colors")
            } footer: {
                Text("Dark backgrounds are easiest on the eyes in a dark control room.")
            }

            Section {
                AppearancePreview(settings: settingsManager.settings)
                    .frame(maxWidth: .infinity)
            } header: {
                Text("Preview")
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 380)
    }
}

/// Small live sample of a live row and a normal row.
private struct AppearancePreview: View {
    let settings: Settings

    var body: some View {
        VStack(spacing: 4) {
            row(number: "203", text: "Preset 3 + VT Opening", live: true)
            row(number: "204", text: "Preset 5 + LX Show Blurple", live: false)
        }
        .padding(10)
        .background(settings.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview of the cue table colors"))
    }

    private func row(number: String, text: String, live: Bool) -> some View {
        HStack(spacing: 10) {
            CueStateChip(state: live ? .live : .none)
                .frame(width: 34, alignment: .leading)
            Text(number).frame(width: 36, alignment: .leading)
            Text(text)
            Spacer()
        }
        .font(.system(size: 12, weight: live ? .bold : .regular))
        .foregroundColor(live ? .white : settings.fontColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            ZStack(alignment: .leading) {
                settings.tableBackgroundColor
                if live {
                    CueRowStyle.live.opacity(0.24)
                    CueRowStyle.live.frame(width: 3)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Clocks

private struct ClockSettingsPane: View {
    @ObservedObject var settingsManager: SettingsManager

    var body: some View {
        Form {
            Section {
                LabeledContent("Clock size") {
                    HStack(spacing: 10) {
                        Slider(value: $settingsManager.settings.clockFontSize, in: 40...120, step: 2)
                            .frame(width: 200)
                        Text("\(Int(settingsManager.settings.clockFontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                ColorPicker("Time of day", selection: $settingsManager.settings.dateTimeColor, supportsOpacity: false)
                ColorPicker("Countdowns", selection: $settingsManager.settings.countdownColor, supportsOpacity: false)
            } header: {
                Text("Clocks")
            } footer: {
                Text("Larger clocks are easier to read from across the room; the cue list gets less space.")
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 300)
    }
}

// MARK: - Highlights

private struct HighlightSettingsPane: View {
    @ObservedObject var settingsManager: SettingsManager
    @State private var newKeyword = ""
    @State private var newColor: Color = .yellow

    var body: some View {
        Form {
            Section {
                if settingsManager.settings.highlightColors.isEmpty {
                    Text("No highlights yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach($settingsManager.settings.highlightColors) { $highlight in
                    HStack(spacing: 10) {
                        ColorPicker("", selection: $highlight.color, supportsOpacity: false)
                            .labelsHidden()
                        TextField("Keyword", text: $highlight.keyword)
                            .textFieldStyle(.plain)
                            .foregroundColor(highlight.color)
                            .fontWeight(.medium)
                        Spacer()
                        Button(role: .destructive) {
                            remove(highlight.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \u{201C}\(highlight.keyword)\u{201D}")
                        .accessibilityLabel(Text("Remove \(highlight.keyword)"))
                    }
                }
            } header: {
                Text("Keyword Colors")
            } footer: {
                Text("A cue whose text contains a keyword is shown in that color, on the Mac and in the web viewer. Matching ignores upper and lower case.")
            }

            Section {
                HStack(spacing: 10) {
                    ColorPicker("", selection: $newColor, supportsOpacity: false)
                        .labelsHidden()
                    TextField("New keyword, e.g. \u{201C}video\u{201D}", text: $newKeyword)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Add a Keyword")
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 380)
    }

    private func add() {
        let keyword = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return }
        settingsManager.settings.highlightColors.append(HighlightColorSetting(keyword: keyword, color: newColor))
        newKeyword = ""
    }

    private func remove(_ id: UUID) {
        settingsManager.settings.highlightColors.removeAll { $0.id == id }
    }
}
