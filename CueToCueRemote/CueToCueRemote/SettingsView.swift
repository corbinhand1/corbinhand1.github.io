import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("haptics") private var haptics = true
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Mac", value: store.serverAddress)
                    LabeledContent("Signed in as", value: store.username)
                    LabeledContent("Role", value: store.isAdmin ? "Administrator" : "Editor")
                    LabeledContent("Status") {
                        Label(store.live ? "Live" : "Offline", systemImage: store.live ? "dot.radiowaves.left.and.right" : "wifi.slash")
                            .foregroundStyle(store.live ? Theme.success : Color.orange)
                    }
                }
                Section {
                    if store.faceIDEnabled {
                        Toggle("\(Biometrics.name) lock", isOn: Binding(get: { true }, set: { if !$0 { store.disableFaceID() } }))
                    } else {
                        Text("Turn on \(Biometrics.name) when you sign in.").foregroundStyle(Theme.textMuted)
                    }
                } header: { Text("Security") } footer: {
                    Text("Locks after a minute in the background and hides the cue sheet in the app switcher.")
                }
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        Text("Dark").tag("dark"); Text("Light").tag("light"); Text("System").tag("system")
                    }.pickerStyle(.segmented)
                    Toggle("Haptic feedback", isOn: $haptics)
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        if store.pending.isEmpty { store.signOut(); dismiss() } else { confirmSignOut = true }
                    }.frame(minHeight: 44)
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.frame(minHeight: 44) } }
            .confirmationDialog("You have edits that haven't reached the Mac.", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out and Discard Them", role: .destructive) { store.signOut(); dismiss() }
            } message: { Text("Wait until they send, or they'll be lost.") }
        }
    }
}
