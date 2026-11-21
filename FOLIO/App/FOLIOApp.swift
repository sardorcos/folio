import SwiftUI

@main
struct FOLIOApp: App {
    @StateObject private var store = FolioStore()

    var body: some Scene {
        WindowGroup {
            FolioRootView(store: store)
                .tint(FolioTheme.blue)
        }
    }
}
