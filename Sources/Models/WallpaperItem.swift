import Foundation

struct ProjectJSON: Codable {
    let title: String?
    let type: String?
    let contentrating: String?
    let description: String?
    let repkgcollection: [String]?
    let preview_tagger: [String]?
}

struct WallpaperItem: Identifiable, Hashable {
    var id: String
    var title: String
    var type: String
    var path: URL
    var pkgPath: URL?
    var previewPath: URL?
    var thumbnailPath: URL?
    var thumbnailVersion: String?
    var metadataKey: String
    var contentRating: String
    var collections: [String]
    var tags: [String]
    var isExtracted: Bool

    init(directory: URL, project: ProjectJSON?, preview: URL?, pkg: URL?) {
        self.id = directory.lastPathComponent
        self.title = project?.title ?? directory.lastPathComponent
        self.type = project?.type ?? "unknown"
        self.path = directory
        self.pkgPath = pkg
        self.previewPath = preview
        self.contentRating = project?.contentrating ?? "Everyone"
        self.metadataKey = directory.lastPathComponent
        self.collections = project?.repkgcollection ?? []
        self.tags = project?.preview_tagger ?? []
        self.isExtracted = WallpaperItem.checkExtracted(directory)
    }

    private static func checkExtracted(_ dir: URL) -> Bool {
        let extractedDir = dir.appendingPathComponent("extracted")
        let sceneFile = extractedDir.appendingPathComponent("scene.json")
        let materialsDir = extractedDir.appendingPathComponent("materials")
        return FileManager.default.fileExists(atPath: sceneFile.path)
            || FileManager.default.fileExists(atPath: materialsDir.path)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: WallpaperItem, rhs: WallpaperItem) -> Bool {
        lhs.id == rhs.id
    }

    var typeLabel: String {
        switch type {
        case "video": return "Video"
        case "image": return "Image"
        case "scene": return "Scene"
        case "web": return "Web"
        case "application": return "App"
        default: return "Unknown"
        }
    }

    var typeIcon: String {
        switch type {
        case "video": return "film"
        case "image": return "photo"
        case "scene": return "cube"
        case "web": return "globe"
        case "application": return "gearshape"
        default: return "questionmark"
        }
    }
}
