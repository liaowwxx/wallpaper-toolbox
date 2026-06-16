import SwiftUI

@main
struct WallpaperGalleryiOSDemoApp: App {
    @State private var library = RemoteLibraryViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .task {
                    await library.loadSampleLibrary()
                }
        }
    }
}

private struct RootView: View {
    var body: some View {
        LibraryView()
    }
}
