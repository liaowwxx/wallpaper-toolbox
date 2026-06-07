import Foundation
import SwiftUI

/// Persistent settings wrapper (not @Observable).
/// Settings are read/written to UserDefaults directly.
/// The AppViewModel (which is @Observable) owns the reactive bridge
/// via its computed settings properties that delegate here.
final class SettingsStore {
    private let defaults = UserDefaults.standard

    // MARK: - General

    var scanMode: ScanMode {
        get {
            let raw = defaults.string(forKey: "scanMode") ?? ScanMode.subdir.rawValue
            return ScanMode(rawValue: raw) ?? .subdir
        }
        set { defaults.set(newValue.rawValue, forKey: "scanMode") }
    }

    var restoreLastWallpaper: Bool {
        get { defaults.bool(forKey: "restoreLastWallpaper") }
        set { defaults.set(newValue, forKey: "restoreLastWallpaper") }
    }

    var autoReplaceStaticWithFirstFrame: Bool {
        get { defaults.bool(forKey: "autoReplaceStatic") }
        set { defaults.set(newValue, forKey: "autoReplaceStatic") }
    }

    // MARK: - Wallpaper

    var wallpaperMuted: Bool {
        get { defaults.object(forKey: "wallpaperMuted") == nil ? true : defaults.bool(forKey: "wallpaperMuted") }
        set { defaults.set(newValue, forKey: "wallpaperMuted") }
    }

    // MARK: - Output

    var outputDirectory: URL? {
        get {
            guard let path = defaults.string(forKey: "outputDirectoryPath"), !path.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
        set { defaults.set(newValue?.path ?? "", forKey: "outputDirectoryPath") }
    }

    // MARK: - Extraction defaults

    var ignoreExts: String {
        get { defaults.string(forKey: "ignoreExts") ?? "" }
        set { defaults.set(newValue, forKey: "ignoreExts") }
    }

    var onlyExts: String {
        get { defaults.string(forKey: "onlyExts") ?? "" }
        set { defaults.set(newValue, forKey: "onlyExts") }
    }

    var convertTex: Bool {
        get { defaults.bool(forKey: "convertTex") }
        set { defaults.set(newValue, forKey: "convertTex") }
    }

    var noTexConvert: Bool {
        get { defaults.bool(forKey: "noTexConvert") }
        set { defaults.set(newValue, forKey: "noTexConvert") }
    }

    var singleDir: Bool {
        get { defaults.bool(forKey: "singleDir") }
        set { defaults.set(newValue, forKey: "singleDir") }
    }

    var recursive: Bool {
        get { defaults.object(forKey: "recursive") == nil ? true : defaults.bool(forKey: "recursive") }
        set { defaults.set(newValue, forKey: "recursive") }
    }

    var copyProject: Bool {
        get { defaults.bool(forKey: "copyProject") }
        set { defaults.set(newValue, forKey: "copyProject") }
    }

    var useName: Bool {
        get { defaults.bool(forKey: "useName") }
        set { defaults.set(newValue, forKey: "useName") }
    }

    var overwrite: Bool {
        get { defaults.bool(forKey: "overwrite") }
        set { defaults.set(newValue, forKey: "overwrite") }
    }

    var debugInfo: Bool {
        get { defaults.bool(forKey: "debugInfo") }
        set { defaults.set(newValue, forKey: "debugInfo") }
    }

    var copyOnly: Bool {
        get { defaults.bool(forKey: "copyOnly") }
        set { defaults.set(newValue, forKey: "copyOnly") }
    }
}
