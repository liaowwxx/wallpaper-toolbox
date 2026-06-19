import AppKit
import Darwin
import Foundation

@MainActor
final class SceneWallpaperRendererService {
    private struct RendererProcess {
        let pid: pid_t
        let process: Process
        let screenID: String
    }

    private var processes: [String: RendererProcess] = [:]
    private var activeProjectURL: URL?
    private var activeAllScreens = false
    private var activeMuted = true

    func setSceneWallpaper(projectURL: URL, allScreens: Bool, isMuted: Bool, userProperties: String? = nil) throws {
        guard let executableURL = Self.findRendererExecutable() else {
            throw SceneWallpaperRendererError.rendererNotFound
        }

        let sceneURL = try Self.resolveSceneInput(from: projectURL)
        let screens = allScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        guard !screens.isEmpty else {
            throw SceneWallpaperRendererError.noScreenAvailable
        }

        stop()
        Self.stopPersistedRendererProcesses()

        var launchedPIDs: [pid_t] = []
        do {
            for screen in screens {
                let process = try launchRenderer(
                    executableURL: executableURL,
                    sceneURL: sceneURL,
                    screen: screen,
                    isMuted: isMuted,
                    userProperties: userProperties
                )
                let screenID = Self.screenIdentifier(for: screen)
                processes[screenID] = RendererProcess(
                    pid: process.processIdentifier,
                    process: process,
                    screenID: screenID
                )
                launchedPIDs.append(process.processIdentifier)
            }
            Self.persistRendererPIDs(launchedPIDs)
            activeProjectURL = projectURL
            activeAllScreens = allScreens
            activeMuted = isMuted
        } catch {
            stop()
            throw error
        }
    }

    func refreshSceneWallpaperProperties(userProperties: String?) throws {
        guard let activeProjectURL else {
            throw SceneWallpaperRendererError.noActiveScene
        }
        try setSceneWallpaper(
            projectURL: activeProjectURL,
            allScreens: activeAllScreens,
            isMuted: activeMuted,
            userProperties: userProperties
        )
    }

    func isRendering(projectURL: URL) -> Bool {
        activeProjectURL?.standardizedFileURL == projectURL.standardizedFileURL
    }

    func stop() {
        guard !processes.isEmpty else {
            activeProjectURL = nil
            Self.stopPersistedRendererProcesses()
            return
        }
        for (_, info) in processes {
            if info.process.isRunning {
                info.process.terminate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if kill(info.pid, 0) == 0 {
                        kill(info.pid, SIGKILL)
                    }
                }
            }
        }
        processes.removeAll()
        activeProjectURL = nil
        Self.clearPersistedRendererPIDs()
    }

    nonisolated static func stopPersistedRendererProcesses() {
        let defaults = UserDefaults.standard
        let pids = defaults.array(forKey: UserDefaultsKey.sceneRendererPIDs) as? [Int] ?? []
        guard !pids.isEmpty else { return }

        for rawPID in pids {
            let pid = pid_t(rawPID)
            guard pid > 0, kill(pid, 0) == 0 else { continue }
            kill(pid, SIGTERM)
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) {
            for rawPID in pids {
                let pid = pid_t(rawPID)
                guard pid > 0, kill(pid, 0) == 0 else { continue }
                kill(pid, SIGKILL)
            }
        }
        defaults.removeObject(forKey: UserDefaultsKey.sceneRendererPIDs)
    }

    private func launchRenderer(
        executableURL: URL,
        sceneURL: URL,
        screen: NSScreen,
        isMuted: Bool,
        userProperties: String?
    ) throws -> Process {
        let frame = screen.frame
        let scale = screen.backingScaleFactor
        let screenArg = [
            Int(frame.origin.x.rounded()),
            Int(frame.origin.y.rounded()),
            Int(frame.width.rounded()),
            Int(frame.height.rounded())
        ].map(String.init).joined(separator: ",") + ",\(scale)"

        var args = [
            sceneURL.path,
            "--wallpaper",
            "--background",
            "--screen", screenArg,
            "--fps", "\(Self.effectiveFPS(for: screen))"
        ]

        if let assetsURL = Self.findAssetsDirectory() {
            args += ["--assets", assetsURL.path]
        }
        if Self.isUpscalingEnabled() {
            args += ["--upscaling", "\(Self.upscalingPercent())"]
        }
        if isMuted {
            args.append("--muted")
        }
        if let userProperties, !userProperties.isEmpty {
            args += ["--user-properties", userProperties]
        }

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.arguments = args
        process.environment = Self.launchEnvironment(for: executableURL)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private static func resolveSceneInput(from projectURL: URL) throws -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: projectURL.path, isDirectory: &isDirectory) else {
            throw SceneWallpaperRendererError.sceneNotFound
        }

        if !isDirectory.boolValue {
            return projectURL
        }

        if fm.fileExists(atPath: projectURL.appendingPathComponent("project.json").path) {
            return projectURL
        }

        if let pkgURL = try? fm.contentsOfDirectory(at: projectURL, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension.lowercased() == "pkg" }) {
            return pkgURL
        }

        throw SceneWallpaperRendererError.sceneNotFound
    }

    private static func findRendererExecutable() -> URL? {
        if let envPath = ProcessInfo.processInfo.environment["WALLPAPER_WGPU_PATH"] {
            let url = PathResolver.resolve(envPath)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }

        let resourceURL = Bundle.main.resourceURL
        let execDirURL = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidates: [URL?] = [
            resourceURL?.appendingPathComponent("wallpaper-wgpu"),
            resourceURL?.appendingPathComponent("bin/wallpaper-wgpu"),
            execDirURL?.appendingPathComponent("wallpaper-wgpu"),
            execDirURL?.appendingPathComponent("bin/wallpaper-wgpu"),
            PathResolver.resolve("resources/bin/wallpaper-wgpu")
        ]

        return candidates.first { candidate in
            guard let candidate else { return false }
            return FileManager.default.fileExists(atPath: candidate.path)
        } ?? nil
    }

    private static func findAssetsDirectory() -> URL? {
        if let envPath = ProcessInfo.processInfo.environment["WALLPAPER_WGPU_ASSETS_PATH"] {
            let url = PathResolver.resolve(envPath)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }

        let resourceURL = Bundle.main.resourceURL
        let candidates: [URL?] = [
            resourceURL?.appendingPathComponent("assets"),
            resourceURL?.appendingPathComponent("assets-pc"),
            resourceURL?.appendingPathComponent("bin/assets"),
            resourceURL?.appendingPathComponent("bin/assets-pc"),
            PathResolver.resolve("resources/assets"),
            PathResolver.resolve("resources/assets-pc")
        ]

        return candidates.first { candidate in
            guard let candidate else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        } ?? nil
    }

    private static func launchEnvironment(for executableURL: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let executableDirectory = executableURL.deletingLastPathComponent()
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = [
            executableDirectory.path,
            executableDirectory.deletingLastPathComponent().path,
            executableDirectory.appendingPathComponent("bin").path,
            existingPath
        ].filter { !$0.isEmpty }.joined(separator: ":")
        return environment
    }

    private static func refreshRate(for screen: NSScreen) -> Int {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let mode = CGDisplayCopyDisplayMode(CGDirectDisplayID(number.uint32Value)) else {
            return 60
        }
        let rate = mode.refreshRate
        guard rate > 0 else { return 60 }
        return max(30, min(240, Int(rate.rounded())))
    }

    private static func effectiveFPS(for screen: NSScreen) -> Int {
        min(sceneFPSCap(), refreshRate(for: screen))
    }

    private static func sceneFPSCap() -> Int {
        let rawValue = UserDefaults.standard.double(forKey: UserDefaultsKey.sceneFPSCap)
        let value = rawValue > 0 ? rawValue : 60
        return max(30, min(240, Int(value.rounded())))
    }

    private static func isUpscalingEnabled() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: UserDefaultsKey.sceneUpscalingEnabled) == nil {
            return true
        }
        return defaults.bool(forKey: UserDefaultsKey.sceneUpscalingEnabled)
    }

    private static func upscalingPercent() -> Int {
        let rawValue = UserDefaults.standard.double(forKey: UserDefaultsKey.sceneUpscalingPercent)
        let value = rawValue > 0 ? rawValue : 70
        return max(30, min(100, Int(value.rounded())))
    }

    private static func screenIdentifier(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display-\(number.uint32Value)"
        }
        return screen.localizedName
    }

    private static func persistRendererPIDs(_ pids: [pid_t]) {
        UserDefaults.standard.set(pids.map(Int.init), forKey: UserDefaultsKey.sceneRendererPIDs)
    }

    private static func clearPersistedRendererPIDs() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.sceneRendererPIDs)
    }
}

enum SceneWallpaperRendererError: LocalizedError {
    case rendererNotFound
    case sceneNotFound
    case noScreenAvailable
    case noActiveScene

    var errorDescription: String? {
        switch self {
        case .rendererNotFound:
            return "wallpaper-wgpu renderer not found. Expected resources/bin/wallpaper-wgpu or set WALLPAPER_WGPU_PATH."
        case .sceneNotFound:
            return "Scene wallpaper project or package was not found."
        case .noScreenAvailable:
            return "No display is available to render the scene wallpaper on."
        case .noActiveScene:
            return "No scene wallpaper is currently rendering."
        }
    }
}
