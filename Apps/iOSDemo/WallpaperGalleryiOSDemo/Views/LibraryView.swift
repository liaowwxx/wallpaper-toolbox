import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LibraryView: View {
    @Environment(RemoteLibraryViewModel.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var baseTileSize: CGFloat = 112
    @GestureState private var magnification: CGFloat = 1.0
    @State private var showFilters = false

    private var tileSize: CGFloat {
        clampedTileSize(baseTileSize * magnification)
    }

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: tileSize, maximum: tileSize), spacing: Self.tileSpacing)
        ]
    }

    var body: some View {
        if usesSidebarLayout {
            regularLayout
        } else {
            compactLayout
        }
    }

    private var usesSidebarLayout: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
        #else
        horizontalSizeClass == .regular
        #endif
    }

    @ViewBuilder
    private var regularLayout: some View {
        @Bindable var library = library
        NavigationSplitView {
            LibrarySidebar()
                .navigationTitle("Library")
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
        } detail: {
            NavigationStack {
                libraryGrid
                    .navigationTitle("Wallpapers")
                    .navigationDestination(for: RemoteWallpaperItem.self) { item in
                        WallpaperDetailView(item: item)
                    }
            }
        }
        .searchable(text: $library.query, prompt: "Search wallpapers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await library.connect() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(library.isLoading)
                .accessibilityLabel("Reload library")
            }
        }
        .statusOverlay()
    }

    @ViewBuilder
    private var compactLayout: some View {
        @Bindable var library = library
        NavigationStack {
            libraryGrid
                .navigationTitle("Wallpapers")
                .navigationDestination(for: RemoteWallpaperItem.self) { item in
                    WallpaperDetailView(item: item)
                }
                .searchable(text: $library.query, prompt: "Search wallpapers")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            Task { await library.connect() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(library.isLoading)
                        .accessibilityLabel("Reload library")

                        Button {
                            showFilters = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                        }
                        .accessibilityLabel("Filters & Settings")
                    }
                }
                .statusOverlay()
        }
        .sheet(isPresented: $showFilters) {
            NavigationStack {
                LibrarySettingsList()
                    .navigationTitle("Filters & Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showFilters = false }
                        }
                    }
            }
        }
    }

    private var libraryGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Self.tileSpacing) {
                ForEach(library.filteredItems) { item in
                    NavigationLink(value: item) {
                        RemoteWallpaperTile(item: item, baseURL: library.baseURL, tileSize: tileSize)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Self.tileSpacing)
            .contentShape(.rect)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .highPriorityGesture(zoomGesture)
        .overlay {
            if library.filteredItems.isEmpty {
                ContentUnavailableView(
                    "No Wallpapers",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Connect to a Windows library or clear the current filter.")
                )
            }
        }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                baseTileSize = clampedTileSize(baseTileSize * value.magnification)
            }
    }

    private func clampedTileSize(_ value: CGFloat) -> CGFloat {
        min(220, max(64, value))
    }

    private static let tileSpacing: CGFloat = 2
}

private struct LibrarySidebar: View {
    var body: some View {
        List {
            LibrarySidebarContent()
        }
        .listStyle(.sidebar)
    }
}

private struct LibrarySettingsList: View {
    var body: some View {
        List {
            LibrarySidebarContent()
        }
        .listStyle(.insetGrouped)
    }
}

private struct LibrarySidebarContent: View {
    var body: some View {
        SidebarFiltersSection()
        SidebarConnectionSection()
        SidebarActionsSection()
        SidebarCapabilitiesSection()
        SidebarLatestJobSection()
    }
}

private struct SidebarFiltersSection: View {
    @Environment(RemoteLibraryViewModel.self) private var library
    @State private var showMatureWarning = false

    var body: some View {
        Group {
            Section("Type") {
                Picker("Filter by type", selection: typeBinding) {
                    Label("All", systemImage: "square.grid.2x2").tag("All")
                    ForEach(library.availableTypes, id: \.self) { type in
                        Label(type.label, systemImage: type.icon).tag(type.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Section("Rating") {
                Picker("Filter by rating", selection: ratingBinding) {
                    Label("All", systemImage: "square.grid.2x2").tag("All")
                    ForEach(ContentRating.allCases, id: \.self) { rating in
                        Label(rating.label, systemImage: rating.icon).tag(rating.filterValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .alert("Mature Content", isPresented: $showMatureWarning) {
                Button("Cancel", role: .cancel) { }
                Button("Show Mature Content") {
                    library.selectedRating = .mature
                }
            } message: {
                Text("This will display content marked as Mature. Are you sure?")
            }
        }
    }

    private var typeBinding: Binding<String> {
        Binding(
            get: { library.selectedType?.rawValue ?? "All" },
            set: { value in
                if value == "All" {
                    library.selectedType = nil
                } else {
                    library.selectedType = WallpaperKind(rawValue: value) ?? .unknown
                }
            }
        )
    }

    private var ratingBinding: Binding<String> {
        Binding(
            get: { library.selectedRating?.filterValue ?? "All" },
            set: { value in
                if value == "Mature" {
                    showMatureWarning = true
                } else if value == "All" {
                    library.selectedRating = nil
                } else {
                    library.selectedRating = ContentRating(filterValue: value)
                }
            }
        )
    }
}

private struct SidebarConnectionSection: View {
    @Environment(RemoteLibraryViewModel.self) private var library

    var body: some View {
        @Bindable var library = library

        Section {
            TextField("Server URL", text: $library.serverURLText)
                .serverURLInputStyle()

            TextField("Username", text: $library.username)
                .plainCredentialInputStyle()

            SecureField("Password", text: $library.password)
        } header: {
            Text("Windows Library")
        } footer: {
            Text("Point this at the Windows API URL shown by the server control panel.")
        }
    }
}

private struct SidebarActionsSection: View {
    @Environment(RemoteLibraryViewModel.self) private var library

    var body: some View {
        Section {
            Button {
                Task { await library.connect() }
            } label: {
                Label("Connect", systemImage: "network")
            }
            .disabled(library.isLoading)

            Button {
                Task { await library.loadSampleLibrary() }
            } label: {
                Label("Load Sample Manifest", systemImage: "doc.badge.gearshape")
            }
            .disabled(library.isLoading)
        }
    }
}

private struct SidebarCapabilitiesSection: View {
    @Environment(RemoteLibraryViewModel.self) private var library

    var body: some View {
        Section("Server Capabilities") {
            CapabilityRow(
                title: "Range streaming",
                isEnabled: library.manifest?.supportsRangeStreaming == true
            )
            CapabilityRow(
                title: "Remote unpack jobs",
                isEnabled: library.manifest?.supportsUnpackJobs == true
            )
            LabeledContent("Schema") {
                Text(library.manifest.map { "\($0.schemaVersion)" } ?? "Unknown")
            }
            LabeledContent("Server") {
                Text(library.manifest?.serverVersion ?? "Unknown")
            }
        }
    }
}

private struct SidebarLatestJobSection: View {
    @Environment(RemoteLibraryViewModel.self) private var library

    var body: some View {
        if let job = library.latestJob {
            Section("Latest Job") {
                LabeledContent("Job") {
                    Text(job.id)
                }
                LabeledContent("State") {
                    Text(job.state)
                }
                if let message = job.message {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct CapabilityRow: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        HStack {
            Label(title, systemImage: isEnabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(isEnabled ? .primary : .secondary)
            Spacer()
        }
    }
}

private extension View {
    @ViewBuilder
    func serverURLInputStyle() -> some View {
        #if os(iOS)
        keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func plainCredentialInputStyle() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }
}

private struct RemoteWallpaperTile: View {
    let item: RemoteWallpaperItem
    let baseURL: URL?
    let tileSize: CGFloat

    var body: some View {
        ThumbnailImage(url: item.thumbnailURL(relativeTo: baseURL), fallbackIcon: item.typeIcon)
            .frame(width: tileSize, height: tileSize)
            .contentShape(.rect)
            .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.typeLabel)")
    }
}

struct ThumbnailImage: View {
    @Environment(RemoteLibraryViewModel.self) private var library

    let url: URL?
    let fallbackIcon: String
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: loadID) {
            await loadImage()
        }
        .clipped()
    }

    private var loadID: String {
        "\(url?.absoluteString ?? "")|\(library.authorizationHeader ?? "")"
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo, .teal, .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: fallbackIcon)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
        }
    }

    @MainActor
    private func loadImage() async {
        image = nil
        guard let url else { return }

        var request = URLRequest(url: url)
        if let authorizationHeader = library.authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return
            }
            #if os(iOS)
            guard let uiImage = UIImage(data: data) else { return }
            image = Image(uiImage: uiImage)
            #endif
        } catch {
            image = nil
        }
    }
}
