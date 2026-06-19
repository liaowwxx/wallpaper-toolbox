import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var repkgPath = ""

    var body: some View {
        @Bindable var viewModel = viewModel
        NavigationSplitView {
            sidebar
        } detail: {
            galleryArea
        }
        .sheet(isPresented: $viewModel.showExtractSheet) {
            ExtractSheet()
        }
        .sheet(isPresented: $viewModel.showWallpaperPicker) {
            if let item = viewModel.wallpaperTargetItem {
                AssetPickerSheet(item: item, assets: viewModel.wallpaperAssets)
            }
        }
        .sheet(isPresented: $viewModel.showSceneProperties) {
            if let item = viewModel.scenePropertiesTargetItem {
                ScenePropertiesSheet(item: item)
            }
        }
        .sheet(isPresented: $viewModel.showNewCollectionSheet) {
            NewCollectionSheet()
        }
        .searchable(text: $viewModel.searchText, placement: .automatic, prompt: "Search wallpapers...")
        .onAppear {
            repkgPath = ProcessInfo.processInfo.environment["REPKG_PATH"] ?? ""
        }
        .onChange(of: viewModel.searchText) { viewModel.onSearchTextChanged() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            WorkspaceSection()
            DirectoriesSection(repkgPath: $repkgPath)
            FiltersSection()
            WallpaperSection()
            ActionsSection()
            StatusSection()
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200, idealWidth: 240)
    }

    // MARK: - Gallery

    private var galleryArea: some View {
        VStack(spacing: 0) {
            if !viewModel.selectedIDs.isEmpty {
                BatchActionBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if viewModel.wallpapers.isEmpty && !viewModel.isScanning {
                EmptyGalleryView()
                    .transition(.opacity)
            } else {
                GalleryView()
            }
        }
        .frame(minWidth: 500)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.selectedIDs.isEmpty)
    }
}

// MARK: - Sidebar Sections

private struct WorkspaceSection: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        Section {
            Button(action: { viewModel.selectDirectory() }) {
                Label("Open Folder", systemImage: "folder")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open folder")
            .accessibilityHint("Select a directory containing Wallpaper Engine wallpapers")

            if let dir = viewModel.selectedDirectory {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dir.lastPathComponent)
                        .font(.caption).fontWeight(.medium)
                    Text(dir.path)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding(.vertical, 2)

                Picker("Scan Mode", selection: Binding(get: { viewModel.scanMode }, set: { viewModel.scanMode = $0 })) {
                    ForEach(ScanMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode == .subdir ? "folder" : "doc").tag(mode)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Scan mode")
                .onChange(of: viewModel.scanMode) {
                    viewModel.saveState()
                    Task { await viewModel.scan() }
                }

                HStack(spacing: 6) {
                    if viewModel.isScanning {
                        ProgressView().scaleEffect(0.6)
                    }
                    Button("Refresh") {
                        Task { await viewModel.scan() }
                    }
                    .disabled(viewModel.isScanning)
                }
            }
        }
    }
}

private struct DirectoriesSection: View {
    @Environment(AppViewModel.self) private var viewModel
    @Binding var repkgPath: String

    var body: some View {
        Section("Directories") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Output").font(.caption).foregroundStyle(.secondary)
                if let out = viewModel.outputDirectory {
                    Text(out.path)
                        .font(.caption2).lineLimit(1).truncationMode(.middle)
                    Button("Change...") { viewModel.selectOutputDirectory() }
                        .font(.caption)
                } else {
                    Button("Select Output...") { viewModel.selectOutputDirectory() }
                        .font(.caption)
                }
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("RePKG Binary").font(.caption).foregroundStyle(.secondary)
                TextField("Path", text: $repkgPath)
                    .font(.caption)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("RePKG binary path")
                HStack {
                    Button("Browse...") {
                        Task {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            if await panel.begin() == .OK, let url = panel.url {
                                repkgPath = url.path
                                setenv("REPKG_PATH", url.path, 1)
                            }
                        }
                    }
                    .font(.caption2)
                    Text("Default: resources/osx-arm64/RePKG")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct FiltersSection: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var showMatureWarning = false

    var body: some View {
        Group {
            Section("Type") {
                Picker("Filter by type", selection: Binding(
                    get: { viewModel.typeFilter ?? "All" },
                    set: {
                        viewModel.typeFilter = $0 == "All" ? nil : $0
                        viewModel.notifyFilterChanged()
                    }
                )) {
                    Label("All", systemImage: "square.grid.2x2").tag("All")
                    Label("Video", systemImage: "film").tag("video")
                    Label("Image", systemImage: "photo").tag("image")
                    Label("Scene", systemImage: "cube").tag("scene")
                    Label("Web", systemImage: "globe").tag("web")
                }
                .labelsHidden()
            }

            Section("Rating") {
                Picker("Filter by rating", selection: ratingBinding) {
                    Label("All", systemImage: "square.grid.2x2").tag("All")
                    Label("Everyone", systemImage: "person.2").tag("Everyone")
                    Label("Questionable", systemImage: "exclamationmark.triangle").tag("Questionable")
                    Label("Mature", systemImage: "18.circle").tag("Mature")
                }
                .labelsHidden()
            }
            .alert("Mature Content", isPresented: $showMatureWarning) {
                Button("Cancel", role: .cancel) { }
                Button("Show Mature Content") {
                    viewModel.contentRatingFilter = "Mature"
                    viewModel.notifyFilterChanged()
                }
            } message: {
                Text("This will display content marked as Mature. Are you sure?")
            }

            if !viewModel.allCollections.isEmpty {
                Section("Collections") {
                    Picker("Filter by collection", selection: Binding(
                        get: { viewModel.collectionFilter ?? "All" },
                        set: {
                            viewModel.collectionFilter = $0 == "All" ? nil : $0
                            viewModel.notifyFilterChanged()
                        }
                    )) {
                        Label("All", systemImage: "square.grid.2x2").tag("All")
                        ForEach(viewModel.allCollections, id: \.self) { collection in
                            Label(collection, systemImage: "folder").tag(collection)
                        }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private var ratingBinding: Binding<String> {
        Binding(
            get: { viewModel.contentRatingFilter ?? "All" },
            set: { newValue in
                if newValue == "Mature" {
                    showMatureWarning = true
                } else {
                    viewModel.contentRatingFilter = newValue == "All" ? nil : newValue
                    viewModel.notifyFilterChanged()
                }
            }
        )
    }
}

private struct WallpaperSection: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Section("Wallpaper") {
            Toggle("Restore on launch", isOn: Binding(
                get: { settings.restoreLastWallpaper },
                set: { settings.restoreLastWallpaper = $0 }
            ))
                .font(.caption)
                .accessibilityHint("Automatically restore the last set wallpaper when the app launches")
            Toggle("Mute playback", isOn: Binding(
                get: { settings.wallpaperMuted },
                set: { settings.wallpaperMuted = $0 }
            ))
                .font(.caption)
                .accessibilityHint("Play video wallpapers without sound")
            Toggle("Replace wallpaper", isOn: Binding(
                get: { settings.autoReplaceStaticWithFirstFrame },
                set: { settings.autoReplaceStaticWithFirstFrame = $0 }
            ))
                .font(.caption)
                .accessibilityHint("Capture first video frame as a static wallpaper fallback")
        }
    }
}

private struct ActionsSection: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        Section {
            Button(action: { viewModel.selectAll() }) {
                Label("Select All", systemImage: "checkmark.rectangle")
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.showExtractSheet = true }) {
                Label("Extract...", systemImage: "shippingbox")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedIDs.isEmpty)
        }
    }
}

private struct StatusSection: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.wallpapers.count) wallpapers").font(.caption)
                if viewModel.selectedIDs.count > 0 {
                    Text("\(viewModel.selectedIDs.count) selected")
                        .font(.caption).foregroundStyle(.tint)
                }
                if !viewModel.statusText.isEmpty {
                    Text(viewModel.statusText)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Batch Action Bar

private struct BatchActionBar: View {
    @Environment(AppViewModel.self) private var viewModel
    @State private var isConfirmingDelete = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(viewModel.selectedIDs.count) selected")
                .font(.subheadline).fontWeight(.medium).foregroundStyle(.tint)
            Button("Deselect") { viewModel.deselectAll() }.font(.caption)
            Divider().frame(height: 16)

            Menu("Add to Collection") {
                ForEach(viewModel.allCollections, id: \.self) { collection in
                    Button(collection) { viewModel.batchAddToCollection(collection) }
                }
                if !viewModel.allCollections.isEmpty { Divider() }
                Button("New Collection...") { viewModel.showNewCollectionSheet = true }
            }
            .font(.caption).disabled(viewModel.selectedIDs.isEmpty)

            if !viewModel.allCollections.isEmpty {
                Menu("Remove from Collection") {
                    ForEach(viewModel.allCollections, id: \.self) { collection in
                        Button(collection) { viewModel.batchRemoveFromCollection(collection) }
                    }
                }
                .font(.caption).disabled(viewModel.selectedIDs.isEmpty)
            }

            Menu("Rating") {
                ForEach(["Everyone", "Questionable", "Mature"], id: \.self) { rating in
                    Button(rating) { viewModel.batchSetContentRating(rating) }
                }
            }
            .font(.caption).disabled(viewModel.selectedIDs.isEmpty)

            Button("Delete") { isConfirmingDelete = true }
                .font(.caption).foregroundStyle(.red)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .toolbarGlass().subtleShadow()
        .confirmationDialog("Delete Selected Wallpapers?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                viewModel.batchDeleteWallpapers()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes \(viewModel.selectedIDs.count) selected wallpapers from disk.")
        }
    }
}

// MARK: - Empty State

private struct EmptyGalleryView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No wallpapers loaded")
                .font(.title2).foregroundStyle(.secondary)
            Text("Open a directory containing Wallpaper Engine wallpapers")
                .foregroundStyle(.secondary)
            Button("Open Directory") { viewModel.selectDirectory() }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
    }
}
