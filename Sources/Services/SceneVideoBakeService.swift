import AppKit
import AVFoundation
import Foundation

enum SceneVideoBakeError: LocalizedError {
    case rendererNotFound
    case sceneNotFound
    case noScreenAvailable
    case outputMissing
    case fallbackEncodingFailed(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .rendererNotFound:
            return "wallpaper-wgpu renderer not found. Expected resources/bin/wallpaper-wgpu or set WALLPAPER_WGPU_PATH."
        case .sceneNotFound:
            return "Scene wallpaper project or package was not found."
        case .noScreenAvailable:
            return "No display is available for scene video rendering."
        case .outputMissing:
            return "The baked scene video was not created or is not playable."
        case .fallbackEncodingFailed(let message):
            return "The renderer produced PNG frames, but fallback video encoding failed: \(message)"
        case .processFailed(let message):
            return message
        }
    }
}

struct SceneVideoBakeService {
    private final class OutputCapture: @unchecked Sendable {
        var data = Data()

        func append(_ chunk: Data) {
            data.append(chunk)
            let maxBytes = 128 * 1024
            if data.count > maxBytes {
                data.removeFirst(data.count - maxBytes)
            }
        }
    }

    @MainActor
    static func bakedVideoURL(for item: WallpaperItem) -> URL {
        sceneBakesRoot
            .appendingPathComponent(item.isRemote ? "remote" : "local", isDirectory: true)
            .appendingPathComponent(cacheItemID(for: item), isDirectory: true)
            .appendingPathComponent("scene-bake.mp4")
    }

    @MainActor
    static func hasUsableBakedVideo(for item: WallpaperItem) -> Bool {
        existingBakedVideoURL(for: item) != nil
    }

    @MainActor
    static func existingBakedVideoURL(for item: WallpaperItem) -> URL? {
        bakedVideoCandidates(for: item).first { isUsableVideo(at: $0) }
    }

    @MainActor
    static func deleteBakedVideo(for item: WallpaperItem) {
        let fm = FileManager.default
        for url in bakedVideoCandidates(for: item) {
            try? fm.removeItem(at: url)
            try? fm.removeItem(at: pngFrameDirectory(for: url))
        }
    }

    @MainActor
    static func currentScreenDescription() -> String {
        let size = currentScreenPixelSize()
        return "\(size.width)x\(size.height)"
    }

    @MainActor
    static func bake(
        item: WallpaperItem,
        fps: Int,
        duration: Int,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async throws -> URL {
        guard let executableURL = findRendererExecutable() else {
            throw SceneVideoBakeError.rendererNotFound
        }
        let sceneURL = try resolveSceneInput(from: item.path)
        let outURL = bakedVideoURL(for: item)
        let tempURL = outURL.deletingLastPathComponent()
            .appendingPathComponent(".scene-bake-\(UUID().uuidString).tmp.mp4")
        let screenSize = currentScreenPixelSize()

        try FileManager.default.createDirectory(
            at: outURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: tempURL)

        var args = [
            "bake",
            sceneURL.path,
            "--size", "\(screenSize.width)x\(screenSize.height)",
            "--fps", String(max(1, min(240, fps))),
            "--clean",
            "--out", tempURL.path,
            "--duration", String(max(1, duration))
        ]

        if let assetsURL = findAssetsDirectory() {
            args += ["--assets", assetsURL.path]
        }

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.arguments = args
        process.environment = launchEnvironment(for: executableURL)
        process.standardOutput = FileHandle.nullDevice

        let stderrPipe = Pipe()
        let capture = OutputCapture()
        process.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            capture.append(chunk)
            guard let text = String(data: chunk, encoding: .utf8) else { return }
            for line in text.components(separatedBy: CharacterSet.newlines) {
                guard let value = progressValue(from: line) else { continue }
                Task { @MainActor in progress?(value) }
            }
        }

        try process.run()
        while process.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            let stderrText = String(data: capture.data, encoding: .utf8)?
                .components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .suffix(12)
                .joined(separator: "\n") ?? ""
            let message = stderrText.isEmpty
                ? "wallpaper-wgpu bake failed with exit code \(process.terminationStatus)."
                : "wallpaper-wgpu bake failed with exit code \(process.terminationStatus):\n\(stderrText)"
            throw SceneVideoBakeError.processFailed(message)
        }

        if !(await isUsableVideoAsync(at: tempURL)) {
            let frameDirectory = pngFrameDirectory(for: tempURL)
            if FileManager.default.fileExists(atPath: frameDirectory.path) {
                try? FileManager.default.removeItem(at: tempURL)
                await MainActor.run { progress?(0.99) }
                do {
                    try await encodePNGSequence(
                        frameDirectory: frameDirectory,
                        outputURL: tempURL,
                        fps: max(1, min(240, fps))
                    )
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    throw SceneVideoBakeError.fallbackEncodingFailed(error.localizedDescription)
                }
            }
        }

        guard await isUsableVideoAsync(at: tempURL) else {
            let stderrText = String(data: capture.data, encoding: .utf8) ?? ""
            try? FileManager.default.removeItem(at: tempURL)
            throw SceneVideoBakeError.processFailed(
                rendererOutputFailureMessage(from: stderrText)
            )
        }

        try? FileManager.default.removeItem(at: outURL)
        try FileManager.default.moveItem(at: tempURL, to: outURL)
        try? FileManager.default.removeItem(at: pngFrameDirectory(for: tempURL))
        await MainActor.run { progress?(1.0) }
        return outURL
    }

    @MainActor
    private static var sceneBakesRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("\(AppConstants.appBundleIdentifier)/SceneBakes", isDirectory: true)
    }

    @MainActor
    private static func bakedVideoCandidates(for item: WallpaperItem) -> [URL] {
        let primaryURL = bakedVideoURL(for: item)
        let legacyURL = sceneBakesRoot
            .appendingPathComponent(item.id.sanitizedForPath, isDirectory: true)
            .appendingPathComponent("scene-bake.mp4")
        return primaryURL == legacyURL ? [primaryURL] : [primaryURL, legacyURL]
    }

    private static func cacheItemID(for item: WallpaperItem) -> String {
        if item.isRemote, let remoteID = item.remoteID, !remoteID.isEmpty {
            return remoteID.sanitizedForPath
        }
        return item.id.sanitizedForPath
    }

    @MainActor
    private static func currentScreenPixelSize() -> (width: Int, height: Int) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let scale = screen?.backingScaleFactor ?? 1
        let width = max(64, Int((frame.width * scale).rounded()))
        let height = max(64, Int((frame.height * scale).rounded()))
        return ((width / 2) * 2, (height / 2) * 2)
    }

    private static func progressValue(from line: String) -> Double? {
        guard let percentRange = line.range(of: #"\[(\d+(?:\.\d+)?)%\]"#, options: .regularExpression),
              let numberRange = line[percentRange].range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression),
              let percent = Double(line[numberRange]) else {
            return nil
        }

        let phaseValue = max(0, min(1, percent / 100))
        if line.contains("预热") {
            return phaseValue * 0.2
        }
        if line.contains("录制") || line.localizedCaseInsensitiveContains("record") {
            return 0.2 + phaseValue * 0.78
        }
        if line.contains("编码") || line.localizedCaseInsensitiveContains("encode") {
            return max(0.98, phaseValue)
        }
        if line.contains("完成") || line.localizedCaseInsensitiveContains("complete") {
            return 1.0
        }
        return phaseValue
    }

    private static func pngFrameDirectory(for outputURL: URL) -> URL {
        outputURL.deletingPathExtension()
    }

    private static func rendererOutputFailureMessage(from stderrText: String) -> String {
        let compactLog = stderrText
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(16)
            .joined(separator: "\n")
        if stderrText.contains("ffmpeg 未找到") || stderrText.localizedCaseInsensitiveContains("ffmpeg") {
            return "wallpaper-wgpu did not produce a playable MP4. It reported an ffmpeg-related fallback, and no usable video could be encoded.\n\(compactLog)"
        }
        return compactLog.isEmpty
            ? "wallpaper-wgpu finished, but no playable MP4 was produced."
            : "wallpaper-wgpu finished, but no playable MP4 was produced.\n\(compactLog)"
    }

    private static func encodePNGSequence(frameDirectory: URL, outputURL: URL, fps: Int) async throws {
        try await Task.detached(priority: .utility) {
            try encodePNGSequenceSync(frameDirectory: frameDirectory, outputURL: outputURL, fps: fps)
        }.value
    }

    private static func encodePNGSequenceSync(frameDirectory: URL, outputURL: URL, fps: Int) throws {
        let fm = FileManager.default
        let frameURLs = try fm.contentsOfDirectory(
            at: frameDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let firstFrameURL = frameURLs.first,
              let firstImage = loadCGImage(firstFrameURL) else {
            throw SceneVideoBakeError.outputMissing
        }

        try? fm.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let width = firstImage.width
        let height = firstImage.height
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(8_000_000, width * height * 2),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )

        guard writer.canAdd(input) else {
            throw SceneVideoBakeError.fallbackEncodingFailed("AVAssetWriter cannot add video input.")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? SceneVideoBakeError.fallbackEncodingFailed("AVAssetWriter failed to start.")
        }
        writer.startSession(atSourceTime: .zero)

        for (index, frameURL) in frameURLs.enumerated() {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.002)
            }

            guard let image = loadCGImage(frameURL),
                  let pixelBuffer = makePixelBuffer(from: image, width: width, height: height) else {
                continue
            }

            let time = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
            guard adaptor.append(pixelBuffer, withPresentationTime: time) else {
                throw writer.error ?? SceneVideoBakeError.fallbackEncodingFailed("Failed to append video frame.")
            }
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        guard writer.status == .completed else {
            throw writer.error ?? SceneVideoBakeError.fallbackEncodingFailed("AVAssetWriter did not complete.")
        }
    }

    private static func loadCGImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func makePixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    private static func resolveSceneInput(from projectURL: URL) throws -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: projectURL.path, isDirectory: &isDirectory) else {
            throw SceneVideoBakeError.sceneNotFound
        }

        if !isDirectory.boolValue {
            return projectURL
        }

        if let pkgURL = try? fm.contentsOfDirectory(at: projectURL, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension.lowercased() == "pkg" }) {
            return pkgURL
        }

        if fm.fileExists(atPath: projectURL.appendingPathComponent("project.json").path) {
            return projectURL
        }

        let extractedURL = projectURL.appendingPathComponent("extracted")
        if fm.fileExists(atPath: extractedURL.appendingPathComponent("project.json").path) {
            return extractedURL
        }

        throw SceneVideoBakeError.sceneNotFound
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
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            existingPath
        ].filter { !$0.isEmpty }.joined(separator: ":")
        environment["RUST_LOG"] = environment["RUST_LOG"] ?? "info"
        return environment
    }

    private static func isUsableVideo(at url: URL) -> Bool {
        guard url.isFileURL,
              FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              size.int64Value > 10_000 else {
            return false
        }
        return true
    }

    private static func isUsableVideoAsync(at url: URL) async -> Bool {
        guard isUsableVideo(at: url) else { return false }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              duration.seconds.isFinite,
              duration.seconds > 0.5,
              let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return false
        }
        let size = (try? await track.load(.naturalSize)) ?? .zero
        return size.width > 0 && size.height > 0
    }
}
