import SwiftUI

@main
struct AlbumsApp: App {
    @State private var store = AlbumStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Albums saved from the share sheet were written by the extension while we were away.
            store.reload()
            Task { await store.resolvePendingAlbums() }
        }
    }
}
