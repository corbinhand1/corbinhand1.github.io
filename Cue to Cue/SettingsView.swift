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
                    }
                    .padding()
                    ColorPicker("Font Color", selection: $settingsManager.settings.fontColor)
                        .padding()
                    ColorPicker("Window Background Color", selection: $settingsManager.settings.backgroundColor)
                        .padding()
                    ColorPicker("Row Background Color", selection: $settingsManager.settings.tableBackgroundColor)
                        .padding()
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
                    }
                    .padding()
                    
                    ColorPicker("Date and Time Color", selection: $settingsManager.settings.dateTimeColor)
                        .padding()
                    
                    ColorPicker("Countdown Color", selection: $settingsManager.settings.countdownColor)
                        
                    
                    Toggle(isOn: $settingsManager.settings.stopAtZero) {
                        Text("Stop at Zero")
                    }
                    .padding()
                }
                .tabItem {
                    Text("Clock & Timers")
                }

                // Row Highlights settings tab
                Form {
                    ForEach($settingsManager.settings.highlightColors) { $highlightColor in
                        HStack {
                            TextField("Keyword", text: $highlightColor.keyword)
                            ColorPicker("Color", selection: $highlightColor.color)
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
    }
}
