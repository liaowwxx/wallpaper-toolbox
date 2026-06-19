import AppKit
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
        .frame(width: 680, height: 540)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(SettingsStore.self) private var settings
    @State private var selectedLibraryMode: LibraryMode = .local

    private var libraryModeBinding: Binding<LibraryMode> {
        Binding(
            get: { selectedLibraryMode },
            set: { mode in
                selectedLibraryMode = mode
                settings.libraryMode = mode
                if mode == .local {
                    viewModel.switchToLocalLibrary()
                } else {
                    viewModel.switchToRemoteLibrary()
                }
            }
        )
    }

    private var scanModeBinding: Binding<ScanMode> {
        Binding(
            get: { settings.scanMode },
            set: { settings.scanMode = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Library Mode", selection: libraryModeBinding) {
                    ForEach(LibraryMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if selectedLibraryMode == .remote {
                    TextField("Server URL", text: Binding(
                        get: { settings.remoteServerURL },
                        set: { settings.remoteServerURL = $0 }
                    ))
                    TextField("Username", text: Binding(
                        get: { settings.remoteUsername },
                        set: { settings.remoteUsername = $0 }
                    ))
                    SecureField("Password", text: Binding(
                        get: { settings.remotePassword },
                        set: { settings.remotePassword = $0 }
                    ))
                    HStack {
                        Text(settings.remoteDownloadDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Change...") {
                            viewModel.selectRemoteDownloadDirectory()
                        }
                    }
                    HStack {
                        if viewModel.isRemoteConnecting {
                            ProgressView().scaleEffect(0.65)
                        }
                        Button {
                            Task { await viewModel.connectRemoteLibrary() }
                        } label: {
                            Label("Connect", systemImage: "network")
                        }
                        .disabled(viewModel.isRemoteConnecting)
                        if !viewModel.remoteConnectionStatus.isEmpty {
                            Text(viewModel.remoteConnectionStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } header: {
                Text("Library")
            } footer: {
                Text("Remote mode connects to the Windows demo server and downloads original wallpaper folders into the selected local directory before using the normal local wallpaper pipeline.")
            }

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
        .onAppear {
            selectedLibraryMode = settings.libraryMode
        }
    }
}

// MARK: - Wallpaper Tab

private struct WallpaperTab: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(SettingsStore.self) private var settings

    @State private var sceneUpscalingEnabled = true
    @State private var sceneUpscalingPercent = 70.0
    @State private var sceneFPSCap = 60.0

    private var maxSceneFPS: Double {
        Double(NSScreen.screens.map(Self.refreshRate).max() ?? 60)
    }

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

            Section {
                Toggle("MetalFX upscaling for scene wallpapers", isOn: $sceneUpscalingEnabled)

                if sceneUpscalingEnabled {
                    sceneSliderRow(
                        title: "Render scale",
                        valueText: "\(Int(sceneUpscalingPercent))%",
                        value: $sceneUpscalingPercent,
                        range: 30...100,
                        step: 5
                    )
                }

                sceneSliderRow(
                    title: "Scene FPS limit",
                    valueText: "\(Int(sceneFPSCap)) FPS",
                    value: $sceneFPSCap,
                    range: 30...max(60, maxSceneFPS),
                    step: 1
                )

                HStack {
                    Spacer()
                    Button {
                        saveAndReapplySceneRenderingSettings()
                    } label: {
                        Label("Save & Reapply", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("s", modifiers: [.command])
                }
            } header: {
                Text("Scene Rendering")
            } footer: {
                Text("Scene wallpapers use the lower of this FPS limit and the display refresh rate. MetalFX renders at a lower internal resolution, then upscales to reduce GPU load.")
            }
        }
        .formStyle(.grouped)
        .onAppear { loadSceneRenderingSettings() }
    }

    private func sceneSliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text(title)
                    .gridColumnAlignment(.leading)
                Text(valueText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
                Slider(value: value, in: range, step: step)
                    .frame(minWidth: 320)
            }
        }
    }

    private func loadSceneRenderingSettings() {
        sceneUpscalingEnabled = settings.sceneUpscalingEnabled
        sceneUpscalingPercent = settings.sceneUpscalingPercent
        sceneFPSCap = min(settings.sceneFPSCap, max(60, maxSceneFPS))
    }

    private func saveAndReapplySceneRenderingSettings() {
        settings.sceneUpscalingEnabled = sceneUpscalingEnabled
        settings.sceneUpscalingPercent = sceneUpscalingPercent
        settings.sceneFPSCap = sceneFPSCap
        viewModel.reapplyCurrentSceneWallpaper()
    }

    private static func refreshRate(for screen: NSScreen) -> Int {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let mode = CGDisplayCopyDisplayMode(CGDirectDisplayID(number.uint32Value)) else {
            return 60
        }
        let rate = mode.refreshRate
        guard rate > 0 else { return 60 }
        return max(30, min(240, Int(rate.rounded())))
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
