import SwiftUI

/// App settings window (Cmd+,).
/// Uses @AppStorage directly — Apple's recommended pattern for Settings scenes.
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
    @AppStorage("scanMode") private var scanModeRaw = ScanMode.subdir.rawValue
    @AppStorage("restoreLastWallpaper") private var restoreLastWallpaper = false

    private var scanModeBinding: Binding<ScanMode> {
        Binding(
            get: { ScanMode(rawValue: scanModeRaw) ?? .subdir },
            set: { scanModeRaw = $0.rawValue }
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
                Toggle("Restore wallpaper on launch", isOn: $restoreLastWallpaper)
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
    @AppStorage("wallpaperMuted") private var wallpaperMuted = true
    @AppStorage("autoReplaceStatic") private var autoReplaceStaticWithFirstFrame = false

    var body: some View {
        Form {
            Section {
                Toggle("Mute video wallpaper", isOn: $wallpaperMuted)

                Toggle("Auto-replace static wallpaper with first frame", isOn: $autoReplaceStaticWithFirstFrame)
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
    @AppStorage("ignoreExts") private var ignoreExts = ""
    @AppStorage("onlyExts") private var onlyExts = ""
    @AppStorage("convertTex") private var convertTex = false
    @AppStorage("noTexConvert") private var noTexConvert = false
    @AppStorage("singleDir") private var singleDir = false
    @AppStorage("recursive") private var recursive = true
    @AppStorage("copyProject") private var copyProject = false
    @AppStorage("useName") private var useName = false
    @AppStorage("overwrite") private var overwrite = false
    @AppStorage("debugInfo") private var debugInfo = false
    @AppStorage("copyOnly") private var copyOnly = false

    var body: some View {
        Form {
            Section {
                TextField("e.g. .png,.jpg", text: $ignoreExts)
                    .accessibilityLabel("Ignore extensions")

                TextField("e.g. .png,.jpg", text: $onlyExts)
                    .accessibilityLabel("Only extensions")
            } header: {
                Text("Extraction Filters")
            } footer: {
                Text("Extensions to ignore (-i) or include (-e) when extracting packages.")
            }

            Section {
                Toggle("Convert TEX files (-t)", isOn: $convertTex)
                Toggle("No TEX conversion", isOn: $noTexConvert)
                Toggle("Single directory (-s)", isOn: $singleDir)
                Toggle("Recursive (-r)", isOn: $recursive)
                Toggle("Copy project.json (-c)", isOn: $copyProject)
                Toggle("Use name (-n)", isOn: $useName)
                Toggle("Overwrite existing", isOn: $overwrite)
                Toggle("Debug info (-d)", isOn: $debugInfo)
                Toggle("Copy only (skip extraction)", isOn: $copyOnly)
            } header: {
                Text("Default Extraction Options")
            }
        }
        .formStyle(.grouped)
    }
}
