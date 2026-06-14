import AppKit
import SwiftUI

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private final class CachedThumbnail {
        let image: NSImage
        let fingerprint: String?

        init(image: NSImage, fingerprint: String?) {
            self.image = image
            self.fingerprint = fingerprint
        }
    }

    private let cache = NSCache<NSURL, CachedThumbnail>()

    private init() {
        cache.countLimit = AppConstants.thumbnailCacheCountLimit
        cache.totalCostLimit = AppConstants.thumbnailCacheCostLimit
    }

    func image(for url: URL) -> NSImage? {
        guard let cached = cache.object(forKey: url as NSURL) else { return nil }
        let fingerprint = fileFingerprint(for: url)
        guard cached.fingerprint == fingerprint else {
            cache.removeObject(forKey: url as NSURL)
            return nil
        }
        return cached.image
    }

    func setImage(_ image: NSImage, for url: URL) {
        let cost = AppConstants.thumbnailSize * AppConstants.thumbnailSize * 4
        let cached = CachedThumbnail(image: image, fingerprint: fileFingerprint(for: url))
        cache.setObject(cached, forKey: url as NSURL, cost: cost)
    }

    private func fileFingerprint(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate else { return nil }
        let size = values.fileSize ?? 0
        return "\(modified.timeIntervalSince1970)-\(size)"
    }
}

struct ThumbnailView: View {
    let url: URL
    let version: String?
    let fallbackIcon: String
    @State private var image: NSImage?

    init(url: URL, version: String? = nil, fallbackIcon: String) {
        self.url = url
        self.version = version
        self.fallbackIcon = fallbackIcon
    }

    var body: some View {
        Group {
            if let nsImage = image {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: fallbackIcon)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: LoadIdentity(url: url, version: version), priority: .background) {
            await load()
        }
    }

    private struct LoadIdentity: Hashable {
        let url: URL
        let version: String?
    }

    private func load() async {
        if let cached = ThumbnailCache.shared.image(for: url) { image = cached; return }
        image = nil

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let squared = cgImage.squareCroppedAndResized(to: AppConstants.thumbnailSize) else { return }

        let thumb = NSImage(cgImage: squared, size: .zero)
        ThumbnailCache.shared.setImage(thumb, for: url)
        guard !Task.isCancelled else { return }
        image = thumb
    }

    static func preloadBatch(urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask(priority: .background) {
                    guard ThumbnailCache.shared.image(for: url) == nil else { return }
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 512,
                        kCGImageSourceCreateThumbnailWithTransform: true
                    ]
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                          let squared = cg.squareCroppedAndResized(to: AppConstants.thumbnailSize) else { return }
                    let thumb = NSImage(cgImage: squared, size: .zero)
                    ThumbnailCache.shared.setImage(thumb, for: url)
                }
            }
        }
    }

    // squareCrop → CGImage.squareCroppedAndResized(to:) in CGImage+Thumbnail.swift
}
