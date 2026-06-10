import AppKit
import SwiftUI

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 800
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func setImage(_ image: NSImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

struct ThumbnailView: View {
    let url: URL
    let fallbackIcon: String
    @State private var image: NSImage?

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
        .task(id: url, priority: .background) { await load() }
    }

    private func load() async {
        if let cached = ThumbnailCache.shared.image(for: url) { image = cached; return }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let squared = Self.squareCrop(cgImage, size: 256) else { return }

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
                          let squared = squareCrop(cg, size: 256) else { return }
                    let thumb = NSImage(cgImage: squared, size: .zero)
                    ThumbnailCache.shared.setImage(thumb, for: url)
                }
            }
        }
    }

    private nonisolated static func squareCrop(_ cgImage: CGImage, size: Int) -> CGImage? {
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
            width: size, height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()
    }
}
