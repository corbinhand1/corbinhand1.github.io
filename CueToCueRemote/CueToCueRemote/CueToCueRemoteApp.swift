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
            .task { await store.resume() }
        }
    }
}
