import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var store: RemoteStore
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var useFaceID = Biometrics.isAvailable
    @State private var pickedName: String?
    @State private var showManual = false
    @StateObject private var finder = MacFinder()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(finder.found) { mac in
                        Button {
                            if let a = mac.address { address = a; pickedName = mac.name; Haptics.select() }
                            else { finder.start() }          // not resolved yet: look again
                        } label: {
                            HStack {
                                Label(mac.name, systemImage: "desktopcomputer").foregroundStyle(Theme.text)
                                Spacer()
                                if pickedName == mac.name { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                                else if mac.address == nil { ProgressView() }
                            }.frame(minHeight: 44)
                        }
                    }
                    if finder.found.isEmpty {
                        HStack(spacing: 8) {
                            if finder.searching { ProgressView() }
                            Text(finder.searching ? "Looking for your Mac on this Wi-Fi…" : "No Mac found on this network.")
                                .foregroundStyle(Theme.textMuted)
                        }.frame(minHeight: 44)
                    }
                } header: { Text("On this network") }
                footer: { Text("Open Cue to Cue on your Mac and join the same Wi-Fi. It shows up here automatically.") }

                Section {
                    DisclosureGroup("Away from home or not listed", isExpanded: $showManual) {
                        TextField("mac.tailnet.ts.net:8080", text: $address)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .onChange(of: address) { _, new in
                                if let n = pickedName, finder.found.first(where: { $0.name == n })?.address != new { pickedName = nil }
                            }
                    }
                } footer: {
                    if showManual { Text("Use your Mac's Tailscale name or a tunnel address so it works outside your Wi-Fi. Prefer Tailscale or https so your password isn't sent in the clear.") }
                }
                Section("Account") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }
                if store.faceIDEnabled {
                    Section {
                        Button {
                            Task { await store.signInWithFaceID() }
                        } label: {
                            Label("Sign in with \(Biometrics.name)", systemImage: "faceid")
                                .font(.headline).frame(minHeight: 44)
                        }
                    }
                }
                if Biometrics.isAvailable {
                    Section {
                        Toggle("Use \(Biometrics.name) next time", isOn: $useFaceID)
                    } footer: {
                        Text("Your password is kept in the secure keychain and only released after \(Biometrics.name).")
                    }
                }
                if let e = store.error {
                    Section {
                        Text(e).foregroundStyle(Theme.danger)
                        if e.contains("Local Network") {
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }.frame(minHeight: 44)
                        }
                    }
                }
                Section {
                    Button {
                        Task { await store.signIn(address: address, username: username, password: password, rememberWithFaceID: useFaceID, foundName: pickedName) }
                    } label: {
                        HStack {
                            Text("Connect")
                            if store.busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(address.isEmpty || username.isEmpty || password.isEmpty || store.busy)
                }
            }
            .frame(maxWidth: 560)               // keep the form compact on iPad
            .frame(maxWidth: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Cue to Cue Remote")
            .onAppear {
                address = store.serverAddress
                username = store.username
                showManual = !store.remoteAddress.isEmpty && store.bonjourName.isEmpty
                finder.start()
            }
            .onDisappear { finder.stop() }
            .onChange(of: finder.found) { _, list in
                // First Mac found on the network: select it so signing in is just username + password.
                if pickedName == nil, address.isEmpty || address == store.serverAddress && !showManual,
                   let mac = list.first(where: { $0.address != nil }), let a = mac.address { address = a; pickedName = mac.name }
            }
        }
    }
}
