import SwiftUI

@main
struct CueToCueRemoteApp: App {
    @StateObject private var store = RemoteStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if store.isSignedIn { SheetView() } else { ConnectView() }
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .task { await store.resume() }
        }
    }
}
