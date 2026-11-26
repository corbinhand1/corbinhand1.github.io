//
//  ConnectionMonitorView.swift
//  Cue to Cue
//
//  Window ▸ Connected Viewers…: how to join (link + QR code) first, then
//  who is watching right now, then who left recently.
//

import SwiftUI

struct ConnectionMonitorView: View {
    @Binding var isPresented: Bool
    @ObservedObject var webServer: WebServer
    @State private var refreshTimer: Timer?
    @State private var copied = false
    @State private var showRecent = false

    private var isRunning: Bool { webServer.serverStatus.isRunning }
    private var hasAddress: Bool {
        !webServer.localIPAddress.isEmpty && webServer.localIPAddress != "Unknown"
    }
    private var viewerURL: String { "http://\(webServer.getConnectionString())" }
    private var active: [ClientSession] { webServer.getClientSessionsStable() }
    private var recent: [ClientSession] { webServer.getInactiveClientSessions() }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(systemImage: "network",
                        title: "Connected Viewers",
                        subtitle: "Anyone on this network can follow the show live in a browser. No account needed.",
                        tint: .teal)
            Form {
                joinSection
                watchingSection
                if !recent.isEmpty { recentSection }
            }
            .formStyle(.grouped)
            PanelFooter(leading: { serverStatusLabel }, done: { isPresented = false })
        }
        .frame(width: 560, height: 640)
        .onAppear {
            webServer.refreshPublishedProperties()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                webServer.refreshPublishedProperties()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    // MARK: Join

    private var joinSection: some View {
        Section {
            if isRunning && hasAddress {
                HStack(alignment: .center, spacing: 18) {
                    if let qr = QRCode.image(for: viewerURL, size: 116) {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 116, height: 116)
                            .padding(8)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityLabel(Text("QR code for \(viewerURL)"))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Scan with a phone or tablet camera, or type this address into any browser:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(viewerURL)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(viewerURL, forType: .string)
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                            } label: {
                                Label(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            Button {
                                if let url = URL(string: viewerURL) { NSWorkspace.shared.open(url) }
                            } label: {
                                Label("Open in Browser", systemImage: "safari")
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } else if !isRunning {
                Label("The viewer server isn't running, so devices can't connect.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("This Mac isn't connected to a network. Join the same Wi-Fi or wired network as the viewing devices.",
                      systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Join from Another Device")
        } footer: {
            Text("Devices must be on the same network as this Mac. Viewers see the cue sheet and clocks update live; they can't change anything unless they sign in.")
        }
    }

    // MARK: Watching

    private var watchingSection: some View {
        Section {
            if active.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No one is watching yet.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                ForEach(active) { session in
                    ViewerRow(session: session, isActive: true)
                }
            }
        } header: {
            HStack {
                Text("Watching Now")
                Spacer()
                if !active.isEmpty {
                    Text("\(active.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Recent

    private var recentSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showRecent) {
                ForEach(recent) { session in
                    ViewerRow(session: session, isActive: false)
                }
            } label: {
                Text("\(recent.count) device\(recent.count == 1 ? "" : "s") disconnected recently")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Status

    private var serverStatusLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(isRunning ? "Viewer server running on port \(String(webServer.serverStatus.port))" : "Viewer server stopped")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// One device: icon, name, browser and address, and how long ago.
private struct ViewerRow: View {
    let session: ClientSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.deviceName.isEmpty ? session.deviceType : session.deviceName)
                    .fontWeight(.medium)
                Text("\(session.browserType) · \(session.ipAddress)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Group {
                if isActive {
                    Text("joined ") + Text(session.firstSeen, style: .relative) + Text(" ago")
                } else {
                    Text("left ") + Text(session.lastSeen, style: .relative) + Text(" ago")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        let type = session.deviceType.lowercased()
        if type.contains("ipad") || type.contains("tablet") { return "ipad" }
        if type.contains("iphone") || type.contains("ipod") || type.contains("mobile") || type.contains("android") { return "iphone" }
        if type.contains("mac") { return "laptopcomputer" }
        return "desktopcomputer"
    }
}
