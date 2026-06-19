import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel

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
        .sheet(isPresented: $viewModel.showNewCollectionSheet) {
            NewCollectionSheet()
        }
        .searchable(text: $viewModel.searchText, placement: .automatic, prompt: "Search wallpapers...")
        .onChange(of: viewModel.searchText) { viewModel.onSearchTextChanged() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            FiltersSection()
            ScenePropertiesSidebarSection()
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200, idealWidth: 240)
    }

    // MARK: - Gallery

    private var galleryArea: some View {
        ZStack(alignment: .bottomTrailing) {
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

            if let progress = viewModel.remoteDownloadProgress {
                RemoteDownloadProgressPanel(progress: progress)
                    .padding(18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 500)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.selectedIDs.isEmpty)
    }
}

private struct RemoteDownloadProgressPanel: View {
    let progress: RemoteDownloadProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundStyle(.blue)
                Text(progress.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer(minLength: 10)
                Text(progress.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: progress.progress)
                .progressViewStyle(.linear)
        }
        .padding(12)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 12, y: 4)
    }
}

// MARK: - Sidebar Sections

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

private struct ScenePropertiesSidebarSection: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        if let item = viewModel.currentSceneWallpaperItem {
            Section("Scene Properties") {
                ScenePropertiesEditor(item: item)
                    .padding(.vertical, 2)
                    .id(item.id)
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
