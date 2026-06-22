import Foundation
import AppKit
import Darwin

struct RemoteDownloadProgress: Identifiable, Equatable {
    let id: String
    var title: String
    var progress: Double
    var detail: String
}

@Observable
@MainActor
final class AppViewModel {
    // MARK: - Runtime state

    var wallpapers: [WallpaperItem] = []
    var selectedDirectory: URL?
    var scanMode: ScanMode = .subdir
    var isScanning = false
    var selectedIDs = Set<String>()
    var searchText = ""
    var typeFilter: String? = nil
    var contentRatingFilter: String? = "Everyone"
    var collectionFilter: String? = nil
    var statusText = "Ready"
    var isRemoteConnecting = false
    var remoteConnectionStatus = ""
    var remoteDownloadProgress: RemoteDownloadProgress?
    var remoteDownloadedIDs = Set<String>()

    /// Tracks whether the initial onAppear launch sequence has run.
    @ObservationIgnored var appDidLaunch = false

    /// Bumped whenever filters or search change, providing animation context for ForEach transitions.
    var filterGeneration = 0

    var isExtracting = false
    var extractionOutput = ""
    var showExtractSheet = false
    var showNewCollectionSheet = false

    var wallpaperAssets: [AssetFile] = []
    var showWallpaperPicker = false
    var wallpaperStatus = ""
    var wallpaperForAllScreens = false
    var wallpaperTargetItem: WallpaperItem?
    var wallpaperPreparedContentURL: URL?
    var currentSceneWallpaperPath: String?
    var currentWebWallpaperPath: String?

    // Settings are now in SettingsStore, injected via environment.
    // These mirrors exist for backward-compatible access within the ViewModel.
    private var settings: SettingsStore?

    // MARK: - Services

    private let scanner = WallpaperScanner()
    private let repkgService = RePKGService()
    private let wallpaperService = WallpaperService()
    private let sceneRendererService = SceneWallpaperRendererService()
    private let webRendererService = WebWallpaperRendererService()
    private let metadataService = MetadataService.shared

    private var wallpaperCacheRoot: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("\(AppConstants.appBundleIdentifier)/wallpaper")
    }

    // MARK: - Settings conveniences (delegated to SettingsStore)

    var restoreLastWallpaper: Bool {
        get { settings?.restoreLastWallpaper ?? false }
        set { settings?.restoreLastWallpaper = newValue }
    }

    var wallpaperMuted: Bool {
        get { settings?.wallpaperMuted ?? true }
        set { settings?.wallpaperMuted = newValue }
    }

    var autoReplaceStaticWithFirstFrame: Bool {
        get { settings?.autoReplaceStaticWithFirstFrame ?? false }
        set { settings?.autoReplaceStaticWithFirstFrame = newValue }
    }

    var remoteAuthorizationHeader: String? {
        guard let settings else { return nil }
        return RemoteLibraryClient.authorizationHeader(
            username: settings.remoteUsername,
            password: settings.remotePassword
        )
    }

    var outputDirectory: URL? {
        get { settings?.outputDirectory ?? nil }
        set { settings?.outputDirectory = newValue }
    }

    var libraryMode: LibraryMode {
        get { settings?.libraryMode ?? .local }
        set { settings?.libraryMode = newValue }
    }

    var isRemoteMode: Bool {
        libraryMode == .remote
    }

    var ignoreExtensions: String {
        get { settings?.ignoreExtensions ?? "" }
        set { settings?.ignoreExtensions = newValue }
    }
    var onlyExtensions: String {
        get { settings?.onlyExtensions ?? "" }
        set { settings?.onlyExtensions = newValue }
    }
    var convertTEX: Bool {
        get { settings?.convertTEX ?? false }
        set { settings?.convertTEX = newValue }
    }
    var noTEXConvert: Bool {
        get { settings?.noTEXConvert ?? false }
        set { settings?.noTEXConvert = newValue }
    }
    var singleDir: Bool {
        get { settings?.singleDir ?? false }
        set { settings?.singleDir = newValue }
    }
    var recursive: Bool {
        get { settings?.recursive ?? true }
        set { settings?.recursive = newValue }
    }
    var copyProject: Bool {
        get { settings?.copyProject ?? false }
        set { settings?.copyProject = newValue }
    }
    var useName: Bool {
        get { settings?.useName ?? false }
        set { settings?.useName = newValue }
    }
    var overwrite: Bool {
        get { settings?.overwrite ?? false }
        set { settings?.overwrite = newValue }
    }
    var debugInfo: Bool {
        get { settings?.debugInfo ?? false }
        set { settings?.debugInfo = newValue }
    }
    var copyOnly: Bool {
        get { settings?.copyOnly ?? false }
        set { settings?.copyOnly = newValue }
    }

    // MARK: - Cached filtered results

    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    private var debouncedSearchText = ""

    /// Generation counter bumped on every wallpaper mutation that affects filtering.
    var wallpaperGeneration: Int = 0

    @ObservationIgnored private var _cachedFilters: (
        wallpaperGeneration: Int,
        searchText: String,
        typeFilter: String?,
        contentRatingFilter: String?,
        collectionFilter: String?,
        result: [WallpaperItem]
    )?

    @ObservationIgnored private var _cachedCollections: (generation: Int, result: [String])?
    @ObservationIgnored private var securityScopedURLs = Set<URL>()
    @ObservationIgnored private var directoryMonitor: DispatchSourceFileSystemObject?
    @ObservationIgnored private var monitoredDirectory: URL?
    @ObservationIgnored private var directoryRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var remoteManifest: RemoteLibraryManifest?
    @ObservationIgnored private var remoteBaseURL: URL?
    @ObservationIgnored private var localSelectedDirectory: URL?

    var allCollections: [String] {
        if let cache = _cachedCollections, cache.generation == wallpaperGeneration {
            return cache.result
        }
        var set = Set<String>()
        for wp in wallpapers {
            for c in wp.collections { set.insert(c) }
        }
        let result = set.sorted()
        _cachedCollections = (wallpaperGeneration, result)
        return result
    }

    var filteredWallpapers: [WallpaperItem] {
        if let cache = _cachedFilters,
           cache.wallpaperGeneration == wallpaperGeneration,
           cache.searchText == debouncedSearchText,
           cache.typeFilter == typeFilter,
           cache.contentRatingFilter == contentRatingFilter,
           cache.collectionFilter == collectionFilter {
            return cache.result
        }
        var result = wallpapers
        if !debouncedSearchText.isEmpty {
            let query = debouncedSearchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query)
                || $0.tags.contains(where: { $0.lowercased().contains(query) })
            }
        }
        if let type = typeFilter {
            result = result.filter { $0.type == type }
        }
        if let rating = contentRatingFilter {
            result = result.filter { $0.contentRating == rating }
        }
        if let collection = collectionFilter {
            result = result.filter { $0.collections.contains(collection) }
        }
        _cachedFilters = (wallpaperGeneration, debouncedSearchText, typeFilter, contentRatingFilter, collectionFilter, result)
        return result
    }

    var selectedWallpapers: [WallpaperItem] {
        let ids = selectedIDs
        return wallpapers.filter { ids.contains($0.id) }
    }

    var currentSceneWallpaperItem: WallpaperItem? {
        guard let path = currentSceneWallpaperPath else { return nil }
        let url = URL(fileURLWithPath: path)
        guard sceneRendererService.isRendering(projectURL: url) else { return nil }
        return wallpapers.first {
            $0.type.lowercased() == "scene"
                && $0.path.standardizedFileURL == url.standardizedFileURL
        }
    }

    init(settingsStore: SettingsStore) {
        self.settings = settingsStore
        scanMode = settingsStore.scanMode
        loadSettings()
        repkgService.onOutput = { [weak self] text in
            self?.extractionOutput += text
        }
        repkgService.onComplete = { [weak self] code in
            self?.isExtracting = false
            self?.statusText = "Extraction finished (exit code: \(code))"
        }
    }

    deinit {
        searchDebounceTask?.cancel()
        directoryRefreshTask?.cancel()
        directoryMonitor?.cancel()
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Directory & Scan

    func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select wallpaper directory"

        Task {
            guard await panel.begin() == .OK, let url = panel.url else { return }
            libraryMode = .local
            localSelectedDirectory = url
            selectedDirectory = url
            createSecurityScopedBookmark(for: url, key: UserDefaultsKey.savedDirectoryBookmark)
            saveSettings()
            await scan()
        }
    }

    func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select output directory"

        Task {
            guard await panel.begin() == .OK, let url = panel.url else { return }
            outputDirectory = url
            createSecurityScopedBookmark(for: url, key: UserDefaultsKey.savedOutputBookmark)
            saveSettings()
        }
    }

    func selectRemoteDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select remote wallpaper download directory"

        Task {
            guard await panel.begin() == .OK, let url = panel.url else { return }
            settings?.remoteDownloadDirectory = url
            createSecurityScopedBookmark(for: url, key: UserDefaultsKey.savedRemoteDownloadBookmark)
            if isRemoteMode, remoteManifest != nil {
                selectedDirectory = url
                await refreshRemoteWallpapers()
            }
        }
    }

    func switchToLocalLibrary() {
        libraryMode = .local
        remoteManifest = nil
        remoteBaseURL = nil
        remoteConnectionStatus = ""
        remoteDownloadProgress = nil
        remoteDownloadedIDs = []
        selectedIDs.removeAll()
        if let localSelectedDirectory {
            selectedDirectory = localSelectedDirectory
        } else if let resolved = resolveBookmark(key: UserDefaultsKey.savedDirectoryBookmark) {
            selectedDirectory = resolved
        }
        if selectedDirectory != nil {
            Task { await scan(resetFilters: false) }
        } else {
            wallpapers = []
            wallpaperGeneration += 1
        }
    }

    func switchToRemoteLibrary() {
        libraryMode = .remote
        if selectedDirectory != settings?.remoteDownloadDirectory {
            localSelectedDirectory = selectedDirectory
        }
        remoteManifest = nil
        remoteBaseURL = nil
        remoteDownloadProgress = nil
        remoteDownloadedIDs = []
        selectedIDs.removeAll()
        selectedDirectory = settings?.remoteDownloadDirectory
        wallpapers = []
        wallpaperGeneration += 1
        remoteConnectionStatus = "Remote mode selected"
        statusText = "Remote mode selected. Connect to load the Windows library."
    }

    func loadInitialLibrary() async {
        if isRemoteMode {
            switchToRemoteLibrary()
            await connectRemoteLibrary()
        } else if selectedDirectory != nil {
            await scan()
        }
    }

    func connectRemoteLibrary() async {
        guard let settings else { return }
        let normalizedURLText = normalizeRemoteServerURL(settings.remoteServerURL)
        guard let serverURL = URL(string: normalizedURLText),
              serverURL.scheme != nil,
              serverURL.host != nil else {
            remoteConnectionStatus = RemoteLibraryError.invalidServerURL.localizedDescription
            statusText = remoteConnectionStatus
            return
        }

        isRemoteConnecting = true
        statusText = "Connecting to remote library..."
        remoteConnectionStatus = "Connecting..."
        wallpapers = []
        remoteDownloadedIDs = []
        selectedIDs.removeAll()
        wallpaperGeneration += 1
        if selectedDirectory != settings.remoteDownloadDirectory {
            localSelectedDirectory = selectedDirectory
        }
        settings.remoteServerURL = normalizedURLText
        settings.libraryMode = .remote
        defer { isRemoteConnecting = false }

        do {
            try FileManager.default.createDirectory(
                at: settings.remoteDownloadDirectory,
                withIntermediateDirectories: true
            )
            let client = RemoteLibraryClient(
                baseURL: serverURL,
                username: settings.remoteUsername,
                password: settings.remotePassword
            )
            let manifest = try await client.fetchManifest()
            remoteManifest = manifest
            remoteBaseURL = manifest.resolvedAPIBaseURL(relativeTo: serverURL) ?? serverURL
            selectedDirectory = settings.remoteDownloadDirectory
            scanMode = .subdir
            await refreshRemoteWallpapers()
            remoteConnectionStatus = "\(manifest.items.count) remote wallpapers loaded"
            statusText = remoteConnectionStatus
        } catch {
            remoteConnectionStatus = "Remote connect failed: \(error.localizedDescription)"
            statusText = remoteConnectionStatus
        }
    }

    func scan(resetFilters: Bool = true) async {
        if isRemoteMode {
            if remoteManifest != nil {
                await refreshRemoteWallpapers(resetFilters: resetFilters)
            } else {
                wallpapers = []
                selectedIDs.removeAll()
                wallpaperGeneration += 1
                statusText = "Remote mode selected. Connect to load the Windows library."
            }
            return
        }
        guard let dir = selectedDirectory else { return }
        startDirectoryMonitor(for: dir)
        isScanning = true
        statusText = "Scanning..."
        if resetFilters {
            selectedIDs.removeAll()
            contentRatingFilter = "Everyone"
            collectionFilter = nil
        }

        let items = await scanner.scan(directory: dir, mode: scanMode)
        wallpapers = items
        if !resetFilters {
            selectedIDs.formIntersection(Set(items.map(\.id)))
        }
        wallpaperGeneration += 1
        isScanning = false
        statusText = "\(items.count) wallpapers found"

        let preloadRequests = items.prefix(AppConstants.thumbnailPreloadBatchSize).compactMap { item -> ThumbnailView.PreloadRequest? in
            guard let thumbnailPath = item.thumbnailPath else { return nil }
            return ThumbnailView.PreloadRequest(url: thumbnailPath, version: item.thumbnailVersion)
        }
        Task.detached(priority: .background) {
            await ThumbnailView.preloadBatch(preloadRequests)
        }
    }

    private func refreshRemoteWallpapers(resetFilters: Bool = false) async {
        guard let manifest = remoteManifest, let settings else { return }
        let root = settings.remoteDownloadDirectory
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        isScanning = true
        if resetFilters {
            selectedIDs.removeAll()
            contentRatingFilter = "Everyone"
            collectionFilter = nil
        }

        let localItems = await scanner.scan(directory: root, mode: .subdir)
        var downloadRegistry = loadRemoteDownloadRegistry(root: root)
        let localByFolder = localItems.reduce(into: [String: WallpaperItem]()) { result, item in
            result[item.path.lastPathComponent] = item
        }
        let localByID = localItems.reduce(into: [String: WallpaperItem]()) { result, item in
            result[item.id] = item
        }

        wallpapers = manifest.items.map { record in
            let inferredItem = inferDownloadedItem(for: record, localItems: localItems)
            let item = remoteWallpaperItem(
                for: record,
                root: root,
                registry: downloadRegistry,
                scannedFolderItem: localByFolder[registeredOrExpectedFolderName(for: record, registry: downloadRegistry)],
                scannedIDItem: localByID[record.id],
                inferredItem: inferredItem
            )
            if item.isDownloaded, downloadRegistry[record.id] == nil {
                downloadRegistry[record.id] = item.path.lastPathComponent
            }
            return item
        }
        saveRemoteDownloadRegistry(downloadRegistry, root: root)
        syncRemoteDownloadedIDs(from: wallpapers)

        if !resetFilters {
            selectedIDs.formIntersection(Set(wallpapers.map(\.id)))
        }
        wallpaperGeneration += 1
        filterGeneration &+= 1
        isScanning = false
        statusText = "\(wallpapers.count) remote wallpapers loaded"
    }

    func downloadRemoteWallpaper(_ item: WallpaperItem) {
        Task { await downloadRemoteWallpaperAsync(item) }
    }

    private func downloadRemoteWallpaperAsync(_ item: WallpaperItem) async {
        guard item.isRemote, !isRemoteWallpaperDownloaded(item) else { return }
        guard let settings,
              let remoteID = item.remoteID,
              let manifest = remoteManifest,
              let record = manifest.items.first(where: { $0.id == remoteID }) else {
            statusText = "Remote item is no longer available"
            return
        }
        guard let archiveURL = record.sourceArchiveURL(relativeTo: remoteBaseURL) else {
            statusText = RemoteLibraryError.missingSourceArchive.localizedDescription
            return
        }
        guard remoteDownloadProgress == nil else {
            statusText = "Another remote download is already running"
            return
        }

        let progressID = item.id
        remoteDownloadProgress = RemoteDownloadProgress(id: progressID, title: item.title, progress: 0, detail: "Starting download")
        statusText = "Downloading \(item.title)..."

        do {
            try FileManager.default.createDirectory(
                at: settings.remoteDownloadDirectory,
                withIntermediateDirectories: true
            )
            let client = RemoteLibraryClient(
                baseURL: remoteBaseURL ?? URL(string: settings.remoteServerURL)!,
                username: settings.remoteUsername,
                password: settings.remotePassword
            )
            let archive = try await client.downloadArchive(from: archiveURL) { [weak self] value in
                guard let self else { return }
                self.remoteDownloadProgress = RemoteDownloadProgress(
                    id: progressID,
                    title: item.title,
                    progress: value,
                    detail: "\(Int((value * 100).rounded()))%"
                )
            }
            let archiveLayout = try await inspectArchiveLayout(
                in: archive,
                expectedAssetNames: record.assets.map(\.name)
            )
            remoteDownloadProgress = RemoteDownloadProgress(id: progressID, title: item.title, progress: 1, detail: "Installing")
            let installPlan = makeRemoteInstallPlan(
                for: record,
                archiveLayout: archiveLayout,
                root: settings.remoteDownloadDirectory
            )
            try FileManager.default.createDirectory(
                at: installPlan.destination,
                withIntermediateDirectories: true
            )
            try await unzipArchive(
                archive,
                to: installPlan.destination,
                readerOptions: archiveLayout.readerOptions
            )
            let downloadedFolderName = installPlan.folderName
            let downloadedFolderURL = settings.remoteDownloadDirectory.appendingPathComponent(downloadedFolderName, isDirectory: true)
            guard remoteDownloadedFolderSatisfies(record: record, folderURL: downloadedFolderURL) else {
                throw RemoteLibraryError.downloadFailed("Downloaded archive is incomplete. The expected \(record.type) asset was not found.")
            }
            var registry = loadRemoteDownloadRegistry(root: settings.remoteDownloadDirectory)
            registry[record.id] = downloadedFolderName
            saveRemoteDownloadRegistry(registry, root: settings.remoteDownloadDirectory)
            try? FileManager.default.removeItem(at: archive)
            markRemoteWallpaperDownloaded(
                record: record,
                folderName: downloadedFolderName,
                root: settings.remoteDownloadDirectory
            )
            remoteDownloadProgress = nil
            await refreshRemoteWallpapers()
            statusText = "Downloaded: \(item.title)"
        } catch {
            remoteDownloadProgress = nil
            statusText = "Download failed: \(error.localizedDescription)"
        }
    }

    private func registeredOrExpectedFolderName(for record: RemoteWallpaperRecord, registry: [String: String]) -> String {
        if let registered = registry[record.id], !registered.isEmpty {
            return registered
        }
        return remoteFolderName(for: record)
    }

    private func inferDownloadedItem(for record: RemoteWallpaperRecord, localItems: [WallpaperItem]) -> WallpaperItem? {
        let matchingItems = localItems.filter {
            $0.title == record.title && $0.type.lowercased() == record.type.lowercased()
        }
        return matchingItems.count == 1 ? matchingItems[0] : nil
    }

    private func remoteWallpaperItem(
        for record: RemoteWallpaperRecord,
        root: URL,
        registry: [String: String],
        scannedFolderItem: WallpaperItem?,
        scannedIDItem: WallpaperItem?,
        inferredItem: WallpaperItem?
    ) -> WallpaperItem {
        let folderName = registeredOrExpectedFolderName(for: record, registry: registry)
        let folderURL = root.appendingPathComponent(folderName, isDirectory: true)
        let downloadedFolderItem = itemForDownloadedRemoteFolder(
            record: record,
            folderURL: folderURL
        )
        var item = downloadedFolderItem
            ?? scannedFolderItem
            ?? scannedIDItem
            ?? inferredItem
            ?? WallpaperItem(directory: folderURL, project: nil, preview: nil, pkg: nil)
        applyRemoteMetadata(to: &item, record: record)
        item.isDownloaded = remoteDownloadedFolderSatisfies(record: record, folderURL: item.path)
        return item
    }

    private func itemForDownloadedRemoteFolder(record: RemoteWallpaperRecord, folderURL: URL) -> WallpaperItem? {
        guard isExistingDirectory(folderURL) else { return nil }
        var item = WallpaperItem(
            directory: folderURL,
            project: metadataService.readProjectJSON(in: folderURL),
            preview: findPreview(in: folderURL),
            pkg: findPKG(in: folderURL)
        )
        applyRemoteMetadata(to: &item, record: record)
        item.isDownloaded = remoteDownloadedFolderSatisfies(record: record, folderURL: folderURL)
        return item
    }

    private func applyRemoteMetadata(to item: inout WallpaperItem, record: RemoteWallpaperRecord) {
        item.id = "remote-\(record.id)"
        item.title = record.title
        item.type = record.type
        item.contentRating = record.contentRating
        item.collections = record.collections
        item.tags = record.tags
        item.metadataKey = record.id
        item.remoteID = record.id
        item.remoteRelativeDir = record.relativeDir
        item.remoteArchiveURL = record.sourceArchiveURL(relativeTo: remoteBaseURL)
        item.remoteThumbnailURL = record.thumbnailURL(relativeTo: remoteBaseURL)
        item.isRemote = true
    }

    private func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func remoteDownloadedFolderSatisfies(record: RemoteWallpaperRecord, folderURL: URL) -> Bool {
        guard isExistingDirectory(folderURL) else { return false }

        switch record.type {
        case "video", "image":
            let expectedAssets = record.assets.filter { $0.kind.lowercased() == record.type }
            let localAssets = AssetScanner.scan(folderURL)
            guard !localAssets.isEmpty else { return false }

            if expectedAssets.isEmpty {
                return localAssets.contains { asset in
                    record.type == "video" ? asset.isVideo : !asset.isVideo
                }
            }

            let localNames = Set(localAssets.map { $0.name.lowercased() })
            return expectedAssets.contains { asset in
                localNames.contains(asset.name.lowercased())
            }
        default:
            return true
        }
    }

    private func markRemoteWallpaperDownloaded(record: RemoteWallpaperRecord, folderName: String, root: URL) {
        guard let index = wallpapers.firstIndex(where: { $0.remoteID == record.id }) else { return }
        let folderURL = root.appendingPathComponent(folderName, isDirectory: true)
        var item = itemForDownloadedRemoteFolder(record: record, folderURL: folderURL)
            ?? WallpaperItem(directory: folderURL, project: nil, preview: nil, pkg: nil)
        applyRemoteMetadata(to: &item, record: record)
        item.isDownloaded = true
        var updatedWallpapers = wallpapers
        updatedWallpapers[index] = item
        wallpapers = updatedWallpapers
        setRemoteDownloaded(true, remoteID: record.id)
        selectedIDs.remove(item.id)
        wallpaperGeneration += 1
        filterGeneration &+= 1
    }

    func isRemoteWallpaperDownloaded(_ item: WallpaperItem) -> Bool {
        guard item.isRemote, let remoteID = item.remoteID else {
            return item.isDownloaded
        }
        return item.isDownloaded || remoteDownloadedIDs.contains(remoteID)
    }

    private func setRemoteDownloaded(_ isDownloaded: Bool, remoteID: String?) {
        guard let remoteID else { return }
        var updatedIDs = remoteDownloadedIDs
        if isDownloaded {
            updatedIDs.insert(remoteID)
        } else {
            updatedIDs.remove(remoteID)
        }
        remoteDownloadedIDs = updatedIDs
        filterGeneration &+= 1
    }

    private func syncRemoteDownloadedIDs(from items: [WallpaperItem]) {
        remoteDownloadedIDs = Set(items.compactMap { item in
            item.isRemote && item.isDownloaded ? item.remoteID : nil
        })
    }

    private func findPreview(in directory: URL) -> URL? {
        for name in ["preview.jpg", "preview.png", "preview.gif", "preview.webp"] {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func findPKG(in directory: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return contents.first { $0.pathExtension.lowercased() == "pkg" }
    }

    private func remoteFolderName(for record: RemoteWallpaperRecord) -> String {
        if let relativeDir = record.relativeDir?.trimmingCharacters(in: .whitespacesAndNewlines), !relativeDir.isEmpty {
            return URL(fileURLWithPath: relativeDir).lastPathComponent
        }
        return record.id
    }

    private func normalizeRemoteServerURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return trimmed
        }
        return "http://\(trimmed)"
    }

    private func remoteDownloadRegistryURL(root: URL) -> URL {
        root.appendingPathComponent(".wallpaper-remote-downloads.json")
    }

    private func loadRemoteDownloadRegistry(root: URL) -> [String: String] {
        let url = remoteDownloadRegistryURL(root: root)
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func saveRemoteDownloadRegistry(_ registry: [String: String], root: URL) {
        let url = remoteDownloadRegistryURL(root: root)
        guard let data = try? JSONEncoder().encode(registry) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private struct RemoteArchiveLayout {
        let topLevelDirectories: [String]
        let hasRootFiles: Bool
        let readerOptions: String?
    }

    private func makeRemoteInstallPlan(
        for record: RemoteWallpaperRecord,
        archiveLayout: RemoteArchiveLayout,
        root: URL
    ) -> (folderName: String, destination: URL) {
        if !archiveLayout.hasRootFiles, archiveLayout.topLevelDirectories.count == 1,
           let folderName = archiveLayout.topLevelDirectories.first {
            return (folderName, root)
        }

        let expected = remoteFolderName(for: record)
        return (expected, root.appendingPathComponent(expected, isDirectory: true))
    }

    private struct RemoteArchiveListing {
        let strategy: RemoteArchiveReaderStrategy
        let entries: [String]
        let replacementCharacterCount: Int
        let expectedAssetMatchCount: Int
    }

    private struct RemoteArchiveReaderStrategy {
        let readerOptions: String?

        static let candidates = [
            RemoteArchiveReaderStrategy(readerOptions: nil),
            RemoteArchiveReaderStrategy(readerOptions: "hdrcharset=CP936")
        ]
    }

    private struct ArchiveProcessResult {
        let output: String
    }

    private nonisolated static func archiveToolURL() -> URL {
        let bsdtar = URL(fileURLWithPath: "/usr/bin/bsdtar")
        if FileManager.default.fileExists(atPath: bsdtar.path) {
            return bsdtar
        }
        return URL(fileURLWithPath: "/usr/bin/tar")
    }

    private nonisolated static func runArchiveTool(arguments: [String]) throws -> ArchiveProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = archiveToolURL()
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        let errorOutput = String(decoding: errorData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RemoteLibraryError.downloadFailed(
                message.isEmpty ? "Unable to process downloaded wallpaper archive." : message
            )
        }

        return ArchiveProcessResult(output: output)
    }

    private nonisolated static func archiveArguments(
        modeArguments: [String],
        readerOptions: String?
    ) -> [String] {
        var arguments = modeArguments
        if let readerOptions {
            arguments.append(contentsOf: ["--options", readerOptions])
        }
        return arguments
    }

    private nonisolated static func archiveListing(
        for archive: URL,
        strategy: RemoteArchiveReaderStrategy,
        expectedAssetNames: Set<String>
    ) throws -> RemoteArchiveListing {
        let result = try runArchiveTool(arguments: archiveArguments(
            modeArguments: ["-tf", archive.path],
            readerOptions: strategy.readerOptions
        ))
        let entries = result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
        let replacementCount = result.output.reduce(0) { count, character in
            character == "\u{FFFD}" ? count + 1 : count
        }
        let localNames = Set(entries.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() })
        let expectedMatchCount = expectedAssetNames.reduce(0) { count, name in
            localNames.contains(name) ? count + 1 : count
        }

        return RemoteArchiveListing(
            strategy: strategy,
            entries: entries,
            replacementCharacterCount: replacementCount,
            expectedAssetMatchCount: expectedMatchCount
        )
    }

    private nonisolated static func bestArchiveListing(
        for archive: URL,
        expectedAssetNames: Set<String>
    ) throws -> RemoteArchiveListing {
        var listings: [RemoteArchiveListing] = []
        var lastError: Error?

        for strategy in RemoteArchiveReaderStrategy.candidates {
            do {
                listings.append(try archiveListing(
                    for: archive,
                    strategy: strategy,
                    expectedAssetNames: expectedAssetNames
                ))
            } catch {
                lastError = error
            }
        }

        guard let best = listings.max(by: { lhs, rhs in
            if lhs.expectedAssetMatchCount != rhs.expectedAssetMatchCount {
                return lhs.expectedAssetMatchCount < rhs.expectedAssetMatchCount
            }
            return lhs.replacementCharacterCount > rhs.replacementCharacterCount
        }) else {
            throw lastError ?? RemoteLibraryError.downloadFailed("Unable to inspect downloaded wallpaper archive.")
        }

        return best
    }

    private nonisolated static func validateArchiveEntries(_ entries: [String]) throws {
        for entry in entries {
            guard !entry.hasPrefix("/") else {
                throw RemoteLibraryError.downloadFailed("Downloaded archive contains an absolute path: \(entry)")
            }

            let components = entry.split(separator: "/", omittingEmptySubsequences: true)
            guard !components.contains("..") else {
                throw RemoteLibraryError.downloadFailed("Downloaded archive contains a parent-directory path: \(entry)")
            }
        }
    }

    private func inspectArchiveLayout(in archive: URL, expectedAssetNames: [String]) async throws -> RemoteArchiveLayout {
        try await Task.detached {
            let expectedAssetNames = Set(expectedAssetNames.map { $0.lowercased() })
            let listing = try Self.bestArchiveListing(for: archive, expectedAssetNames: expectedAssetNames)
            try Self.validateArchiveEntries(listing.entries)
            var topLevelDirectories = Set<String>()
            var hasRootFiles = false

            for entry in listing.entries {
                let components = entry.split(separator: "/", omittingEmptySubsequences: true)
                guard let first = components.first else { continue }
                let topLevelName = String(first)
                guard topLevelName != "__MACOSX" else { continue }

                if components.count == 1 {
                    if !entry.hasSuffix("/") {
                        hasRootFiles = true
                    }
                } else {
                    topLevelDirectories.insert(topLevelName)
                }
            }

            return RemoteArchiveLayout(
                topLevelDirectories: topLevelDirectories.sorted(),
                hasRootFiles: hasRootFiles,
                readerOptions: listing.strategy.readerOptions
            )
        }.value
    }

    private func unzipArchive(_ archive: URL, to destination: URL, readerOptions: String?) async throws {
        try await Task.detached {
            _ = try Self.runArchiveTool(arguments: Self.archiveArguments(
                modeArguments: ["-xf", archive.path, "-C", destination.path],
                readerOptions: readerOptions
            ))
        }.value
    }

    // MARK: - Directory monitoring

    private func startDirectoryMonitor(for directory: URL) {
        guard monitoredDirectory != directory else { return }
        directoryRefreshTask?.cancel()
        directoryMonitor?.cancel()
        directoryMonitor = nil
        monitoredDirectory = nil

        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleDirectoryRefresh()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()

        directoryMonitor = source
        monitoredDirectory = directory
    }

    private func scheduleDirectoryRefresh() {
        guard selectedDirectory != nil else { return }
        directoryRefreshTask?.cancel()
        directoryRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, !self.isScanning else { return }
            await self.scan(resetFilters: false)
        }
    }

    /// Call when user changes a filter, so animated ForEach transitions get context.
    func notifyFilterChanged() {
        filterGeneration &+= 1
    }

    // MARK: - Selection

    func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func selectAll() {
        let filtered = filteredWallpapers.map(\.id)
        selectedIDs = Set(filtered)
    }

    func deselectAll() {
        selectedIDs.removeAll()
    }

    // MARK: - Content Rating

    func setContentRating(_ item: WallpaperItem, rating: String) {
        guard let idx = wallpapers.firstIndex(where: { $0.id == item.id }) else { return }
        wallpapers[idx].contentRating = rating
        wallpaperGeneration += 1
        metadataService.saveMetadata(for: wallpapers[idx], mode: scanMode, flatRoot: selectedDirectory)
        statusText = "Content rating updated"
    }

    // MARK: - Collections

    func addToCollection(_ item: WallpaperItem, collection: String) {
        guard let idx = wallpapers.firstIndex(where: { $0.id == item.id }) else { return }
        if !wallpapers[idx].collections.contains(collection) {
            wallpapers[idx].collections.append(collection)
            wallpaperGeneration += 1
            metadataService.saveMetadata(for: wallpapers[idx], mode: scanMode, flatRoot: selectedDirectory)
            statusText = "Added to '\(collection)'"
        }
    }

    func removeFromCollection(_ item: WallpaperItem, collection: String) {
        guard let idx = wallpapers.firstIndex(where: { $0.id == item.id }) else { return }
        wallpapers[idx].collections.removeAll { $0 == collection }
        wallpaperGeneration += 1
        metadataService.saveMetadata(for: wallpapers[idx], mode: scanMode, flatRoot: selectedDirectory)
        statusText = "Removed from '\(collection)'"
    }

    func createCollection(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        for id in selectedIDs {
            if let idx = wallpapers.firstIndex(where: { $0.id == id }) {
                if !wallpapers[idx].collections.contains(trimmed) {
                    wallpapers[idx].collections.append(trimmed)
                }
            }
        }
        wallpaperGeneration += 1
        for item in wallpapers where selectedIDs.contains(item.id) {
            metadataService.saveMetadata(for: item, mode: scanMode, flatRoot: selectedDirectory)
        }
        statusText = "Collection '\(trimmed)' created with \(selectedIDs.count) items"
    }

    // MARK: - Batch Operations

    func batchAddToCollection(_ collection: String) {
        let indexMap = wallpapers.enumerated().reduce(into: [String: Int]()) {
            $0[$1.element.id] = $1.offset
        }
        var affected: [WallpaperItem] = []
        for id in selectedIDs {
            if let idx = indexMap[id], !wallpapers[idx].collections.contains(collection) {
                wallpapers[idx].collections.append(collection)
                affected.append(wallpapers[idx])
            }
        }
        if !affected.isEmpty { wallpaperGeneration += 1 }
        for item in affected {
            metadataService.saveMetadata(for: item, mode: scanMode, flatRoot: selectedDirectory)
        }
        statusText = "Added \(affected.count) items to '\(collection)'"
    }

    func batchRemoveFromCollection(_ collection: String) {
        let indexMap = wallpapers.enumerated().reduce(into: [String: Int]()) {
            $0[$1.element.id] = $1.offset
        }
        var affected: [WallpaperItem] = []
        for id in selectedIDs {
            if let idx = indexMap[id], wallpapers[idx].collections.contains(collection) {
                wallpapers[idx].collections.removeAll { $0 == collection }
                affected.append(wallpapers[idx])
            }
        }
        if !affected.isEmpty { wallpaperGeneration += 1 }
        for item in affected {
            metadataService.saveMetadata(for: item, mode: scanMode, flatRoot: selectedDirectory)
        }
        statusText = "Removed \(affected.count) items from '\(collection)'"
    }

    func batchSetContentRating(_ rating: String) {
        let indexMap = wallpapers.enumerated().reduce(into: [String: Int]()) {
            $0[$1.element.id] = $1.offset
        }
        var affected: [WallpaperItem] = []
        for id in selectedIDs {
            if let idx = indexMap[id] {
                wallpapers[idx].contentRating = rating
                affected.append(wallpapers[idx])
            }
        }
        if !affected.isEmpty { wallpaperGeneration += 1 }
        for item in affected {
            metadataService.saveMetadata(for: item, mode: scanMode, flatRoot: selectedDirectory)
        }
        statusText = "Updated rating to '\(rating)' for \(affected.count) items"
    }

    // MARK: - Delete

    func deleteWallpaper(_ item: WallpaperItem) {
        do {
            try FileManager.default.removeItem(at: item.path)
            if item.isRemote {
                setRemoteDownloaded(false, remoteID: item.remoteID)
                selectedIDs.remove(item.id)
                Task { await refreshRemoteWallpapers() }
            } else {
                wallpapers.removeAll { $0.id == item.id }
                selectedIDs.remove(item.id)
                wallpaperGeneration += 1
            }

            if scanMode == .flat, let root = selectedDirectory {
                var meta = metadataService.readFlatMeta(root: root)
                meta.removeValue(forKey: item.metadataKey)
                meta.removeValue(forKey: item.title)
                metadataService.writeFlatMeta(meta, root: root)
            }
            statusText = "Deleted: \(item.title)"
        } catch {
            statusText = "Delete failed: \(error.localizedDescription)"
        }
    }

    func batchDeleteWallpapers() {
        let toDelete = wallpapers.filter { selectedIDs.contains($0.id) }
        var failed = 0
        var deletedRemoteItem = false
        for item in toDelete {
            do {
                try FileManager.default.removeItem(at: item.path)
                if item.isRemote {
                    deletedRemoteItem = true
                    setRemoteDownloaded(false, remoteID: item.remoteID)
                }
                wallpapers.removeAll { $0.id == item.id }
                selectedIDs.remove(item.id)
            } catch {
                failed += 1
            }
        }
        if scanMode == .flat, let root = selectedDirectory {
            var meta = metadataService.readFlatMeta(root: root)
            for item in toDelete where !selectedIDs.contains(item.id) {
                meta.removeValue(forKey: item.metadataKey)
                meta.removeValue(forKey: item.title)
            }
            metadataService.writeFlatMeta(meta, root: root)
        }
        let deleted = toDelete.count - failed
        if deleted > 0 { wallpaperGeneration += 1 }
        if deletedRemoteItem {
            Task { await refreshRemoteWallpapers() }
        }
        statusText = failed > 0
            ? "Deleted \(deleted) wallpapers (\(failed) failed)"
            : "Deleted \(deleted) wallpapers"
    }

    // MARK: - Extraction

    func extract() async {
        guard !selectedIDs.isEmpty, let outputDir = outputDirectory else {
            statusText = "Select wallpapers and an output directory first"
            return
        }

        isExtracting = true
        extractionOutput = ""
        showExtractSheet = true

        if copyOnly {
            let fm = FileManager.default
            for wp in selectedWallpapers {
                statusText = "Copying: \(wp.title)"
                let folderName = wp.path.lastPathComponent
                let destDir = outputDir.appendingPathComponent(folderName)

                if overwrite, fm.fileExists(atPath: destDir.path) {
                    do {
                        try fm.removeItem(at: destDir)
                    } catch {
                        extractionOutput += "Failed to remove existing: \(error.localizedDescription)\n"
                    }
                }

                do {
                    try fm.copyItem(at: wp.path, to: destDir)
                    extractionOutput += "Copied: \(folderName)\n"
                } catch {
                    extractionOutput += "Copy failed (\(folderName)): \(error.localizedDescription)\n"
                }
            }
        } else {
            for wp in selectedWallpapers {
                guard !repkgService.isRunning else { break }
                guard let pkg = wp.pkgPath else { continue }

                statusText = "Extracting: \(wp.title)"

                let targetDir: String
                if singleDir {
                    targetDir = outputDir.path
                } else {
                    targetDir = outputDir.appendingPathComponent(wp.title.sanitizedForPath).path
                }

                let args = RePKGService.buildArguments(
                    inputPath: pkg.path,
                    outputDir: targetDir,
                    ignoreExtensions: ignoreExtensions.isEmpty ? nil : ignoreExtensions,
                    onlyExtensions: onlyExtensions.isEmpty ? nil : onlyExtensions,
                    debugInfo: debugInfo,
                    convertTEX: convertTEX,
                    noTEXConvert: noTEXConvert,
                    singleDir: singleDir,
                    recursive: recursive,
                    copyProject: copyProject,
                    useName: useName,
                    overwrite: overwrite
                )

                do {
                    try repkgService.run(arguments: args)
                } catch {
                    extractionOutput += "Error: \(error.localizedDescription)\n"
                    break
                }

                while repkgService.isRunning {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }

        isExtracting = false
        statusText = "Extraction complete"
    }

    func extractAll() async {
        guard let inputDir = selectedDirectory, let outputDir = outputDirectory else {
            statusText = "Select input and output directories"
            return
        }

        isExtracting = true
        extractionOutput = ""
        showExtractSheet = true
        statusText = "Extracting all..."

        let args = RePKGService.buildArguments(
            inputPath: inputDir.path,
            outputDir: outputDir.path,
            ignoreExtensions: ignoreExtensions.isEmpty ? nil : ignoreExtensions,
            onlyExtensions: onlyExtensions.isEmpty ? nil : onlyExtensions,
            debugInfo: debugInfo,
            convertTEX: convertTEX,
            noTEXConvert: noTEXConvert,
            singleDir: singleDir,
            recursive: recursive,
            copyProject: copyProject,
            useName: useName,
            overwrite: overwrite
        )

        do {
            try repkgService.run(arguments: args)
        } catch {
            extractionOutput += "Error: \(error.localizedDescription)\n"
            isExtracting = false
            return
        }

        while repkgService.isRunning {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        isExtracting = false
    }

    func stopExtraction() {
        repkgService.stop()
        isExtracting = false
        statusText = "Extraction stopped"
    }

    // MARK: - Wallpaper Pipeline

    func startWallpaperPipeline(_ item: WallpaperItem, allScreens: Bool = false) {
        wallpaperTargetItem = item
        wallpaperForAllScreens = allScreens
        wallpaperPreparedContentURL = nil
        wallpaperAssets = []
        wallpaperStatus = ""

        Task {
            statusText = "Preparing wallpaper: \(item.title)..."
            wallpaperStatus = "Preparing..."

            let isScene = item.type.lowercased() == "scene"
            let isWeb = item.type.lowercased() == "web"
            let isDirectRenderable = isScene || isWeb
            let scanDir: URL

            if item.pkgPath != nil {
                scanDir = item.isExtracted
                    ? item.path.appendingPathComponent("extracted")
                    : item.path
            } else if item.isExtracted {
                scanDir = item.path.appendingPathComponent("extracted")
            } else {
                scanDir = item.path
            }

            wallpaperStatus = "Scanning for assets..."
            let assets = AssetScanner.scan(scanDir)
            wallpaperAssets = assets
            wallpaperPreparedContentURL = scanDir
            wallpaperStatus = ""

            if assets.isEmpty && !isDirectRenderable && item.pkgPath == nil {
                statusText = "No media files found in extracted output"
                return
            }

            showWallpaperPicker = true
            if isScene {
                statusText = assets.isEmpty
                    ? "Scene ready — render directly, bake to video, or extract media files"
                    : "\(assets.count) assets found — render scene directly or select one"
            } else if isWeb {
                statusText = assets.isEmpty
                    ? "Web wallpaper ready — render directly or extract media files"
                    : "\(assets.count) assets found — render web directly or select one"
            } else {
                statusText = assets.isEmpty
                    ? "Extract the wallpaper to list media files"
                    : "\(assets.count) assets found — select one"
            }
        }
    }

    func extractWallpaperAssetsForPicker() {
        guard let item = wallpaperTargetItem, let pkg = item.pkgPath else { return }
        guard !isExtracting else { return }

        Task {
            isExtracting = true
            wallpaperStatus = "Extracting package..."
            statusText = "Extracting wallpaper: \(item.title)..."
            let cacheDir = wallpaperCacheRoot.appendingPathComponent(item.id.sanitizedForPath)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

            let args = RePKGService.buildArguments(
                inputPath: pkg.path,
                outputDir: cacheDir.path,
                singleDir: true,
                recursive: false,
                overwrite: true
            )

            do {
                _ = try await repkgService.runAndWait(arguments: args)
                wallpaperStatus = "Scanning for assets..."
                let assets = AssetScanner.scan(cacheDir)
                wallpaperAssets = assets
                wallpaperPreparedContentURL = cacheDir
                statusText = assets.isEmpty
                    ? "No media files found in extracted output"
                    : "\(assets.count) assets found — select one"
            } catch {
                statusText = "Wallpaper extraction failed: \(error.localizedDescription)"
            }

            wallpaperStatus = ""
            isExtracting = false
        }
    }

    func bakedSceneVideoURL(for item: WallpaperItem) -> URL? {
        guard item.type.lowercased() == "scene" else { return nil }
        return SceneVideoBakeService.existingBakedVideoURL(for: item)
    }

    func deleteBakedSceneVideo(for item: WallpaperItem) {
        guard item.type.lowercased() == "scene" else { return }
        SceneVideoBakeService.deleteBakedVideo(for: item)
        statusText = "Deleted baked scene video: \(item.title)"
    }

    func sceneBakeScreenDescription() -> String {
        SceneVideoBakeService.currentScreenDescription()
    }

    func bakeSceneVideoForPicker(
        item: WallpaperItem,
        fps: Int,
        duration: Int,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async -> URL? {
        guard item.type.lowercased() == "scene" else { return nil }
        do {
            statusText = "Rendering scene video: \(item.title)..."
            let url = try await SceneVideoBakeService.bake(
                item: item,
                fps: fps,
                duration: duration,
                progress: progress
            )
            statusText = "Scene video rendered: \(url.lastPathComponent)"
            return url
        } catch {
            statusText = "Scene video render failed: \(error.localizedDescription)"
            return nil
        }
    }

    func finishSceneDirectSelection(_ item: WallpaperItem) {
        guard item.type.lowercased() == "scene" else { return }

        showWallpaperPicker = false
        do {
            webRendererService.stop()
            WallpaperService.killVideoWallpaper()
            let userProperties = SceneWallpaperPropertiesService.propertiesOverrideJSON(for: item.path)
            try sceneRendererService.setSceneWallpaper(
                projectURL: item.path,
                allScreens: wallpaperForAllScreens,
                isMuted: wallpaperMuted,
                userProperties: userProperties
            )
            saveLastSceneWallpaper(item.path, isMuted: wallpaperMuted, allScreens: wallpaperForAllScreens)
            if autoReplaceStaticWithFirstFrame {
                let allScreens = wallpaperForAllScreens
                let title = item.title
                Task {
                    await replaceStaticWallpaperWithCurrentSceneFrame(allScreens: allScreens, title: title)
                }
            }
            statusText = wallpaperForAllScreens
                ? "Scene wallpaper rendering on all screens: \(item.title)"
                : "Scene wallpaper rendering: \(item.title)"
        } catch {
            statusText = "Scene render failed: \(error.localizedDescription)"
        }

        wallpaperPreparedContentURL = nil
        wallpaperTargetItem = nil
    }

    func finishSceneBakedVideoSelection(_ item: WallpaperItem, videoURL: URL) {
        guard item.type.lowercased() == "scene" else { return }

        showWallpaperPicker = false
        do {
            sceneRendererService.stop()
            webRendererService.stop()
            WallpaperService.killVideoWallpaper()
            try wallpaperService.setWallpaper(
                filePath: videoURL,
                isMuted: wallpaperMuted,
                allScreens: wallpaperForAllScreens
            )
            saveLastWallpaper(videoURL, isMuted: wallpaperMuted)
            statusText = wallpaperForAllScreens
                ? "Baked scene video wallpaper set on all screens: \(item.title)"
                : "Baked scene video wallpaper set: \(item.title)"
        } catch {
            statusText = "Baked scene video wallpaper failed: \(error.localizedDescription)"
        }

        wallpaperPreparedContentURL = nil
        wallpaperTargetItem = nil
    }

    func finishWebDirectSelection(_ item: WallpaperItem) {
        guard item.type.lowercased() == "web" else { return }

        showWallpaperPicker = false
        let contentURL = wallpaperPreparedContentURL ?? item.path
        do {
            sceneRendererService.stop()
            WallpaperService.killVideoWallpaper()
            try webRendererService.setWebWallpaper(
                contentURL: contentURL,
                allScreens: wallpaperForAllScreens
            )
            saveLastWebWallpaper(contentURL, isMuted: wallpaperMuted, allScreens: wallpaperForAllScreens)
            if autoReplaceStaticWithFirstFrame {
                let allScreens = wallpaperForAllScreens
                let title = item.title
                Task {
                    await replaceStaticWallpaperWithCurrentWebFrame(allScreens: allScreens, title: title)
                }
            }
            statusText = wallpaperForAllScreens
                ? "Web wallpaper rendering on all screens: \(item.title)"
                : "Web wallpaper rendering: \(item.title)"
        } catch {
            statusText = "Web render failed: \(error.localizedDescription)"
        }

        wallpaperPreparedContentURL = nil
        wallpaperTargetItem = nil
    }

    private func replaceStaticWallpaperWithCurrentSceneFrame(allScreens: Bool, title: String) async {
        guard let frameURL = await sceneRendererService.captureFirstFrame() else {
            statusText = "Scene rendering: \(title) (first-frame capture unavailable)"
            return
        }

        do {
            try wallpaperService.setImageWallpaper(filePath: frameURL, allScreens: allScreens)
            statusText = "Scene wallpaper rendering: \(title) (static first frame applied)"
        } catch {
            statusText = "Scene first-frame wallpaper failed: \(error.localizedDescription)"
        }
    }

    private func replaceStaticWallpaperWithCurrentWebFrame(allScreens: Bool, title: String) async {
        guard let frameURL = await webRendererService.captureFirstFrame() else {
            statusText = "Web rendering: \(title) (first-frame capture unavailable)"
            return
        }

        do {
            try wallpaperService.setImageWallpaper(filePath: frameURL, allScreens: allScreens)
            statusText = "Web wallpaper rendering: \(title) (static first frame applied)"
        } catch {
            statusText = "Web first-frame wallpaper failed: \(error.localizedDescription)"
        }
    }

    func finishWallpaperSelection(_ asset: AssetFile) {
        guard wallpaperTargetItem != nil else { return }

        showWallpaperPicker = false

        do {
            sceneRendererService.stop()
            webRendererService.stop()
            WallpaperService.killVideoWallpaper()
            if wallpaperForAllScreens {
                if asset.isWeb {
                    try webRendererService.setWebWallpaper(
                        contentURL: asset.url,
                        allScreens: true
                    )
                } else if asset.isVideo {
                    try wallpaperService.setWallpaper(filePath: asset.url, isMuted: wallpaperMuted, allScreens: true)
                    if autoReplaceStaticWithFirstFrame {
                        Task {
                            if let frameURL = await WallpaperService.captureFirstFrame(videoURL: asset.url) {
                                try? wallpaperService.setImageWallpaper(filePath: frameURL, allScreens: true)
                            }
                        }
                    }
                } else {
                    try wallpaperService.setImageWallpaper(filePath: asset.url, allScreens: true)
                }
                statusText = "Wallpaper set on all screens: \(asset.name)\(wallpaperMuted ? " (muted)" : "")"
            } else {
                if asset.isWeb {
                    try webRendererService.setWebWallpaper(
                        contentURL: asset.url,
                        allScreens: false
                    )
                } else if asset.isVideo {
                    try wallpaperService.setWallpaper(filePath: asset.url, isMuted: wallpaperMuted)
                    if autoReplaceStaticWithFirstFrame {
                        Task {
                            if let frameURL = await WallpaperService.captureFirstFrame(videoURL: asset.url) {
                                try? wallpaperService.setImageWallpaper(filePath: frameURL)
                            }
                        }
                    }
                } else {
                    try wallpaperService.setImageWallpaper(filePath: asset.url)
                }
                let kind = asset.isWeb ? " (web)" : asset.isVideo ? " (video\(wallpaperMuted ? ", muted" : ""))" : ""
                statusText = "Wallpaper set: \(asset.name)\(kind)"
            }

            if asset.isWeb {
                saveLastWebWallpaper(asset.url, isMuted: wallpaperMuted, allScreens: wallpaperForAllScreens)
            } else {
                saveLastWallpaper(asset.url, isMuted: wallpaperMuted)
            }
        } catch {
            statusText = "Failed: \(error.localizedDescription)"
        }

        wallpaperPreparedContentURL = nil
        wallpaperTargetItem = nil
    }

    func setAsWallpaper(_ item: WallpaperItem) {
        if item.isRemote, !isRemoteWallpaperDownloaded(item) {
            downloadRemoteWallpaper(item)
            return
        }
        if scanMode == .flat, let previewPath = item.previewPath {
            setFlatWallpaper(url: previewPath, allScreens: false)
            return
        }
        startWallpaperPipeline(item, allScreens: false)
    }

    func setAsWallpaperForAllScreens(_ item: WallpaperItem) {
        if item.isRemote, !isRemoteWallpaperDownloaded(item) {
            downloadRemoteWallpaper(item)
            return
        }
        if scanMode == .flat, let previewPath = item.previewPath {
            setFlatWallpaper(url: previewPath, allScreens: true)
            return
        }
        startWallpaperPipeline(item, allScreens: true)
    }

    func refreshSceneWallpaperProperties(for item: WallpaperItem) {
        guard item.type.lowercased() == "scene" else { return }
        guard sceneRendererService.isRendering(projectURL: item.path) else {
            statusText = "Scene properties saved: \(item.title)"
            return
        }

        do {
            let userProperties = SceneWallpaperPropertiesService.propertiesOverrideJSON(for: item.path)
            try sceneRendererService.refreshSceneWallpaperProperties(userProperties: userProperties)
            statusText = "Scene properties applied: \(item.title)"
        } catch {
            statusText = "Scene properties saved, refresh failed: \(error.localizedDescription)"
        }
    }

    func reapplyCurrentSceneWallpaper() {
        guard UserDefaults.standard.string(forKey: UserDefaultsKey.lastWallpaperKind) == "scene" else {
            statusText = "No scene wallpaper to reapply"
            return
        }
        guard let path = UserDefaults.standard.string(forKey: UserDefaultsKey.lastWallpaper) else {
            statusText = "No scene wallpaper to reapply"
            return
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusText = "Scene wallpaper no longer exists"
            return
        }

        do {
            webRendererService.stop()
            WallpaperService.killVideoWallpaper()
            let isMuted = UserDefaults.standard.bool(forKey: UserDefaultsKey.lastWallpaperMuted)
            let allScreens = UserDefaults.standard.bool(forKey: UserDefaultsKey.lastWallpaperAllScreens)
            let userProperties = SceneWallpaperPropertiesService.propertiesOverrideJSON(for: url)
            try sceneRendererService.setSceneWallpaper(
                projectURL: url,
                allScreens: allScreens,
                isMuted: isMuted,
                userProperties: userProperties
            )
            currentSceneWallpaperPath = url.path
            statusText = "Scene rendering settings applied"
        } catch {
            statusText = "Scene reapply failed: \(error.localizedDescription)"
        }
    }

    private func setFlatWallpaper(url: URL, allScreens: Bool) {
        do {
            sceneRendererService.stop()
            webRendererService.stop()
            WallpaperService.killVideoWallpaper()
            if AssetScanner.webExtensions.contains(url.pathExtension.lowercased()) {
                try webRendererService.setWebWallpaper(
                    contentURL: url,
                    allScreens: allScreens
                )
                saveLastWebWallpaper(url, isMuted: wallpaperMuted, allScreens: allScreens)
            } else if allScreens {
                try wallpaperService.setWallpaper(filePath: url, isMuted: wallpaperMuted, allScreens: true)
                saveLastWallpaper(url, isMuted: wallpaperMuted)
            } else {
                try wallpaperService.setWallpaper(filePath: url, isMuted: wallpaperMuted)
                saveLastWallpaper(url, isMuted: wallpaperMuted)
            }
            statusText = "Wallpaper set: \(url.lastPathComponent)"
        } catch {
            statusText = "Failed: \(error.localizedDescription)"
        }
    }

    func openInFinder(_ item: WallpaperItem) {
        NSWorkspace.shared.selectFile(item.path.path, inFileViewerRootedAtPath: "")
    }

    func applyStaticWallpaper(_ fileURL: URL, assetName: String) {
        do {
            sceneRendererService.stop()
            webRendererService.stop()
            try wallpaperService.setImageWallpaper(filePath: fileURL)
            saveLastWallpaper(fileURL, isMuted: false)
            statusText = "Frame set: \(assetName)"
        } catch {
            statusText = "Frame failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Security-Scoped Bookmarks

    private func createSecurityScopedBookmark(for url: URL, key: String) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: key)
        } catch {
            statusText = "Failed to save bookmark: \(error.localizedDescription)"
        }
    }

    private func resolveBookmark(key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                let newBookmark = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(newBookmark, forKey: key)
            }
            guard url.startAccessingSecurityScopedResource() else { return nil }
            securityScopedURLs.insert(url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Persistence

    func saveSettings() {
        var dict: [String: Any] = [:]
        if let dir = selectedDirectory { dict["selectedDirectory"] = dir.path }
        dict["scanMode"] = scanMode.rawValue
        UserDefaults.standard.set(dict, forKey: UserDefaultsKey.appSettings)
        settings?.scanMode = scanMode
    }

    private func loadSettings() {
        guard let dict = UserDefaults.standard.dictionary(forKey: UserDefaultsKey.appSettings) else { return }

        // Restore directory via security-scoped bookmark if available,
        // falling back to raw path string for backward compatibility.
        if let resolved = resolveBookmark(key: UserDefaultsKey.savedDirectoryBookmark) {
            selectedDirectory = resolved
            localSelectedDirectory = resolved
        } else if let path = dict["selectedDirectory"] as? String {
            selectedDirectory = URL(fileURLWithPath: path)
            localSelectedDirectory = selectedDirectory
        }

        if let mode = dict["scanMode"] as? String {
            scanMode = ScanMode(rawValue: mode) ?? settings?.scanMode ?? .subdir
            settings?.scanMode = scanMode
        } else {
            scanMode = settings?.scanMode ?? scanMode
        }
    }

    func restoreWallpaperIfNeeded() {
        guard restoreLastWallpaper else { return }
        guard let path = UserDefaults.standard.string(forKey: UserDefaultsKey.lastWallpaper) else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let isMuted = UserDefaults.standard.bool(forKey: UserDefaultsKey.lastWallpaperMuted)
            let kind = UserDefaults.standard.string(forKey: UserDefaultsKey.lastWallpaperKind)
            if kind == "scene" {
                webRendererService.stop()
                WallpaperService.killVideoWallpaper()
                let allScreens = UserDefaults.standard.bool(forKey: UserDefaultsKey.lastWallpaperAllScreens)
                let userProperties = SceneWallpaperPropertiesService.propertiesOverrideJSON(for: url)
                try sceneRendererService.setSceneWallpaper(projectURL: url, allScreens: allScreens, isMuted: isMuted, userProperties: userProperties)
                currentSceneWallpaperPath = url.path
                currentWebWallpaperPath = nil
            } else if kind == "web" {
                sceneRendererService.stop()
                WallpaperService.killVideoWallpaper()
                let allScreens = UserDefaults.standard.bool(forKey: UserDefaultsKey.lastWallpaperAllScreens)
                try webRendererService.setWebWallpaper(
                    contentURL: url,
                    allScreens: allScreens
                )
                currentWebWallpaperPath = url.path
                currentSceneWallpaperPath = nil
            } else {
                sceneRendererService.stop()
                webRendererService.stop()
                WallpaperService.killVideoWallpaper()
                try wallpaperService.setWallpaper(filePath: url, isMuted: isMuted)
                currentSceneWallpaperPath = nil
                currentWebWallpaperPath = nil
            }
        } catch {
            statusText = "Restore wallpaper failed"
        }
    }

    private func saveLastWallpaper(_ url: URL, isMuted: Bool) {
        UserDefaults.standard.set(url.path, forKey: UserDefaultsKey.lastWallpaper)
        UserDefaults.standard.set(isMuted, forKey: UserDefaultsKey.lastWallpaperMuted)
        UserDefaults.standard.set("media", forKey: UserDefaultsKey.lastWallpaperKind)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.lastWallpaperAllScreens)
        currentSceneWallpaperPath = nil
        currentWebWallpaperPath = nil
    }

    private func saveLastSceneWallpaper(_ url: URL, isMuted: Bool, allScreens: Bool) {
        UserDefaults.standard.set(url.path, forKey: UserDefaultsKey.lastWallpaper)
        UserDefaults.standard.set(isMuted, forKey: UserDefaultsKey.lastWallpaperMuted)
        UserDefaults.standard.set("scene", forKey: UserDefaultsKey.lastWallpaperKind)
        UserDefaults.standard.set(allScreens, forKey: UserDefaultsKey.lastWallpaperAllScreens)
        currentSceneWallpaperPath = url.path
        currentWebWallpaperPath = nil
    }

    private func saveLastWebWallpaper(_ url: URL, isMuted: Bool, allScreens: Bool) {
        UserDefaults.standard.set(url.path, forKey: UserDefaultsKey.lastWallpaper)
        UserDefaults.standard.set(isMuted, forKey: UserDefaultsKey.lastWallpaperMuted)
        UserDefaults.standard.set("web", forKey: UserDefaultsKey.lastWallpaperKind)
        UserDefaults.standard.set(allScreens, forKey: UserDefaultsKey.lastWallpaperAllScreens)
        currentWebWallpaperPath = url.path
        currentSceneWallpaperPath = nil
    }

    func saveState() {
        saveSettings()
    }

    // MARK: - Search debounce

    func onSearchTextChanged() {
        searchDebounceTask?.cancel()
        let text = searchText
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(AppConstants.searchDebounceMilliseconds))
            guard !Task.isCancelled, let self else { return }
            debouncedSearchText = text
            filterGeneration &+= 1
        }
    }
}
