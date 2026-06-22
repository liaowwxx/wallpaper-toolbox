import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(SettingsStore.self) private var settings

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
        .searchable(text: $viewModel.searchText, placement: .automatic, prompt: Text(L10n.t("Search wallpapers...", settings.appLanguage)))
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
            GalleryAtmosphereBackground(accent: galleryAccent)

            VStack(spacing: 0) {
                if !viewModel.selectedIDs.isEmpty {
                    BatchActionBar()
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
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
        .animation(AppMotion.selection, value: viewModel.selectedIDs.isEmpty)
    }

    private var galleryAccent: Color {
        if settings.galleryAccentMode == .custom {
            return GalleryTheme.color(hex: settings.customGalleryAccentHex) ?? GalleryTheme.violet
        }
        if let selected = viewModel.wallpapers.first(where: { viewModel.selectedIDs.contains($0.id) }) {
            return GalleryTheme.accent(for: selected.type)
        }
        if let first = viewModel.filteredWallpapers.first {
            return GalleryTheme.accent(for: first.type)
        }
        return GalleryTheme.violet
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
        .galleryGlassSurface(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            tint: GalleryTheme.cyan
        )
        .subtleShadow()
    }
}

// MARK: - Sidebar Sections

private struct FiltersSection: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(SettingsStore.self) private var settings
    @State private var showMatureWarning = false

    var body: some View {
        Group {
            Section(L10n.t("Type", settings.appLanguage)) {
                Picker(L10n.t("Filter by type", settings.appLanguage), selection: Binding(
                    get: { viewModel.typeFilter ?? "All" },
                    set: {
                        viewModel.typeFilter = $0 == "All" ? nil : $0
                        viewModel.notifyFilterChanged()
                    }
                )) {
                    Label(L10n.t("All", settings.appLanguage), systemImage: "square.grid.2x2").tag("All")
                    Label(L10n.t("Video", settings.appLanguage), systemImage: "film").tag("video")
                    Label(L10n.t("Image", settings.appLanguage), systemImage: "photo").tag("image")
                    Label(L10n.t("Scene", settings.appLanguage), systemImage: "cube").tag("scene")
                    Label(L10n.t("Web", settings.appLanguage), systemImage: "globe").tag("web")
                }
                .labelsHidden()
            }

            Section(L10n.t("Rating", settings.appLanguage)) {
                Picker(L10n.t("Filter by rating", settings.appLanguage), selection: ratingBinding) {
                    Label(L10n.t("All", settings.appLanguage), systemImage: "square.grid.2x2").tag("All")
                    Label(L10n.t("Everyone", settings.appLanguage), systemImage: "person.2").tag("Everyone")
                    Label(L10n.t("Questionable", settings.appLanguage), systemImage: "exclamationmark.triangle").tag("Questionable")
                    Label(L10n.t("Mature", settings.appLanguage), systemImage: "18.circle").tag("Mature")
                }
                .labelsHidden()
            }
            .alert(L10n.t("Mature Content", settings.appLanguage), isPresented: $showMatureWarning) {
                Button(L10n.t("Cancel", settings.appLanguage), role: .cancel) { }
                Button(L10n.t("Show Mature Content", settings.appLanguage)) {
                    viewModel.contentRatingFilter = "Mature"
                    viewModel.notifyFilterChanged()
                }
            } message: {
                Text(L10n.t("This will display content marked as Mature. Are you sure?", settings.appLanguage))
            }

            if !viewModel.allCollections.isEmpty {
                Section(L10n.t("Collections", settings.appLanguage)) {
                    Picker(L10n.t("Filter by collection", settings.appLanguage), selection: Binding(
                        get: { viewModel.collectionFilter ?? "All" },
                        set: {
                            viewModel.collectionFilter = $0 == "All" ? nil : $0
                            viewModel.notifyFilterChanged()
                        }
                    )) {
                        Label(L10n.t("All", settings.appLanguage), systemImage: "square.grid.2x2").tag("All")
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
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if let item = viewModel.currentSceneWallpaperItem {
            Section(L10n.t("Scene Properties", settings.appLanguage)) {
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
    @Environment(SettingsStore.self) private var settings
    @State private var isConfirmingDelete = false

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: L10n.t("%d selected", settings.appLanguage), viewModel.selectedIDs.count))
                .font(.subheadline).fontWeight(.medium).foregroundStyle(.tint)
            Button(L10n.t("Deselect", settings.appLanguage)) { viewModel.deselectAll() }.font(.caption)
            Divider().frame(height: 16)

            Menu(L10n.t("Add to Collection", settings.appLanguage)) {
                ForEach(viewModel.allCollections, id: \.self) { collection in
                    Button(collection) { viewModel.batchAddToCollection(collection) }
                }
                if !viewModel.allCollections.isEmpty { Divider() }
                Button(L10n.t("New Collection...", settings.appLanguage)) { viewModel.showNewCollectionSheet = true }
            }
            .font(.caption).disabled(viewModel.selectedIDs.isEmpty)

            if !viewModel.allCollections.isEmpty {
                Menu(L10n.t("Remove from Collection", settings.appLanguage)) {
                    ForEach(viewModel.allCollections, id: \.self) { collection in
                        Button(collection) { viewModel.batchRemoveFromCollection(collection) }
                    }
                }
                .font(.caption).disabled(viewModel.selectedIDs.isEmpty)
            }

            Menu(L10n.t("Rating", settings.appLanguage)) {
                ForEach(["Everyone", "Questionable", "Mature"], id: \.self) { rating in
                    Button(L10n.contentRating(rating, settings.appLanguage)) { viewModel.batchSetContentRating(rating) }
                }
            }
            .font(.caption).disabled(viewModel.selectedIDs.isEmpty)

            Button(L10n.t("Delete", settings.appLanguage)) { isConfirmingDelete = true }
                .font(.caption).foregroundStyle(.red)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .galleryGlassSurface(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            tint: .accentColor
        )
        .subtleShadow()
        .confirmationDialog(L10n.t("Delete Selected Wallpapers?", settings.appLanguage), isPresented: $isConfirmingDelete) {
            Button(L10n.t("Delete", settings.appLanguage), role: .destructive) {
                viewModel.batchDeleteWallpapers()
            }
            Button(L10n.t("Cancel", settings.appLanguage), role: .cancel) { }
        } message: {
            Text(String(format: L10n.t("This removes %d selected wallpapers from disk.", settings.appLanguage), viewModel.selectedIDs.count))
        }
    }
}

// MARK: - Empty State

private struct EmptyGalleryView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text(L10n.t("No wallpapers loaded", settings.appLanguage))
                .font(.title2).foregroundStyle(.secondary)
            Text(L10n.t("Open a directory containing Wallpaper Engine wallpapers", settings.appLanguage))
                .foregroundStyle(.secondary)
            Button(L10n.t("Open Directory", settings.appLanguage)) { viewModel.selectDirectory() }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
        .padding(32)
        .galleryGlassSurface(
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            tint: GalleryTheme.violet
        )
    }
}
