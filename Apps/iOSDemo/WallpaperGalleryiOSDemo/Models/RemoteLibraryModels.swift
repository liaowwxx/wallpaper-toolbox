import Foundation

enum AppTab: Hashable {
    case library
    case settings
}

struct RemoteLibraryManifest: Decodable, Equatable {
    let schemaVersion: Int
    let serverVersion: String
    let generatedAt: Date?
    let apiBaseURL: String?
    let features: [String]
    let items: [RemoteWallpaperItem]

    func resolvedAPIBaseURL(relativeTo baseURL: URL?) -> URL? {
        URLResolver.resolveAPIBaseURL(apiBaseURL, relativeTo: baseURL)
    }

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
    let contentRating: ContentRating
    let tags: [String]
    let collections: [String]
    let assets: [RemoteAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case thumbnail
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
        type = try container.decode(WallpaperKind.self, forKey: .type)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail)
        isUnpacked = try container.decode(Bool.self, forKey: .isUnpacked)
        contentRating = try container.decodeIfPresent(ContentRating.self, forKey: .contentRating) ?? .everyone
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        collections = try container.decodeIfPresent([String].self, forKey: .collections) ?? []
        assets = try container.decodeIfPresent([RemoteAsset].self, forKey: .assets) ?? []
    }

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

enum ContentRating: String, CaseIterable, Decodable, Hashable {
    case everyone
    case questionable
    case mature

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mature":
            self = .mature
        case "questionable":
            self = .questionable
        default:
            self = .everyone
        }
    }

    var label: String {
        switch self {
        case .everyone: return "Everyone"
        case .questionable: return "Questionable"
        case .mature: return "Mature"
        }
    }

    var icon: String {
        switch self {
        case .everyone: return "person.2"
        case .questionable: return "exclamationmark.triangle"
        case .mature: return "18.circle"
        }
    }

    var filterValue: String {
        switch self {
        case .everyone: return "Everyone"
        case .questionable: return "Questionable"
        case .mature: return "Mature"
        }
    }

    init?(filterValue: String) {
        switch filterValue {
        case "Everyone":
            self = .everyone
        case "Questionable":
            self = .questionable
        case "Mature":
            self = .mature
        default:
            return nil
        }
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
    case pkg
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
        case .pkg: return "Package"
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
        case .pkg: return "shippingbox"
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
    static func resolveAPIBaseURL(_ value: String?, relativeTo baseURL: URL?) -> URL? {
        if let url = resolve(value, relativeTo: baseURL) {
            return url
        }
        guard let baseURL,
              shouldUseStaticFilePaths(for: baseURL),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.port = 8090
        return components.url
    }

    static func resolve(_ value: String?, relativeTo baseURL: URL?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let absolute = URL(string: value), absolute.scheme != nil {
            return normalizeFileURL(rewriteServerURL(absolute, relativeTo: baseURL), relativeTo: baseURL)
        }
        guard let baseURL else { return nil }
        let normalizedValue = normalizeRelativePath(value, relativeTo: baseURL)
        return URL(string: normalizedValue, relativeTo: baseURL)?.absoluteURL
    }

    private static func rewriteServerURL(_ url: URL, relativeTo baseURL: URL?) -> URL {
        guard let baseURL,
              let host = url.host,
              let replacementHost = baseURL.host,
              shouldRewrite(host: host, port: url.port, toMatch: baseURL, replacementHost: replacementHost),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.host = replacementHost
        return components.url ?? url
    }

    private static func isLocalhost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1"
    }

    private static func shouldRewrite(host: String, port: Int?, toMatch baseURL: URL, replacementHost: String) -> Bool {
        guard host != replacementHost else { return false }
        if isLocalhost(host), !isLocalhost(replacementHost) {
            return true
        }
        return port == baseURL.port
    }

    private static func normalizeFileURL(_ url: URL, relativeTo baseURL: URL?) -> URL {
        guard let baseURL,
              shouldUseStaticFilePaths(for: baseURL),
              url.path.hasPrefix("/files/"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.path = String(url.path.dropFirst("/files".count))
        return components.url ?? url
    }

    private static func normalizeRelativePath(_ path: String, relativeTo baseURL: URL) -> String {
        guard shouldUseStaticFilePaths(for: baseURL), path.hasPrefix("/files/") else {
            return path
        }
        return String(path.dropFirst("/files".count))
    }

    private static func shouldUseStaticFilePaths(for baseURL: URL) -> Bool {
        baseURL.port == 8080
    }
}
