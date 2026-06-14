import Foundation
import AppKit
import AVFoundation

final class WallpaperService {

    func setWallpaper(filePath: URL, isMuted: Bool = false, allScreens: Bool = false) throws {
        let ext = filePath.pathExtension.lowercased()
        if AssetScanner.videoExtensions.contains(ext) {
            try setVideoWallpaper(filePath: filePath, isMuted: isMuted)
        } else {
            try setImageWallpaper(filePath: filePath, allScreens: allScreens)
        }
    }

    func setImageWallpaper(filePath: URL, allScreens: Bool = false) throws {
        if allScreens {
            guard !NSScreen.screens.isEmpty else {
                throw WallpaperError.noScreenAvailable
            }
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(filePath, for: screen, options: [:])
            }
            return
        }

        guard let screen = NSScreen.main else {
            throw WallpaperError.noScreenAvailable
        }
        try NSWorkspace.shared.setDesktopImageURL(filePath, for: screen, options: [:])
    }

    private func setVideoWallpaper(filePath: URL, isMuted: Bool) throws {
        let playerPath = findWallpaperPlayer()
        guard let player = playerPath, FileManager.default.fileExists(atPath: player.path) else {
            throw WallpaperError.playerNotFound
        }

        let process = Process()
        process.executableURL = player
        var args = [filePath.path]
        if isMuted { args.append("--mute") }
        process.arguments = args
        try process.run()
    }

    private func findWallpaperPlayer() -> URL? {
        let resourceURL = Bundle.main.resourceURL
        let execDirURL = Bundle.main.executableURL?.deletingLastPathComponent()

        let candidates: [URL?] = [
            resourceURL?.appendingPathComponent("WallpaperPlayer"),
            resourceURL?.appendingPathComponent("bin/WallpaperPlayer"),
            execDirURL?.appendingPathComponent("WallpaperPlayer"),
            PathResolver.resolve("../resources/bin/WallpaperPlayer"),
        ]

        return candidates.first(where: {
            guard let url = $0 else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }) ?? nil
    }

    // resolvePath → PathResolver.resolve in PathResolver.swift

    static func killVideoWallpaper() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["WallpaperPlayer"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    // MARK: - Frame capture

    static func captureFrame(videoURL: URL, at time: CMTime) async -> URL? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let cgImage: CGImage
        do {
            (cgImage, _) = try await generator.image(at: time)
        } catch {
            return nil
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("repkg-frame-\(Int(Date().timeIntervalSince1970)).jpg")

        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: AppConstants.frameCaptureJPEGQuality]
        CGImageDestinationAddImage(dest, cgImage, opts as CFDictionary)

        return CGImageDestinationFinalize(dest) ? tmp : nil
    }

    static func captureFirstFrame(videoURL: URL) async -> URL? {
        await captureFrame(videoURL: videoURL, at: .zero)
    }
}

enum WallpaperError: LocalizedError {
    case playerNotFound
    case noScreenAvailable

    var errorDescription: String? {
        switch self {
        case .playerNotFound:
            return "WallpaperPlayer binary not found. Video wallpaper requires the native player."
        case .noScreenAvailable:
            return "No display is available to set the wallpaper on."
        }
    }
}
