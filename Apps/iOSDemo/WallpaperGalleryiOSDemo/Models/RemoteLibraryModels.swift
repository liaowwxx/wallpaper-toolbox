import Foundation

enum AppTab: Hashable {
    case library
    case collections
    case settings
}

struct RemoteLibraryManifest: Decodable, Equatable {
    let schemaVersion: Int
    let serverVersion: String
    let generatedAt: Date?
    let features: [String]
    let items: [RemoteWallpaperItem]

    var supportsUnpackJobs: Bool {
        features.contains("unpackJobs")
    }

    var supportsRangeStreaming: Bool {
        features.contains("rangeStreaming")
    }
}

struct RemoteWallpaperItem: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let type: WallpaperKind
    let thumbnail: String?
    let isUnpacked: Bool
    let tags: [String]
    let collections: [String]
    let assets: [RemoteAsset]

    var typeLabel: String {
        type.label
    }

    var typeIcon: String {
        type.icon
    }

    func thumbnailURL(relativeTo baseURL: URL?) -> URL? {
        URLResolver.resolve(thumbnail, relativeTo: baseURL)
    }
}

struct RemoteAsset: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let kind: AssetKind
    let url: String
    let size: Int64?

    var formattedSize: String {
        guard let size else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var systemImage: String {
        kind.icon
    }

    func resolvedURL(relativeTo baseURL: URL?) -> URL? {
        URLResolver.resolve(url, relativeTo: baseURL)
    }
}

enum WallpaperKind: String, Decodable, Hashable {
    case image
    case video
    case scene
    case web
    case application
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = WallpaperKind(rawValue: value.lowercased()) ?? .unknown
    }

    var label: String {
        switch self {
        case .image: return "Image"
        case .video: return "Video"
        case .scene: return "Scene"
        case .web: return "Web"
        case .application: return "App"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .scene: return "cube"
        case .web: return "globe"
        case .application: return "gearshape"
        case .unknown: return "questionmark"
        }
    }
}

enum AssetKind: String, Decodable, Hashable {
    case image
    case video
    case unknown

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = AssetKind(rawValue: value.lowercased()) ?? .unknown
    }

    var icon: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .unknown: return "doc"
        }
    }
}

struct UnpackJob: Decodable, Identifiable, Hashable {
    let id: String
    let itemID: String?
    let state: String
    let message: String?

    enum CodingKeys: String, CodingKey {
        case id = "jobId"
        case itemID = "itemId"
        case state
        case message
    }
}

enum URLResolver {
    static func resolve(_ value: String?, relativeTo baseURL: URL?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute
        }
        guard let baseURL else { return nil }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }
}
