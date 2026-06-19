import Foundation

/// Centralized constants used across the app.
enum AppConstants {

    // MARK: - Thumbnails

    /// Square-crop output dimension for generated thumbnails.
    static let thumbnailSize = 256
    /// Maximum number of cached NSImage thumbnails.
    static let thumbnailCacheCountLimit = 800
    /// Approximate memory ceiling for the thumbnail cache (80 MB).
    static let thumbnailCacheCostLimit = 80 * 1024 * 1024
    /// JPEG compression quality used for persisted thumbnails.
    static let thumbnailJPEGQuality: CGFloat = 0.75
    /// Number of thumbnails to preload after a scan completes.
    static let thumbnailPreloadBatchSize = 40

    /// JPEG compression quality for captured video frames.
    static let frameCaptureJPEGQuality: CGFloat = 0.85

    // MARK: - Search

    /// Debounce delay (ms) applied to search-text input.
    static let searchDebounceMilliseconds: UInt64 = 150

    // MARK: - Extraction

    /// Timeout (seconds) for ffmpeg thumbnail generation before the process is killed.
    static let ffmpegTimeoutSeconds: Double = 10

    // MARK: - App identity

    static let appBundleIdentifier = "com.wallpaper.gallery"
}

/// UserDefaults key constants.
/// Prevents typos and centralises key names in one place.
enum UserDefaultsKey {
    // General
    static let scanMode = "scanMode"
    static let restoreLastWallpaper = "restoreLastWallpaper"
    static let autoReplaceStatic = "autoReplaceStatic"

    // Wallpaper
    static let wallpaperMuted = "wallpaperMuted"

    // Output
    static let outputDirectoryPath = "outputDirectoryPath"

    // Extraction
    static let ignoreExts = "ignoreExts"
    static let onlyExts = "onlyExts"
    static let convertTex = "convertTex"
    static let noTexConvert = "noTexConvert"
    static let singleDir = "singleDir"
    static let recursive = "recursive"
    static let copyProject = "copyProject"
    static let useName = "useName"
    static let overwrite = "overwrite"
    static let debugInfo = "debugInfo"
    static let copyOnly = "copyOnly"

    // Bookmarks
    static let savedDirectoryBookmark = "savedDirectoryBookmark"
    static let savedOutputBookmark = "savedOutputBookmark"

    // Persistence
    static let appSettings = "com.wallpaper.gallery.settings"
    static let lastWallpaper = "com.wallpaper.gallery.settings.lastWallpaper"
    static let lastWallpaperMuted = "com.wallpaper.gallery.settings.lastWallpaperMuted"
    static let lastWallpaperKind = "com.wallpaper.gallery.settings.lastWallpaperKind"
    static let lastWallpaperAllScreens = "com.wallpaper.gallery.settings.lastWallpaperAllScreens"
    static let sceneRendererPIDs = "com.wallpaper.gallery.sceneRendererPIDs"
}
