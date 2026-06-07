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
    private let thumbSize = 256

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

        let tempThumbDir = root.appendingPathComponent("temp_thumb", isDirectory: true)
        try? fileManager.createDirectory(at: tempThumbDir, withIntermediateDirectories: true)

        var items: [WallpaperItem] = []

        for entry in contents {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            guard entry.lastPathComponent != "temp_thumb" else { continue }

            let projectJSON = metadataService.readProjectJSON(in: entry)
            let preview = findPreview(in: entry)
            let pkg = findPKG(in: entry)

            if preview != nil || pkg != nil {
                var item = WallpaperItem(directory: entry, project: projectJSON, preview: preview, pkg: pkg)
                if let previewPath = preview {
                    item.thumbnailPath = await generateThumb(for: previewPath, itemId: item.id, tempThumbDir: tempThumbDir)
                }
                items.append(item)
            }
        }

        return items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    private func scanFlat(root: URL) async -> [WallpaperItem] {
        let assetExts = Set(["jpg", "jpeg", "png", "gif", "bmp", "webp",
                              "mp4", "mov", "avi", "mkv", "webm", "m4v", "wmv", "flv"])
        let imageExts = Set(["jpg", "jpeg", "png", "gif", "bmp", "webp"])

        let flatMeta = metadataService.readFlatMeta(root: root)
        let tempThumbDir = root.appendingPathComponent("temp_thumb", isDirectory: true)
        try? fileManager.createDirectory(at: tempThumbDir, withIntermediateDirectories: true)

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
                guard assetExts.contains(ext) else { continue }
                fileURLs.append(fileURL)
            }
        }

        var items: [WallpaperItem] = []
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
            item.type = imageExts.contains(ext) ? "image" : "video"

            if let meta = flatMeta[filename] {
                item.contentRating = meta.contentrating ?? "Everyone"
                item.collections = meta.repkgcollection ?? []
                item.tags = meta.tags ?? []
            }

            item.thumbnailPath = await generateThumb(for: fileURL, itemId: itemId, tempThumbDir: tempThumbDir)
            items.append(item)
        }

        return items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    private func generateThumb(for source: URL, itemId: String, tempThumbDir: URL) async -> URL? {
        let thumbPath = tempThumbDir.appendingPathComponent("\(itemId.sanitizedForPath).jpg")
        if checkCache(source: source, thumb: thumbPath) { return thumbPath }
        let ext = source.pathExtension.lowercased()
        if ["mp4", "mov", "avi", "mkv", "webm", "m4v", "wmv", "flv"].contains(ext) {
            return await generateVideoThumb(source: source, output: thumbPath)
        } else {
            return await generateImageThumb(source: source, output: thumbPath)
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

    // MARK: - Square crop helper

    private func squareCropAndResize(_ cgImage: CGImage, targetSize: Int) -> CGImage? {
        let w = cgImage.width
        let h = cgImage.height
        let side = min(w, h)
        let x = (w - side) / 2
        let y = (h - side) / 2

        guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: side, height: side)) else {
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: targetSize, height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: targetSize * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))
        return ctx.makeImage()
    }

    // MARK: - Image thumbnail (CGImageSource thumbnail API, no full decode)

    private func generateImageThumb(source: URL, output: URL) async -> URL? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(thumbSize * 2, 512),
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary),
              let squared = squareCropAndResize(cgImage, targetSize: thumbSize) else {
            return nil
        }
        return saveJPEG(cgImage: squared, to: output)
    }

    // MARK: - Video thumbnails

    private func generateVideoThumb(source: URL, output: URL) async -> URL? {
        let ext = source.pathExtension.lowercased()
        if avSupportedExts.contains(ext) {
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

    private let avSupportedExts: Set<String> = ["mov", "mp4", "m4v", "avi", "3gp"]

    private func generateWithAVFoundation(source: URL, output: URL) async -> URL? {
        let asset = AVURLAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: thumbSize, height: thumbSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            guard let squared = squareCropAndResize(cgImage, targetSize: thumbSize) else { return nil }
            return saveJPEG(cgImage: squared, to: output)
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

            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
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
        let width = thumbSize
        let height = thumbSize
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
        return saveJPEG(cgImage: cgImage, to: output)
    }

    // MARK: - JPEG encoding (direct CGImage → JPEG, no NSImage/TIFF)

    private func saveJPEG(cgImage: CGImage, to url: URL) -> URL? {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.75]
        CGImageDestinationAddImage(dest, cgImage, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return url
    }
}

extension String {
    var sanitizedForPath: String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return components(separatedBy: invalid).joined(separator: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
