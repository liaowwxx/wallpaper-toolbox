import Foundation
import AppKit
import Darwin

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

    /// Tracks whether the initial onAppear launch sequence has run.
    @ObservationIgnored var appDidLaunch = false

    /// Bumped whenever filters or search change, providing animation context for ForEach transitions.
    @ObservationIgnored var filterGeneration = 0

    var isExtracting = false
    var extractionOutput = ""
    var showExtractSheet = false
    var showNewCollectionSheet = false

    var wallpaperAssets: [AssetFile] = []
    var showWallpaperPicker = false
    var wallpaperStatus = ""
    var wallpaperForAllScreens = false
    var wallpaperTargetItem: WallpaperItem?
    var showSceneProperties = false
    var scenePropertiesTargetItem: WallpaperItem?

    // Settings are now in SettingsStore, injected via environment.
    // These mirrors exist for backward-compatible access within the ViewModel.
    private var settings: SettingsStore?

    // MARK: - Services

    private let scanner = WallpaperScanner()
    private let repkgService = RePKGService()
    private let wallpaperService = WallpaperService()
    private let sceneRendererService = SceneWallpaperRendererService()
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

    var outputDirectory: URL? {
        get { settings?.outputDirectory ?? nil }
        set { settings?.outputDirectory = newValue }
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
    @ObservationIgnored private var _wallpaperGeneration: Int = 0

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

    var allCollections: [String] {
        if let cache = _cachedCollections, cache.generation == _wallpaperGeneration {
            return cache.result
        }
        var set = Set<String>()
        for wp in wallpapers {
            for c in wp.collections { set.insert(c) }
        }
        let result = set.sorted()
        _cachedCollections = (_wallpaperGeneration, result)
        return result
    }

    var filteredWallpapers: [WallpaperItem] {
        if let cache = _cachedFilters,
           cache.wallpaperGeneration == _wallpaperGeneration,
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
        _cachedFilters = (_wallpaperGeneration, debouncedSearchText, typeFilter, contentRatingFilter, collectionFilter, result)
        return result
    }

    var selectedWallpapers: [WallpaperItem] {
        let ids = selectedIDs
        return wallpapers.filter { ids.contains($0.id) }
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

    func scan(resetFilters: Bool = true) async {
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
        _wallpaperGeneration += 1
        isScanning = false
        statusText = "\(items.count) wallpapers found"

        let preloadURLs = items.prefix(AppConstants.thumbnailPreloadBatchSize).compactMap(\.thumbnailPath)
        Task.detached(priority: .background) {
            await ThumbnailView.preloadBatch(urls: preloadURLs)
        }
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
        _wallpaperGeneration += 1
        metadataService.saveMetadata(for: wallpapers[idx], mode: scanMode, flatRoot: selectedDirectory)
        statusText = "Content rating updated"
    }

    // MARK: - Collections

    func addToCollection(_ item: WallpaperItem, collection: String) {
        guard let idx = wallpapers.firstIndex(where: { $0.id == item.id }) else { return }
        if !wallpapers[idx].collections.contains(collection) {
            wallpapers[idx].collections.append(collection)
            _wallpaperGeneration += 1
            metadataService.saveMetadata(for: wallpapers[idx], mode: scanMode, flatRoot: selectedDirectory)
            statusText = "Added to '\(collection)'"
        }
    }

    func removeFromCollection(_ item: WallpaperItem, collection: String) {
        guard let idx = wallpapers.firstIndex(where: { $0.id == item.id }) else { return }
        wallpapers[idx].collections.removeAll { $0 == collection }
        _wallpaperGeneration += 1
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
        _wallpaperGeneration += 1
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
        if !affected.isEmpty { _wallpaperGeneration += 1 }
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
        if !affected.isEmpty { _wallpaperGeneration += 1 }
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
        if !affected.isEmpty { _wallpaperGeneration += 1 }
        for item in affected {
            metadataService.saveMetadata(for: item, mode: scanMode, flatRoot: selectedDirectory)
        }
        statusText = "Updated rating to '\(rating)' for \(affected.count) items"
    }

    // MARK: - Delete

    func deleteWallpaper(_ item: WallpaperItem) {
        do {
            try FileManager.default.removeItem(at: item.path)
            wallpapers.removeAll { $0.id == item.id }
            selectedIDs.remove(item.id)
            _wallpaperGeneration += 1

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
        for item in toDelete {
            do {
                try FileManager.default.removeItem(at: item.path)
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
        if deleted > 0 { _wallpaperGeneration += 1 }
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
        wallpaperStatus = ""

        Task {
            statusText = "Preparing wallpaper: \(item.title)..."
            wallpaperStatus = "Preparing..."

            if item.type.lowercased() == "scene" {
                do {
                    WallpaperService.killVideoWallpaper()
                    let userProperties = SceneWallpaperPropertiesService.propertiesOverrideJSON(for: item.path)
                    try sceneRendererService.setSceneWallpaper(
                        projectURL: item.path,
                        allScreens: allScreens,
                        isMuted: wallpaperMuted,
                        userProperties: userProperties
                    )
                    saveLastSceneWallpaper(item.path, isMuted: wallpaperMuted, allScreens: allScreens)
                    wallpaperStatus = ""
                    wallpaperTargetItem = nil
                    statusText = allScreens
                        ? "Scene wallpaper rendering on all screens: \(item.title)"
                        : "Scene wallpaper rendering: \(item.title)"
                } catch {
                    wallpaperStatus = ""
                    wallpaperTargetItem = nil
                    statusText = "Scene render failed: \(error.localizedDescription)"
                }
                return
            }

            let scanDir: URL

            if let pkg = item.pkgPath {
                wallpaperStatus = "Extracting package..."
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
                } catch {
                    statusText = "Wallpaper extraction failed: \(error.localizedDescription)"
                    wallpaperStatus = ""
                    return
                }
                scanDir = cacheDir
            } else if item.isExtracted {
                scanDir = item.path.appendingPathComponent("extracted")
            } else {
                scanDir = item.path
            }

            wallpaperStatus = "Scanning for assets..."
            let assets = AssetScanner.scan(scanDir)
            wallpaperAssets = assets
            wallpaperStatus = ""

            if assets.isEmpty {
                statusText = "No media files found in extracted output"
                return
            }

            showWallpaperPicker = true
            statusText = "\(assets.count) assets found — select one"
        }
    }

    func finishWallpaperSelection(_ asset: AssetFile) {
        guard wallpaperTargetItem != nil else { return }

        showWallpaperPicker = false

        do {
            sceneRendererService.stop()
            WallpaperService.killVideoWallpaper()
            if wallpaperForAllScreens {
                if asset.isVideo {
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
                try wallpaperService.setWallpaper(filePath: asset.url, isMuted: wallpaperMuted)
                if asset.isVideo, autoReplaceStaticWithFirstFrame {
                    Task {
                        if let frameURL = await WallpaperService.captureFirstFrame(videoURL: asset.url) {
                            try? wallpaperService.setImageWallpaper(filePath: frameURL)
                        }
                    }
                }
                let kind = asset.isVideo ? " (video\(wallpaperMuted ? ", muted" : ""))" : ""
                statusText = "Wallpaper set: \(asset.name)\(kind)"
            }

            saveLastWallpaper(asset.url, isMuted: wallpaperMuted)
        } catch {
            statusText = "Failed: \(error.localizedDescription)"
        }

        wallpaperTargetItem = nil
    }

    func setAsWallpaper(_ item: WallpaperItem) {
        if scanMode == .flat, let previewPath = item.previewPath {
            setFlatWallpaper(url: previewPath, allScreens: false)
            return
        }
        startWallpaperPipeline(item, allScreens: false)
    }

    func setAsWallpaperForAllScreens(_ item: WallpaperItem) {
        if scanMode == .flat, let previewPath = item.previewPath {
            setFlatWallpaper(url: previewPath, allScreens: true)
            return
        }
        startWallpaperPipeline(item, allScreens: true)
    }

    func openSceneProperties(_ item: WallpaperItem) {
        guard item.type.lowercased() == "scene" else { return }
        scenePropertiesTargetItem = item
        showSceneProperties = true
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
            statusText = "Scene rendering settings applied"
        } catch {
            statusText = "Scene reapply failed: \(error.localizedDescription)"
        }
    }

    private func setFlatWallpaper(url: URL, allScreens: Bool) {
        do {
            sceneRendererService.stop()
            WallpaperService.killVideoWallpaper()
            if allScreens {
                try wallpaperService.setWallpaper(filePath: url, isMuted: wallpaperMuted, allScreens: true)
            } else {
                try wallpaperService.setWallpaper(filePath: url, isMuted: wallpaperMuted)
            }
            saveLastWallpaper(url, isMuted: wallpaperMuted)
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
        } else if let path = dict["selectedDirectory"] as? String {
            selectedDirectory = URL(fileURLWithPath: path)
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
            if UserDefaults.standard.string(forKey: UserDefaultsKey.lastWallpaperKind) == "scene" {
                WallpaperService.killVideoWallpaper()
                let allScreens = UserDefaults.standard.bool(forKey: UserDefaultsKey.lastWallpaperAllScreens)
                let userProperties = SceneWallpaperPropertiesService.propertiesOverrideJSON(for: url)
                try sceneRendererService.setSceneWallpaper(projectURL: url, allScreens: allScreens, isMuted: isMuted, userProperties: userProperties)
            } else {
                sceneRendererService.stop()
                WallpaperService.killVideoWallpaper()
                try wallpaperService.setWallpaper(filePath: url, isMuted: isMuted)
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
    }

    private func saveLastSceneWallpaper(_ url: URL, isMuted: Bool, allScreens: Bool) {
        UserDefaults.standard.set(url.path, forKey: UserDefaultsKey.lastWallpaper)
        UserDefaults.standard.set(isMuted, forKey: UserDefaultsKey.lastWallpaperMuted)
        UserDefaults.standard.set("scene", forKey: UserDefaultsKey.lastWallpaperKind)
        UserDefaults.standard.set(allScreens, forKey: UserDefaultsKey.lastWallpaperAllScreens)
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
