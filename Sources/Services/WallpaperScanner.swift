import Foundation
import AppKit
import AVFoundation

enum ScanMode: String, CaseIterable {
    case subdir = "subdir"
    case flat = "flat"

    var label: String {
        switch self {
        case .subdir: return "Subdirectories"
        case .flat: return "Flat files"
        }
    }
}

final class WallpaperScanner {
    private let fileManager = FileManager.default
    private let metadataService = MetadataService.shared
    private let thumbnailSize = AppConstants.thumbnailSize
    private let thumbnailGenerationLimit = 4

    func scan(directory: URL, mode: ScanMode) async -> [WallpaperItem] {
        switch mode {
        case .subdir:
            return await scanSubdirectories(root: directory)
        case .flat:
            return await scanFlat(root: directory)
        }
    }

    private func scanSubdirectories(root: URL) async -> [WallpaperItem] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let tempThumbDirectory = root.appendingPathComponent("temp_thumb", isDirectory: true)
        try? fileManager.createDirectory(at: tempThumbDirectory, withIntermediateDirectories: true)

        var items: [WallpaperItem] = []
        var thumbnailSources: [Int: URL] = [:]

        for entry in contents {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            guard entry.lastPathComponent != "temp_thumb" else { continue }

            let projectJSON = metadataService.readProjectJSON(in: entry)
            let preview = findPreview(in: entry)
            let pkg = findPKG(in: entry)

            if preview != nil || pkg != nil {
                let item = WallpaperItem(directory: entry, project: projectJSON, preview: preview, pkg: pkg)
                if let previewPath = preview {
                    thumbnailSources[items.count] = previewPath
                }
                items.append(item)
            }
        }

        await generateThumbnails(for: &items, sources: thumbnailSources, tempThumbDirectory: tempThumbDirectory)
        removeStaleThumbnails(in: tempThumbDirectory, keeping: Set(items.map(\.id)))

        return items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    private func scanFlat(root: URL) async -> [WallpaperItem] {
        let assetExtensions = Set(["jpg", "jpeg", "png", "gif", "bmp", "webp",
                              "mp4", "mov", "avi", "mkv", "webm", "m4v", "wmv", "flv"])
        let imageExtensions = Set(["jpg", "jpeg", "png", "gif", "bmp", "webp"])

        let flatMeta = metadataService.readFlatMeta(root: root)
        let tempThumbDirectory = root.appendingPathComponent("temp_thumb", isDirectory: true)
        try? fileManager.createDirectory(at: tempThumbDirectory, withIntermediateDirectories: true)

        var fileURLs: [URL] = []
        if let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            while let fileURL = enumerator.nextObject() as? URL {
                let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard !isDir else {
                    if fileURL.lastPathComponent == "temp_thumb" {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                let ext = fileURL.pathExtension.lowercased()
                guard assetExtensions.contains(ext) else { continue }
                fileURLs.append(fileURL)
            }
        }

        var items: [WallpaperItem] = []
        var thumbnailSources: [Int: URL] = [:]
        for fileURL in fileURLs {
            let ext = fileURL.pathExtension.lowercased()
            let parentDir = fileURL.deletingLastPathComponent()
            let filename = fileURL.lastPathComponent
            let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            let relativePath = fileURL.path.hasPrefix(rootPrefix)
                ? String(fileURL.path.dropFirst(rootPrefix.count))
                : filename
            let itemId = relativePath.sanitizedForPath

            var item = WallpaperItem(
                directory: parentDir,
                project: nil,
                preview: fileURL,
                pkg: nil
            )
            item.id = itemId
            item.title = filename
            item.type = imageExtensions.contains(ext) ? "image" : "video"
            item.metadataKey = relativePath

            if let meta = flatMeta[relativePath] ?? flatMeta[filename] {
                item.contentRating = meta.contentrating ?? "Everyone"
                item.collections = meta.repkgcollection ?? []
                item.tags = meta.tags ?? []
            }

            thumbnailSources[items.count] = fileURL
            items.append(item)
        }

        await generateThumbnails(for: &items, sources: thumbnailSources, tempThumbDirectory: tempThumbDirectory)
        removeStaleThumbnails(in: tempThumbDirectory, keeping: Set(items.map(\.id)))

        return items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    private struct ThumbnailJob {
        let index: Int
        let source: URL
        let itemId: String
    }

    private func generateThumbnails(
        for items: inout [WallpaperItem],
        sources: [Int: URL],
        tempThumbDirectory: URL
    ) async {
        let jobs = sources.compactMap { index, source -> ThumbnailJob? in
            guard items.indices.contains(index) else { return nil }
            return ThumbnailJob(index: index, source: source, itemId: items[index].id)
        }
        guard !jobs.isEmpty else { return }

        await withTaskGroup(of: (Int, URL?, String?).self) { group in
            var nextJob = 0

            func enqueueNextJob() {
                guard nextJob < jobs.count else { return }
                let job = jobs[nextJob]
                nextJob += 1
                group.addTask {
                    let thumbnail = await self.generateThumbnail(
                        for: job.source,
                        itemId: job.itemId,
                        tempThumbDirectory: tempThumbDirectory
                    )
                    return (job.index, thumbnail, self.fileFingerprint(for: job.source))
                }
            }

            for _ in 0..<min(thumbnailGenerationLimit, jobs.count) {
                enqueueNextJob()
            }

            while let result = await group.next() {
                let (index, thumbnailPath, version) = result
                if items.indices.contains(index) {
                    items[index].thumbnailPath = thumbnailPath
                    items[index].thumbnailVersion = version
                }
                enqueueNextJob()
            }
        }
    }

    private func generateThumbnail(for source: URL, itemId: String, tempThumbDirectory: URL) async -> URL? {
        let thumbPath = tempThumbDirectory.appendingPathComponent("\(itemId.sanitizedForPath).jpg")
        if checkCache(source: source, thumb: thumbPath) { return thumbPath }
        let ext = source.pathExtension.lowercased()
        if ["mp4", "mov", "avi", "mkv", "webm", "m4v", "wmv", "flv"].contains(ext) {
            return await generateVideoThumbnail(source: source, output: thumbPath)
        } else {
            return await generateImageThumbnail(source: source, output: thumbPath)
        }
    }

    private func findPreview(in directory: URL) -> URL? {
        for name in ["preview.jpg", "preview.png", "preview.gif", "preview.webp"] {
            let url = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func findPKG(in directory: URL) -> URL? {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        return contents.first { $0.pathExtension.lowercased() == "pkg" }
    }

    private func checkCache(source: URL, thumb: URL) -> Bool {
        guard fileManager.fileExists(atPath: thumb.path),
              let srcAttrs = try? fileManager.attributesOfItem(atPath: source.path),
              let thumbAttrs = try? fileManager.attributesOfItem(atPath: thumb.path),
              let srcDate = srcAttrs[.modificationDate] as? Date,
              let thumbDate = thumbAttrs[.modificationDate] as? Date else { return false }
        return thumbDate > srcDate
    }

    private func fileFingerprint(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate else { return nil }
        let size = values.fileSize ?? 0
        return "\(modified.timeIntervalSince1970)-\(size)"
    }

    private func removeStaleThumbnails(in directory: URL, keeping itemIDs: Set<String>) {
        let expectedFilenames = Set(itemIDs.map { "\($0.sanitizedForPath).jpg" })
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in contents where file.pathExtension.lowercased() == "jpg" {
            if !expectedFilenames.contains(file.lastPathComponent) {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    // MARK: - Square crop helper

    // Moved to CGImage+Thumbnail.swift as `squareCroppedAndResized(to:)`.

    // MARK: - Image thumbnail (CGImageSource thumbnail API, no full decode)

    private func generateImageThumbnail(source: URL, output: URL) async -> URL? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(AppConstants.thumbnailSize * 2, 512),
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary),
              let squared = cgImage.squareCroppedAndResized(to: thumbnailSize) else {
            return nil
        }
        return squared.writeJPEG(to: output)
    }

    // MARK: - Video thumbnails

    private func generateVideoThumbnail(source: URL, output: URL) async -> URL? {
        let ext = source.pathExtension.lowercased()
        if avSupportedExtensions.contains(ext) {
            if let result = await generateWithAVFoundation(source: source, output: output) {
                return result
            }
        }
        return await generateWithFFmpeg(source: source, output: output)
    }

    private func findFFmpeg() -> URL? {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for p in paths {
            let url = URL(fileURLWithPath: p)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private let avSupportedExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "3gp"]

    private func generateWithAVFoundation(source: URL, output: URL) async -> URL? {
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbnailSize, height: thumbnailSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            guard let squared = cgImage.squareCroppedAndResized(to: thumbnailSize) else { return nil }
            return squared.writeJPEG(to: output)
        } catch {
            return nil
        }
    }

    private final class OnceFlag: @unchecked Sendable {
        var value = false
    }

    private func generateWithFFmpeg(source: URL, output: URL) async -> URL? {
        guard let ffmpeg = findFFmpeg() else { return placeholderThumb(output: output) }

        return await withCheckedContinuation { continuation in
            let resumed = OnceFlag()
            let lock = NSLock()

            let process = Process()
            process.executableURL = ffmpeg
            process.arguments = [
                "-y", "-an", "-i", source.path,
                "-vframes", "1",
                "-s", "256x256",
                "-f", "image2pipe",
                "-vcodec", "mjpeg",
                "-"
            ]

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { proc in
                lock.lock()
                guard !resumed.value else { lock.unlock(); return }
                resumed.value = true
                lock.unlock()

                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus == 0, !data.isEmpty {
                    try? data.write(to: output)
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(returning: self.placeholderThumb(output: output))
                }
            }

            do {
                try process.run()
            } catch {
                lock.lock()
                guard !resumed.value else { lock.unlock(); return }
                resumed.value = true
                lock.unlock()
                continuation.resume(returning: placeholderThumb(output: output))
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + AppConstants.ffmpegTimeoutSeconds) {
                lock.lock()
                guard !resumed.value else { lock.unlock(); return }
                lock.unlock()
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    // MARK: - Placeholder

    private func placeholderThumb(output: URL) -> URL? {
        let width = thumbnailSize
        let height = thumbnailSize
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let cx = width / 2
        let cy = height / 2
        let r = width / 4
        for y in 0..<height {
            for x in 0..<width {
                let dx = x - cx
                let dy = y - cy
                if dx * dx + dy * dy <= r * r {
                    let i = (y * width + x) * 4
                    pixels[i] = 80
                    pixels[i + 1] = 80
                    pixels[i + 2] = 80
                    pixels[i + 3] = 255
                }
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = ctx.makeImage() else { return nil }
        return cgImage.writeJPEG(to: output)
    }

    // MARK: - JPEG encoding (moved to CGImage+Thumbnail.swift)
}

extension String {
    var sanitizedForPath: String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return components(separatedBy: invalid).joined(separator: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
