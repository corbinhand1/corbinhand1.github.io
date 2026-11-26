import SwiftUI

struct LockView: View {
    @EnvironmentObject var store: RemoteStore
    @State private var tried = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Cue Remote is locked").font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
            Button {
                Task { await store.unlock() }
            } label: {
                Label("Unlock with \(Biometrics.name)", systemImage: "faceid")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(PressStyle())
            .padding(.horizontal, 32)
            Button("Sign out", role: .destructive) { store.signOut(); store.locked = false }
                .frame(minHeight: 44)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .task {
            // Prompt right away on first show so unlocking is one glance.
            if !tried { tried = true; await store.unlock() }
        }
    }
}
