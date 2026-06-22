import Foundation

enum LibraryMode: String, CaseIterable {
    case local
    case remote

    var label: String {
        switch self {
        case .local: return "Local"
        case .remote: return "Remote"
        }
    }
}

enum GalleryAccentMode: String, CaseIterable, Identifiable {
    case automatic
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .custom: return "Custom"
        }
    }
}

/// Reactive, persistent settings store.
/// All settings read/write directly to UserDefaults.
/// Injected via `.environment()` so both the main window and the Settings scene
/// stay in sync through SwiftUI's observation.
@Observable
@MainActor
final class SettingsStore {
    private let defaults = UserDefaults.standard

    var appLanguage: AppLanguage {
        didSet { defaults.set(appLanguage.rawValue, forKey: UserDefaultsKey.appLanguage) }
    }

    var galleryAccentMode: GalleryAccentMode {
        didSet { defaults.set(galleryAccentMode.rawValue, forKey: UserDefaultsKey.galleryAccentMode) }
    }

    var customGalleryAccentHex: String {
        didSet { defaults.set(customGalleryAccentHex, forKey: UserDefaultsKey.customGalleryAccentHex) }
    }

    var effectiveLanguage: AppLanguage {
        appLanguage.effectiveLanguage
    }

    init() {
        let rawLanguage = defaults.string(forKey: UserDefaultsKey.appLanguage) ?? AppLanguage.system.rawValue
        appLanguage = AppLanguage(rawValue: rawLanguage) ?? .system
        let rawAccentMode = defaults.string(forKey: UserDefaultsKey.galleryAccentMode) ?? GalleryAccentMode.automatic.rawValue
        galleryAccentMode = GalleryAccentMode(rawValue: rawAccentMode) ?? .automatic
        customGalleryAccentHex = defaults.string(forKey: UserDefaultsKey.customGalleryAccentHex) ?? "#705CF2"
    }

    // MARK: - General

    var libraryMode: LibraryMode {
        get {
            let raw = defaults.string(forKey: UserDefaultsKey.libraryMode) ?? LibraryMode.local.rawValue
            return LibraryMode(rawValue: raw) ?? .local
        }
        set { defaults.set(newValue.rawValue, forKey: UserDefaultsKey.libraryMode) }
    }

    var scanMode: ScanMode {
        get {
            let raw = defaults.string(forKey: UserDefaultsKey.scanMode) ?? ScanMode.subdir.rawValue
            return ScanMode(rawValue: raw) ?? .subdir
        }
        set { defaults.set(newValue.rawValue, forKey: UserDefaultsKey.scanMode) }
    }

    var restoreLastWallpaper: Bool {
        get { defaults.bool(forKey: UserDefaultsKey.restoreLastWallpaper) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.restoreLastWallpaper) }
    }

    var autoReplaceStaticWithFirstFrame: Bool {
        get { defaults.bool(forKey: UserDefaultsKey.autoReplaceStatic) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.autoReplaceStatic) }
    }

    var remoteServerURL: String {
        get { defaults.string(forKey: UserDefaultsKey.remoteServerURL) ?? "http://localhost:8090" }
        set { defaults.set(newValue, forKey: UserDefaultsKey.remoteServerURL) }
    }

    var remoteUsername: String {
        get { defaults.string(forKey: UserDefaultsKey.remoteUsername) ?? "" }
        set { defaults.set(newValue, forKey: UserDefaultsKey.remoteUsername) }
    }

    var remotePassword: String {
        get { defaults.string(forKey: UserDefaultsKey.remotePassword) ?? "" }
        set { defaults.set(newValue, forKey: UserDefaultsKey.remotePassword) }
    }

    var remoteDownloadDirectory: URL {
        get {
            if let path = defaults.string(forKey: UserDefaultsKey.remoteDownloadDirectoryPath), !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Wallpaper Toolbox Remote", isDirectory: true)
        }
        set { defaults.set(newValue.path, forKey: UserDefaultsKey.remoteDownloadDirectoryPath) }
    }

    // MARK: - Wallpaper

    var wallpaperMuted: Bool {
        get { defaults.object(forKey: UserDefaultsKey.wallpaperMuted) == nil ? true : defaults.bool(forKey: UserDefaultsKey.wallpaperMuted) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.wallpaperMuted) }
    }

    var sceneUpscalingEnabled: Bool {
        get {
            defaults.object(forKey: UserDefaultsKey.sceneUpscalingEnabled) == nil
                ? true
                : defaults.bool(forKey: UserDefaultsKey.sceneUpscalingEnabled)
        }
        set { defaults.set(newValue, forKey: UserDefaultsKey.sceneUpscalingEnabled) }
    }

    var sceneUpscalingPercent: Double {
        get {
            let value = defaults.double(forKey: UserDefaultsKey.sceneUpscalingPercent)
            return value > 0 ? value : 70
        }
        set { defaults.set(max(30, min(100, newValue)), forKey: UserDefaultsKey.sceneUpscalingPercent) }
    }

    var sceneFPSCap: Double {
        get {
            let value = defaults.double(forKey: UserDefaultsKey.sceneFPSCap)
            return value > 0 ? value : 60
        }
        set { defaults.set(max(30, min(240, newValue)), forKey: UserDefaultsKey.sceneFPSCap) }
    }

    // MARK: - Output

    var outputDirectory: URL? {
        get {
            guard let path = defaults.string(forKey: UserDefaultsKey.outputDirectoryPath), !path.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
        set { defaults.set(newValue?.path ?? "", forKey: UserDefaultsKey.outputDirectoryPath) }
    }

    // MARK: - Extraction defaults

    var ignoreExtensions: String {
        get { defaults.string(forKey: UserDefaultsKey.ignoreExts) ?? "" }
        set { defaults.set(newValue, forKey: UserDefaultsKey.ignoreExts) }
    }

    var onlyExtensions: String {
        get { defaults.string(forKey: UserDefaultsKey.onlyExts) ?? "" }
        set { defaults.set(newValue, forKey: UserDefaultsKey.onlyExts) }
    }

    var convertTEX: Bool {
        get { defaults.bool(forKey: UserDefaultsKey.convertTex) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.convertTex) }
    }

    var noTEXConvert: Bool {
        get { defaults.bool(forKey: UserDefaultsKey.noTexConvert) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.noTexConvert) }
    }

    var singleDir: Bool {
        get { defaults.bool(forKey: UserDefaultsKey.singleDir) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.singleDir) }
    }

    var recursive: Bool {
        get { defaults.object(forKey: UserDefaultsKey.recursive) == nil ? true : defaults.bool(forKey: UserDefaultsKey.recursive) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.recursive) }
    }

    var copyProject: Bool {
        get { defaults.bool(forKey: UserDefaultsKey.copyProject) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.copyProject) }
    }

    var useName: Bool {
        get { defaults.bool(forKey: UserDefaultsKey.useName) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.useName) }
    }

    var overwrite: Bool {
        get { defaults.bool(forKey: UserDefaultsKey.overwrite) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.overwrite) }
    }

    var debugInfo: Bool {
        get { defaults.bool(forKey: UserDefaultsKey.debugInfo) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.debugInfo) }
    }

    var copyOnly: Bool {
        get { defaults.bool(forKey: UserDefaultsKey.copyOnly) }
        set { defaults.set(newValue, forKey: UserDefaultsKey.copyOnly) }
    }
}
