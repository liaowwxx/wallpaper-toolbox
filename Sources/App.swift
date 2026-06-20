import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        WallpaperService.killVideoWallpaper()
        SceneWallpaperRendererService.stopPersistedRendererProcesses()
    }
}

@main
struct WallPaperGalleryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel: AppViewModel!
    @State private var settingsStore: SettingsStore!

    init() {
        let store = SettingsStore()
        _settingsStore = State(initialValue: store)
        _viewModel = State(initialValue: AppViewModel(settingsStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .environment(settingsStore)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    if !viewModel.appDidLaunch {
                        viewModel.appDidLaunch = true
                        viewModel.restoreWallpaperIfNeeded()
                        Task { await viewModel.loadInitialLibrary() }
                    }
                }
        }
        .defaultSize(width: 1024, height: 700)
        .windowResizability(.contentMinSize)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button(L10n.t("Open Directory...", settingsStore.appLanguage)) {
                    viewModel.selectDirectory()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // Selection commands in Edit menu
            CommandGroup(after: .pasteboard) {
                Divider()
                Button(L10n.t("Select All", settingsStore.appLanguage)) {
                    viewModel.selectAll()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(viewModel.wallpapers.isEmpty)

                Button(L10n.t("Deselect All", settingsStore.appLanguage)) {
                    viewModel.deselectAll()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(viewModel.selectedIDs.isEmpty)
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(viewModel)
                .environment(settingsStore)
        }
        #endif
    }
}
