import Foundation

struct AssetFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let isVideo: Bool

    var formattedSize: String {
        if size < 1024 { return "\(size) B" }
        let kb = Double(size) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024.0)
    }

    var icon: String {
        isVideo ? "film" : "photo"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AssetFile, rhs: AssetFile) -> Bool {
        lhs.id == rhs.id
    }
}

struct AssetScanner {
    static let imageExts: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp",
        "tiff", "tif", "heic", "heif", "ico"
    ]
    static let videoExts: Set<String> = [
        "mp4", "mov", "avi", "mkv", "webm", "m4v",
        "wmv", "flv", "mpg", "mpeg"
    ]

    static func scan(_ directory: URL) -> [AssetFile] {
        var assets: [AssetFile] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return assets }

        while let url = enumerator.nextObject() as? URL {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDir else { continue }

            let ext = url.pathExtension.lowercased()
            let isVideo = videoExts.contains(ext)
            let isImage = imageExts.contains(ext)
            guard isVideo || isImage else { continue }

            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            assets.append(AssetFile(
                url: url,
                name: url.lastPathComponent,
                size: Int64(fileSize),
                isVideo: isVideo
            ))
        }

        return assets.sorted { $0.size > $1.size }
    }
}
