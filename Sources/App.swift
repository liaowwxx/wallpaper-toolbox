import SwiftUI
import AppKit

private var appDidLaunch = false

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        WallpaperService.killVideoWallpaper()
    }
}

@main
struct RePKG_NativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    if !appDidLaunch {
                        appDidLaunch = true
                        viewModel.restoreWallpaperIfNeeded()
                    }
                    if viewModel.selectedDirectory != nil {
                        Task { await viewModel.scan() }
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
                Button("Open Directory...") {
                    viewModel.selectDirectory()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // Selection commands in Edit menu
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Select All") {
                    viewModel.selectAll()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(viewModel.wallpapers.isEmpty)

                Button("Deselect All") {
                    viewModel.deselectAll()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(viewModel.selectedIDs.isEmpty)
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
