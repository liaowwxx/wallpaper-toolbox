import Foundation

struct AssetFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let isVideo: Bool
    let isWeb: Bool

    var formattedSize: String {
        if size < 1024 { return "\(size) B" }
        let kb = Double(size) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024.0)
    }

    var icon: String {
        if isWeb { return "globe" }
        return isVideo ? "film" : "photo"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AssetFile, rhs: AssetFile) -> Bool {
        lhs.id == rhs.id
    }
}

struct AssetScanner {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp",
        "tiff", "tif", "heic", "heif", "ico"
    ]
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "avi", "mkv", "webm", "m4v",
        "wmv", "flv", "mpg", "mpeg"
    ]
    static let webExtensions: Set<String> = ["html", "htm"]

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
            let isVideo = videoExtensions.contains(ext)
            let isImage = imageExtensions.contains(ext)
            let isWeb = webExtensions.contains(ext)
            guard isVideo || isImage || isWeb else { continue }

            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            assets.append(AssetFile(
                url: url,
                name: url.lastPathComponent,
                size: Int64(fileSize),
                isVideo: isVideo,
                isWeb: isWeb
            ))
        }

        return assets.sorted {
            if $0.isWeb != $1.isWeb { return $0.isWeb }
            return $0.size > $1.size
        }
    }
}
