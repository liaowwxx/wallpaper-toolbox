import Foundation

/// Reactive, persistent settings store.
/// All settings read/write directly to UserDefaults.
/// Injected via `.environment()` so both the main window and the Settings scene
/// stay in sync through SwiftUI's observation.
@Observable
@MainActor
final class SettingsStore {
    private let defaults = UserDefaults.standard

    // MARK: - General

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
