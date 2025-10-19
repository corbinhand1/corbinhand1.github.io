//
//  ConnectionMonitorView.swift
//  Cue to Cue
//
//  Created by Corbin Hand on 8/31/24.
//

import SwiftUI

struct ConnectionMonitorView: View {
    @Binding var isPresented: Bool
    @ObservedObject var webServer: WebServer
    @State private var refreshTimer: Timer?
    
    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(spacing: 0) {
                headerSection
                connectionStatsSection
                serverInfoSection
                activeConnectionsSection
                previouslyActiveClientsSection
                Spacer(minLength: 20)
            }
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 700, idealHeight: 800)
        .background(.ultraThinMaterial)
        .onAppear {
            // Start refresh timer
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                webServer.refreshPublishedProperties()
            }
        }
        .onDisappear {
            // Stop refresh timer
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
    

    
    // MARK: - View Sections
    
    private var headerSection: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                Text("Connection Monitor")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    let connectionString = webServer.getConnectionString()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(connectionString, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(ConnectionMonitorButtonStyle(color: .green))
                .help("Copy \(webServer.getConnectionString()) to clipboard")
                
                Button(action: {
                    webServer.forceCleanupInactiveSessions()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(ConnectionMonitorButtonStyle(color: .purple))
                .help("Force Cleanup Inactive Sessions")
                
                Button(action: {
                    webServer.debugConnectionCount()
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(ConnectionMonitorButtonStyle(color: .orange))
                .help("Debug Connections")
                
                Button(action: {
                    webServer.refreshPublishedProperties()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(ConnectionMonitorButtonStyle(color: .blue))
                .help("Refresh Data")
                
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(ConnectionMonitorButtonStyle(color: .red))
                .help("Close Window")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Rectangle()
                .fill(.regularMaterial)
                .overlay(
                    Rectangle()
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
    
    private var connectionStatsSection: some View {
        HStack(spacing: 16) {
            StatCard(title: "Active Clients", value: "\(webServer.getClientSessionCount())", color: .green, icon: "person.2")
            StatCard(title: "Inactive Clients", value: "\(webServer.getInactiveClientSessionCount())", color: .orange, icon: "clock.arrow.circlepath")
            StatCard(title: "Server Status", value: webServer.serverStatus.isRunning ? "Running" : "Stopped", color: webServer.serverStatus.isRunning ? .green : .red, icon: "server.rack")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }
    
    private var serverInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "server.rack")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                
                Text("Server Information")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                InfoCard(label: "IP Address", value: webServer.localIPAddress, icon: "network")
                InfoCard(label: "Status", value: webServer.serverStatus.isRunning ? "Running" : "Stopped", icon: "circle.fill", statusColor: webServer.serverStatus.isRunning ? .green : .red)
            }
            
            // Copy connection string section
            VStack(spacing: 8) {
                HStack {
                    Text("Connection String")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        let connectionString = webServer.getConnectionString()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(connectionString, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Copy \(webServer.getConnectionString()) to clipboard")
                }
                
                HStack {
                    Text(webServer.getConnectionString())
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.ultraThinMaterial)
                        )
                    
                    Spacer()
                }
            }
            .padding(.top, 8)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
    }
    
    private var activeConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.2")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                
                Text("Active Clients")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            if !webServer.getClientSessionsStable().isEmpty {
                let clientSessions = webServer.getClientSessionsStable()
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16, content: {
                    ForEach(clientSessions) { session in
                        ClientSessionCard(session: session, webServer: webServer)
                    }
                })
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text("No Active Clients")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    Text("When devices connect to your web viewer, they will appear here")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
    }
    
    private var previouslyActiveClientsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                
                Text("Previously Active Clients")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            let inactiveSessions = webServer.getInactiveClientSessions()
            
            if !inactiveSessions.isEmpty {
                VStack(spacing: 12) {
                    ForEach(inactiveSessions) { session in
                        HStack {
                            // Device name
                            Text(session.deviceName)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            // Timestamps
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Active: \(session.firstSeen, style: .time)")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                
                                Text("Inactive: \(session.lastSeen, style: .time)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                                )
                        )
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    
                    Text("No Previously Active Clients")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    Text("Clients that disconnect will appear here")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
    }
}



// MARK: - Custom Button Style
struct ConnectionMonitorButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
                    .opacity(configuration.isPressed ? 0.7 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Modern Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Modern Info Card
struct InfoCard: View {
    let label: String
    let value: String
    let icon: String
    var statusColor: Color?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(statusColor ?? .accentColor)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Client Session Card
struct ClientSessionCard: View {
    let session: ClientSession
    let webServer: WebServer
    
    var body: some View {
        VStack(spacing: 12) {
            // Join time indicator at top
            HStack {
                Spacer()
                
                // Show join time
                Text(session.firstSeen, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                    )
            }
            
            Spacer()
            
            // Device name in center
            Text(session.deviceName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.green)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
            
            // IP address below device name
            Text(session.ipAddress)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Spacer()
            
            // Browser and device type at bottom
            VStack(spacing: 6) {
                Text(session.browserType)
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.2))
                    )
                
                Text(session.deviceType)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.2))
                    )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
}





#Preview {
    ConnectionMonitorView(isPresented: .constant(true), webServer: WebServer())
}
