//
//  WebsitePanel.swift
//  Cue to Cue
//
//  File ▸ Website…: website publishing settings in their own panel.
//  (The feature/website-show-library branch replaces the contents.)
//

import SwiftUI

struct WebsitePanel: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(systemImage: "icloud.and.arrow.up",
                        title: "Website",
                        subtitle: "Publish the current show to your website so anyone can follow it from anywhere.")
            Divider()
            WebsiteSyncSettingsView()
                .frame(minHeight: 360)
            PanelFooter { isPresented = false }
        }
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
