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
    @Environment(RemoteLibraryViewModel.self) private var library

    var body: some View {
        @Bindable var library = library

        TabView(selection: $library.selectedTab) {
            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "photo.on.rectangle.angled")
            }
            .tag(AppTab.library)

            NavigationStack {
                CollectionsView()
            }
            .tabItem {
                Label("Collections", systemImage: "rectangle.stack.badge.person.crop")
            }
            .tag(AppTab.collections)

            NavigationStack {
                ConnectionSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
    }
}
