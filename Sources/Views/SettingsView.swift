import AppKit
import SwiftUI

/// App settings window (Cmd+,).
/// Uses the shared SettingsStore injected via environment so
/// changes here are reflected immediately in the main window.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        TabView {
            Tab(L10n.t("Library", settings.appLanguage), systemImage: "books.vertical") {
                GeneralTab()
            }
            Tab(L10n.t("Wallpaper", settings.appLanguage), systemImage: "display") {
                WallpaperTab()
            }
            Tab(L10n.t("Extraction", settings.appLanguage), systemImage: "shippingbox") {
                AdvancedTab()
            }
        }
        .scenePadding()
        .frame(width: 720, height: 600)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(SettingsStore.self) private var settings
    @State private var selectedLibraryMode: LibraryMode = .local
    @State private var repkgPath = ""

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
            get: { viewModel.scanMode },
            set: { mode in
                viewModel.scanMode = mode
                settings.scanMode = mode
                viewModel.saveState()
                if viewModel.selectedDirectory != nil {
                    Task { await viewModel.scan() }
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker(L10n.t("Language", settings.appLanguage), selection: Binding(
                    get: { settings.appLanguage },
                    set: { settings.appLanguage = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName(in: settings.appLanguage)).tag(language)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(L10n.t("Language", settings.appLanguage))
            }

            Section {
                Picker(L10n.t("Library Mode", settings.appLanguage), selection: libraryModeBinding) {
                    ForEach(LibraryMode.allCases, id: \.self) { mode in
                        Text(L10n.t(mode.label, settings.appLanguage)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if selectedLibraryMode == .local {
                    localLibraryControls
                } else {
                    remoteLibraryControls
                }
            } header: {
                Text(L10n.t("Library", settings.appLanguage))
            } footer: {
                Text(L10n.t("Local mode scans a folder on this Mac. Remote mode downloads original wallpaper folders before using the same local pipeline.", settings.appLanguage))
            }

            Section {
                Picker(L10n.t("Default Scan Mode", settings.appLanguage), selection: scanModeBinding) {
                    ForEach(ScanMode.allCases, id: \.self) { mode in
                        Text(L10n.t(mode.label, settings.appLanguage)).tag(mode)
                    }
                }
            } header: {
                Text(L10n.t("Scanning", settings.appLanguage))
            }

            Section {
                directoryRow(
                    title: L10n.t("Output", settings.appLanguage),
                    path: viewModel.outputDirectory?.path,
                    emptyTitle: L10n.t("No output directory selected", settings.appLanguage)
                ) {
                    viewModel.selectOutputDirectory()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("RePKG Binary", settings.appLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(L10n.t("Default bundled RePKG", settings.appLanguage), text: $repkgPath)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button {
                            browseRePKGBinary()
                        } label: {
                            Label(L10n.t("Browse", settings.appLanguage), systemImage: "folder")
                        }
                        Button {
                            repkgPath = ""
                            unsetenv("REPKG_PATH")
                        } label: {
                            Label(L10n.t("Use Bundled", settings.appLanguage), systemImage: "arrow.uturn.backward")
                        }
                        .disabled(repkgPath.isEmpty)
                    }
                }
                .onChange(of: repkgPath) {
                    if repkgPath.isEmpty {
                        unsetenv("REPKG_PATH")
                    } else {
                        setenv("REPKG_PATH", repkgPath, 1)
                    }
                }
            } header: {
                Text(L10n.t("Directories", settings.appLanguage))
            } footer: {
                Text(L10n.t("The bundled RePKG binary is used when no override path is set.", settings.appLanguage))
            }

            Section {
                HStack {
                    Text(L10n.itemCount(viewModel.wallpapers.count, "%d wallpaper", "%d wallpapers", settings.appLanguage))
                    Spacer()
                    if !viewModel.statusText.isEmpty {
                        Text(L10n.t(viewModel.statusText, settings.appLanguage))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if !viewModel.selectedIDs.isEmpty {
                    Text(String(format: L10n.t("%d selected", settings.appLanguage), viewModel.selectedIDs.count))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.t("Status", settings.appLanguage))
            }

            Section {
                HStack {
                    Button {
                        viewModel.selectAll()
                    } label: {
                        Label(L10n.t("Select All", settings.appLanguage), systemImage: "checkmark.rectangle")
                    }
                    .disabled(viewModel.wallpapers.isEmpty)

                    Button {
                        viewModel.deselectAll()
                    } label: {
                        Label(L10n.t("Deselect", settings.appLanguage), systemImage: "xmark.rectangle")
                    }
                    .disabled(viewModel.selectedIDs.isEmpty)

                    Spacer()

                    Button {
                        viewModel.showExtractSheet = true
                    } label: {
                        Label(L10n.t("Extract Selected", settings.appLanguage), systemImage: "shippingbox")
                    }
                    .disabled(viewModel.selectedIDs.isEmpty)
                }
            } header: {
                Text(L10n.t("Actions", settings.appLanguage))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            selectedLibraryMode = settings.libraryMode
            repkgPath = ProcessInfo.processInfo.environment["REPKG_PATH"] ?? ""
        }
    }

    private var localLibraryControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                viewModel.selectDirectory()
            } label: {
                Label(L10n.t("Open Folder", settings.appLanguage), systemImage: "folder")
            }

            if let dir = viewModel.selectedDirectory {
                pathSummary(title: dir.lastPathComponent, path: dir.path)
                HStack {
                    if viewModel.isScanning {
                        ProgressView().scaleEffect(0.65)
                    }
                    Button {
                        Task { await viewModel.scan() }
                    } label: {
                        Label(L10n.t("Refresh", settings.appLanguage), systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isScanning)
                }
            }
        }
    }

    private var remoteLibraryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.t("Server URL", settings.appLanguage), text: Binding(
                get: { settings.remoteServerURL },
                set: { settings.remoteServerURL = $0 }
            ))
            TextField(L10n.t("Username", settings.appLanguage), text: Binding(
                get: { settings.remoteUsername },
                set: { settings.remoteUsername = $0 }
            ))
            SecureField(L10n.t("Password", settings.appLanguage), text: Binding(
                get: { settings.remotePassword },
                set: { settings.remotePassword = $0 }
            ))
            directoryRow(
                title: L10n.t("Download Folder", settings.appLanguage),
                path: settings.remoteDownloadDirectory.path,
                emptyTitle: L10n.t("No download folder selected", settings.appLanguage)
            ) {
                viewModel.selectRemoteDownloadDirectory()
            }
            HStack {
                if viewModel.isRemoteConnecting {
                    ProgressView().scaleEffect(0.65)
                }
                Button {
                    Task { await viewModel.connectRemoteLibrary() }
                } label: {
                    Label(L10n.t("Connect", settings.appLanguage), systemImage: "network")
                }
                .disabled(viewModel.isRemoteConnecting)
                if !viewModel.remoteConnectionStatus.isEmpty {
                    Text(L10n.t(viewModel.remoteConnectionStatus, settings.appLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func directoryRow(
        title: String,
        path: String?,
        emptyTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(path ?? emptyTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(L10n.t("Change...", settings.appLanguage), action: action)
        }
    }

    private func pathSummary(title: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func browseRePKGBinary() {
        Task {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.message = L10n.t("Select RePKG binary", settings.appLanguage)
            if await panel.begin() == .OK, let url = panel.url {
                repkgPath = url.path
            }
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
                Toggle(L10n.t("Restore wallpaper on launch", settings.appLanguage), isOn: Binding(
                    get: { settings.restoreLastWallpaper },
                    set: { settings.restoreLastWallpaper = $0 }
                ))

                Toggle(L10n.t("Mute video wallpaper", settings.appLanguage), isOn: Binding(
                    get: { settings.wallpaperMuted },
                    set: { settings.wallpaperMuted = $0 }
                ))

                Toggle(L10n.t("Auto-replace static wallpaper with first frame", settings.appLanguage), isOn: Binding(
                    get: { settings.autoReplaceStaticWithFirstFrame },
                    set: { settings.autoReplaceStaticWithFirstFrame = $0 }
                ))
            } header: {
                Text(L10n.t("Playback", settings.appLanguage))
            } footer: {
                Text(L10n.t("Restore reapplies the last wallpaper on launch. Static replacement captures the first video frame as a fallback for spaces and login screen.", settings.appLanguage))
            }

            Section {
                Toggle(L10n.t("MetalFX upscaling for scene wallpapers", settings.appLanguage), isOn: $sceneUpscalingEnabled)

                if sceneUpscalingEnabled {
                    sceneSliderRow(
                        title: L10n.t("Render scale", settings.appLanguage),
                        valueText: "\(Int(sceneUpscalingPercent))%",
                        value: $sceneUpscalingPercent,
                        range: 30...100,
                        step: 5
                    )
                }

                sceneSliderRow(
                    title: L10n.t("Scene FPS limit", settings.appLanguage),
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
                        Label(L10n.t("Save & Reapply", settings.appLanguage), systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("s", modifiers: [.command])
                }
            } header: {
                Text(L10n.t("Scene Rendering", settings.appLanguage))
            } footer: {
                Text(L10n.t("Scene wallpapers use the lower of this FPS limit and the display refresh rate. MetalFX renders at a lower internal resolution, then upscales to reduce GPU load.", settings.appLanguage))
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
                    .accessibilityLabel(L10n.t("Ignore extensions", settings.appLanguage))

                TextField("e.g. .png,.jpg", text: Binding(
                    get: { settings.onlyExtensions },
                    set: { settings.onlyExtensions = $0 }
                ))
                    .accessibilityLabel(L10n.t("Only extensions", settings.appLanguage))
            } header: {
                Text(L10n.t("Extraction Filters", settings.appLanguage))
            } footer: {
                Text(L10n.t("Extensions to ignore (-i) or include (-e) when extracting packages.", settings.appLanguage))
            }

            Section {
                Toggle(L10n.t("Convert TEX files (-t)", settings.appLanguage), isOn: Binding(
                    get: { settings.convertTEX },
                    set: { settings.convertTEX = $0 }
                ))
                Toggle(L10n.t("No TEX conversion", settings.appLanguage), isOn: Binding(
                    get: { settings.noTEXConvert },
                    set: { settings.noTEXConvert = $0 }
                ))
                Toggle(L10n.t("Single directory (-s)", settings.appLanguage), isOn: Binding(
                    get: { settings.singleDir },
                    set: { settings.singleDir = $0 }
                ))
                Toggle(L10n.t("Recursive (-r)", settings.appLanguage), isOn: Binding(
                    get: { settings.recursive },
                    set: { settings.recursive = $0 }
                ))
                Toggle(L10n.t("Copy project.json (-c)", settings.appLanguage), isOn: Binding(
                    get: { settings.copyProject },
                    set: { settings.copyProject = $0 }
                ))
                Toggle(L10n.t("Use name (-n)", settings.appLanguage), isOn: Binding(
                    get: { settings.useName },
                    set: { settings.useName = $0 }
                ))
                Toggle(L10n.t("Overwrite existing", settings.appLanguage), isOn: Binding(
                    get: { settings.overwrite },
                    set: { settings.overwrite = $0 }
                ))
                Toggle(L10n.t("Debug info (-d)", settings.appLanguage), isOn: Binding(
                    get: { settings.debugInfo },
                    set: { settings.debugInfo = $0 }
                ))
                Toggle(L10n.t("Copy only (skip extraction)", settings.appLanguage), isOn: Binding(
                    get: { settings.copyOnly },
                    set: { settings.copyOnly = $0 }
                ))
            } header: {
                Text(L10n.t("Default Extraction Options", settings.appLanguage))
            }
        }
        .formStyle(.grouped)
    }
}
