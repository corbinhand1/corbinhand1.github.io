import SwiftUI

@main
struct CueToCueRemoteApp: App {
    @StateObject private var store = RemoteStore()
    @Environment(\.scenePhase) private var phase
    @State private var backgroundedAt: Date?

    /// How long the app can be away before Face ID is required again.
    private let grace: TimeInterval = 60

    var body: some Scene {
        WindowGroup {
            ZStack {
                if store.locked {
                    LockView()
                } else if store.isSignedIn {
                    SheetView()
                } else {
                    ConnectView()
                }
                // Hide the cue sheet in the app switcher when Face ID protection is on.
                if phase != .active && store.faceIDEnabled { Theme.background.ignoresSafeArea() }
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .task { if !store.locked { await store.resume() } }
            .onChange(of: phase) { _, new in
                switch new {
                case .background: backgroundedAt = Date()
                case .active:
                    if store.faceIDEnabled, store.isSignedIn, let t = backgroundedAt,
                       Date().timeIntervalSince(t) > grace { store.locked = true }
                    backgroundedAt = nil
                default: break
                }
            }
        }
    }
}
