import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var store: RemoteStore
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("mac.tailnet.ts.net:8080", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Mac address")
                } footer: {
                    Text("The address of the Mac running Cue to Cue: a Tailscale name, a tunnel URL, or a local IP. Use Tailscale or an https tunnel when away from home so your password isn't sent in the clear.")
                }
                Section("Account") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }
                if let e = store.error {
                    Section { Text(e).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await store.signIn(address: address, username: username, password: password) }
                    } label: {
                        HStack {
                            Text("Connect")
                            if store.busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(address.isEmpty || username.isEmpty || password.isEmpty || store.busy)
                }
            }
            .navigationTitle("Cue to Cue Remote")
            .onAppear {
                address = store.serverAddress
                username = store.username
            }
        }
    }
}
