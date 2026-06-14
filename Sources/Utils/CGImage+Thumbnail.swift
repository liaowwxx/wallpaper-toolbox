import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

extension CGImage {

    /// Center-crops the image to a square, then resizes it to the target dimension.
    /// Used by both thumbnail generation (WallpaperScanner) and lazy loading (ThumbnailView).
    func squareCroppedAndResized(to targetSize: Int) -> CGImage? {
        let w = width
        let h = height
        let side = min(w, h)
        let x = (w - side) / 2
        let y = (h - side) / 2

        guard let cropped = cropping(to: CGRect(x: x, y: y, width: side, height: side)) else {
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

    /// Writes the CGImage as a JPEG to the destination URL, returning the URL on success.
    /// Used by WallpaperScanner for thumbnail persistence.
    func writeJPEG(to url: URL, quality: CGFloat = 0.75) -> URL? {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, self, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return url
    }
}
