import SwiftUI

/// App settings window (Cmd+,).
/// Uses the shared SettingsStore injected via environment so
/// changes here are reflected immediately in the main window.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralTab()
            }
            Tab("Wallpaper", systemImage: "display") {
                WallpaperTab()
            }
            Tab("Advanced", systemImage: "ellipsis.curlybraces") {
                AdvancedTab()
            }
        }
        .scenePadding()
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Environment(SettingsStore.self) private var settings

    private var scanModeBinding: Binding<ScanMode> {
        Binding(
            get: { settings.scanMode },
            set: { settings.scanMode = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Default Scan Mode", selection: scanModeBinding) {
                    ForEach(ScanMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            } header: {
                Text("Scanning")
            }

            Section {
                Toggle("Restore wallpaper on launch", isOn: Binding(
                    get: { settings.restoreLastWallpaper },
                    set: { settings.restoreLastWallpaper = $0 }
                ))
            } header: {
                Text("Behavior")
            } footer: {
                Text("When enabled, the last set wallpaper will be restored when the app launches.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Wallpaper Tab

private struct WallpaperTab: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section {
                Toggle("Mute video wallpaper", isOn: Binding(
                    get: { settings.wallpaperMuted },
                    set: { settings.wallpaperMuted = $0 }
                ))

                Toggle("Auto-replace static wallpaper with first frame", isOn: Binding(
                    get: { settings.autoReplaceStaticWithFirstFrame },
                    set: { settings.autoReplaceStaticWithFirstFrame = $0 }
                ))
            } header: {
                Text("Playback")
            } footer: {
                Text("When setting a video wallpaper, also capture the first frame as a static fallback for spaces and login screen.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced Tab

private struct AdvancedTab: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section {
                TextField("e.g. .png,.jpg", text: Binding(
                    get: { settings.ignoreExtensions },
                    set: { settings.ignoreExtensions = $0 }
                ))
                    .accessibilityLabel("Ignore extensions")

                TextField("e.g. .png,.jpg", text: Binding(
                    get: { settings.onlyExtensions },
                    set: { settings.onlyExtensions = $0 }
                ))
                    .accessibilityLabel("Only extensions")
            } header: {
                Text("Extraction Filters")
            } footer: {
                Text("Extensions to ignore (-i) or include (-e) when extracting packages.")
            }

            Section {
                Toggle("Convert TEX files (-t)", isOn: Binding(
                    get: { settings.convertTEX },
                    set: { settings.convertTEX = $0 }
                ))
                Toggle("No TEX conversion", isOn: Binding(
                    get: { settings.noTEXConvert },
                    set: { settings.noTEXConvert = $0 }
                ))
                Toggle("Single directory (-s)", isOn: Binding(
                    get: { settings.singleDir },
                    set: { settings.singleDir = $0 }
                ))
                Toggle("Recursive (-r)", isOn: Binding(
                    get: { settings.recursive },
                    set: { settings.recursive = $0 }
                ))
                Toggle("Copy project.json (-c)", isOn: Binding(
                    get: { settings.copyProject },
                    set: { settings.copyProject = $0 }
                ))
                Toggle("Use name (-n)", isOn: Binding(
                    get: { settings.useName },
                    set: { settings.useName = $0 }
                ))
                Toggle("Overwrite existing", isOn: Binding(
                    get: { settings.overwrite },
                    set: { settings.overwrite = $0 }
                ))
                Toggle("Debug info (-d)", isOn: Binding(
                    get: { settings.debugInfo },
                    set: { settings.debugInfo = $0 }
                ))
                Toggle("Copy only (skip extraction)", isOn: Binding(
                    get: { settings.copyOnly },
                    set: { settings.copyOnly = $0 }
                ))
            } header: {
                Text("Default Extraction Options")
            }
        }
        .formStyle(.grouped)
    }
}
