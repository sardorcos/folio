import SwiftUI

@main
struct FOLIOApp: App {
    @StateObject private var store = FolioStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            FolioRootView(store: store)
                .tint(FolioTheme.blue)
                // Файлы из расширения «Поделиться» забираются при запуске и при каждом возвращении в приложение.
                .task { store.importSharedFiles() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.importSharedFiles() }
                }
        }
    }
}
