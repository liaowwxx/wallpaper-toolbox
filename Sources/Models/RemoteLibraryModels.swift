import Foundation

struct RemoteLibraryManifest: Decodable {
    let schemaVersion: Int
    let serverVersion: String
    let generatedAt: Date?
    let apiBaseURL: String?
    let features: [String]
    let items: [RemoteWallpaperRecord]

    func resolvedAPIBaseURL(relativeTo baseURL: URL?) -> URL? {
        RemoteURLResolver.resolveAPIBaseURL(apiBaseURL, relativeTo: baseURL)
    }
}

struct RemoteWallpaperRecord: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let type: String
    let relativeDir: String?
    let thumbnail: String?
    let sourceArchive: String?
    let isUnpacked: Bool
    let contentRating: String
    let tags: [String]
    let collections: [String]
    let assets: [RemoteAssetRecord]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case relativeDir
        case thumbnail
        case sourceArchive
        case isUnpacked
        case contentRating
        case tags
        case collections
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        type = (try container.decodeIfPresent(String.self, forKey: .type) ?? "unknown").lowercased()
        relativeDir = try container.decodeIfPresent(String.self, forKey: .relativeDir)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        sourceArchive = try container.decodeIfPresent(String.self, forKey: .sourceArchive)
        isUnpacked = try container.decodeIfPresent(Bool.self, forKey: .isUnpacked) ?? false
        contentRating = Self.normalizedRating(try container.decodeIfPresent(String.self, forKey: .contentRating))
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        collections = try container.decodeIfPresent([String].self, forKey: .collections) ?? []
        assets = try container.decodeIfPresent([RemoteAssetRecord].self, forKey: .assets) ?? []
    }

    func thumbnailURL(relativeTo baseURL: URL?) -> URL? {
        RemoteURLResolver.resolve(thumbnail, relativeTo: baseURL)
    }

    func sourceArchiveURL(relativeTo baseURL: URL?) -> URL? {
        RemoteURLResolver.resolve(sourceArchive, relativeTo: baseURL)
    }

    private static func normalizedRating(_ value: String?) -> String {
        switch (value ?? "Everyone").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mature":
            return "Mature"
        case "questionable":
            return "Questionable"
        default:
            return "Everyone"
        }
    }
}

struct RemoteAssetRecord: Decodable, Hashable {
    let id: String
    let name: String
    let kind: String
    let url: String
    let size: Int64?
}

enum RemoteLibraryError: LocalizedError {
    case invalidServerURL
    case unsupportedSchema(Int)
    case missingSourceArchive
    case invalidDownloadResponse
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid Windows library server URL."
        case .unsupportedSchema(let version):
            return "This app supports schemaVersion 1. Server returned \(version)."
        case .missingSourceArchive:
            return "The Windows server did not publish a source folder download for this wallpaper."
        case .invalidDownloadResponse:
            return "The download response was invalid."
        case .downloadFailed(let message):
            return message
        }
    }
}

enum RemoteURLResolver {
    static func resolveAPIBaseURL(_ value: String?, relativeTo baseURL: URL?) -> URL? {
        if let url = resolve(value, relativeTo: baseURL) {
            return url
        }
        return baseURL
    }

    static func resolve(_ value: String?, relativeTo baseURL: URL?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute
        }
        guard let baseURL else { return nil }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }
}
