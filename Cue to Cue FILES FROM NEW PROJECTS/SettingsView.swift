//
//  TopSectionView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/12/24.
//



import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @Environment(\.presentationMode) var presentationMode
    var onSettingsChanged: (() -> Void)?

    @State private var newKeyword: String = ""
    @State private var newColor: Color = .white

    var body: some View {
        VStack {
            Text("Settings")
                .font(.title)
                .bold()
                .padding()

            TabView {
                // General settings tab
                Form {
                    HStack {
                        Text("Font Size")
                        Slider(value: $settingsManager.settings.fontSize, in: 10...24, step: 1)
                            .onChange(of: settingsManager.settings.fontSize) { oldValue, newValue in
                                onSettingsChanged?()
                            }
                    }
                    .padding()
                    ColorPicker("Font Color", selection: $settingsManager.settings.fontColor)
                        .padding()
                        .onChange(of: settingsManager.settings.fontColor) { oldValue, newValue in
                            onSettingsChanged?()
                        }
                    ColorPicker("Window Background Color", selection: $settingsManager.settings.backgroundColor)
                        .padding()
                        .onChange(of: settingsManager.settings.backgroundColor) { oldValue, newValue in
                            onSettingsChanged?()
                        }
                    ColorPicker("Row Background Color", selection: $settingsManager.settings.tableBackgroundColor)
                        .padding()
                        .onChange(of: settingsManager.settings.tableBackgroundColor) { oldValue, newValue in
                            onSettingsChanged?()
                        }
                }
                .tabItem {
                    Text("General")
                }

                // Timer settings tab
                Form {
                    HStack {
                        Text("Clock Font Size")
                        Slider(value: $settingsManager.settings.clockFontSize, in: 70...90, step: 2)
                            .padding(.horizontal)
                            .onChange(of: settingsManager.settings.clockFontSize) { oldValue, newValue in
                                onSettingsChanged?()
                            }
                    }
                    .padding()
                    
                    ColorPicker("Date and Time Color", selection: $settingsManager.settings.dateTimeColor)
                        .padding()
                        .onChange(of: settingsManager.settings.dateTimeColor) { oldValue, newValue in
                            onSettingsChanged?()
                        }
                    
                    ColorPicker("Countdown Color", selection: $settingsManager.settings.countdownColor)
                        .onChange(of: settingsManager.settings.countdownColor) { oldValue, newValue in
                            onSettingsChanged?()
                        }
                    
                    Toggle(isOn: $settingsManager.settings.stopAtZero) {
                        Text("Stop at Zero")
                    }
                    .padding()
                        .onChange(of: settingsManager.settings.stopAtZero) { oldValue, newValue in
                            onSettingsChanged?()
                        }
                }
                .tabItem {
                    Text("Clock & Timers")
                }

                // Row Highlights settings tab
                Form {
                    ForEach($settingsManager.settings.highlightColors) { $highlightColor in
                        HStack {
                            TextField("Keyword", text: $highlightColor.keyword)
                                .onChange(of: highlightColor.keyword) { oldValue, newValue in
                                    onSettingsChanged?()
                                }
                            ColorPicker("Color", selection: $highlightColor.color)
                                .onChange(of: highlightColor.color) { oldValue, newValue in
                                    onSettingsChanged?()
                                }
                            Button(action: {
                                if let index = settingsManager.settings.highlightColors.firstIndex(where: { $0.id == highlightColor.id }) {
                                    settingsManager.settings.highlightColors.remove(at: index)
                                    onSettingsChanged?()
                                }
                            }) {
                                Text("Remove")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                    }
                    HStack {
                        TextField("New Keyword", text: $newKeyword)
                        ColorPicker("Color", selection: $newColor)
                        Button(action: addNewHighlightColor) {
                            Text("Add")
                        }
                    }
                    .padding()
                }
                .tabItem {
                    Text("Row Text Highlight")
                }
            }

            Spacer()
            Button("Close") {
                presentationMode.wrappedValue.dismiss()
            }
            .padding()
        }
        .padding()
        .frame(width: 500)
    }

    private func addNewHighlightColor() {
        guard !newKeyword.isEmpty else { return }
        let newHighlightColor = HighlightColorSetting(keyword: newKeyword, color: newColor)
        settingsManager.settings.highlightColors.append(newHighlightColor)
        newKeyword = ""
        newColor = .white
        onSettingsChanged?()
    }
}
