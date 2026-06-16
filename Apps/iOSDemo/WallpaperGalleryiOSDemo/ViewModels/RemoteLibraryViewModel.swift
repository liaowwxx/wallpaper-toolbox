import Foundation
import Observation

@MainActor
@Observable
final class RemoteLibraryViewModel {
    var selectedTab: AppTab = .library
    var serverURLText: String
    var username = ""
    var password = ""
    var query = ""
    var selectedCollection: String?
    var manifest: RemoteLibraryManifest?
    var baseURL: URL?
    var isLoading = false
    var errorMessage: String?
    var statusMessage = "Sample library loaded"
    var latestJob: UnpackJob?
    var savingAssetID: String?

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        let savedServerURL = defaults.string(forKey: DefaultsKey.serverURL)
        serverURLText = Self.shouldPreferDefaultTailscale(over: savedServerURL)
            ? Self.defaultServerURL
            : savedServerURL ?? Self.defaultServerURL
        username = defaults.string(forKey: DefaultsKey.username) ?? ""
        password = defaults.string(forKey: DefaultsKey.password) ?? ""
    }

    var filteredItems: [RemoteWallpaperItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            let matchesCollection = selectedCollection == nil || item.collections.contains(selectedCollection!)
            let matchesQuery = normalizedQuery.isEmpty
                || item.title.lowercased().contains(normalizedQuery)
                || item.tags.contains { $0.lowercased().contains(normalizedQuery) }
            return matchesCollection && matchesQuery
        }
    }

    var items: [RemoteWallpaperItem] {
        manifest?.items ?? []
    }

    var allCollections: [String] {
        Array(Set(items.flatMap(\.collections))).sorted()
    }

    var canTriggerUnpack: Bool {
        manifest?.supportsUnpackJobs == true
    }

    func item(withID id: String) -> RemoteWallpaperItem? {
        items.first { $0.id == id }
    }

    func connect() async {
        let normalizedURLText = normalizeServerURLText(serverURLText)
        guard let url = URL(string: normalizedURLText),
              url.scheme != nil else {
            errorMessage = RemoteLibraryError.invalidServerURL.localizedDescription
            return
        }
        serverURLText = normalizedURLText

        await runLoadingTask {
            let client = RemoteLibraryClient(baseURL: url, username: username, password: password)
            let manifest = try await client.fetchManifest()
            try validate(manifest)
            self.manifest = manifest
            self.baseURL = url
            self.statusMessage = "\(manifest.items.count) wallpapers loaded from Windows library"
            self.selectedTab = .library
            self.saveConnectionSettings()
        }
    }

    func loadInitialLibrary() async {
        if defaults.string(forKey: DefaultsKey.serverURL) != nil {
            await connect()
            return
        }
        await loadSampleLibrary()
    }

    func loadSampleLibrary() async {
        await runLoadingTask {
            guard let url = Bundle.main.url(forResource: "library", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else {
                throw RemoteLibraryError.sampleMissing
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(RemoteLibraryManifest.self, from: data)
            try validate(manifest)
            self.manifest = manifest
            self.baseURL = URL(string: "http://localhost:8080")
            self.statusMessage = "Sample library loaded"
            self.errorMessage = nil
        }
    }

    func triggerUnpack(for item: RemoteWallpaperItem) async {
        guard canTriggerUnpack else {
            errorMessage = "This server does not advertise unpackJobs support."
            return
        }
        guard let manifest, let url = manifest.resolvedAPIBaseURL(relativeTo: baseURL) ?? baseURL else {
            errorMessage = RemoteLibraryError.invalidServerURL.localizedDescription
            return
        }

        await runLoadingTask {
            let client = RemoteLibraryClient(baseURL: url, username: username, password: password)
            let job = try await client.triggerUnpack(itemID: item.id)
            self.latestJob = job
            self.statusMessage = "Unpack job \(job.state)"
            if job.state == "failed" {
                self.errorMessage = job.message ?? "Remote unpack failed."
                return
            }
            if job.state == "done" {
                let manifest = try await client.fetchManifest()
                try validate(manifest)
                self.manifest = manifest
                self.statusMessage = "\(item.title) unpacked"
            }
        }
    }

    func saveToPhotos(_ asset: RemoteAsset) async {
        guard savingAssetID == nil else { return }
        savingAssetID = asset.id
        statusMessage = "Saving \(asset.name)"
        errorMessage = nil
        defer { savingAssetID = nil }

        do {
            try await PhotoAssetExporter.save(asset: asset, baseURL: baseURL)
            statusMessage = "\(asset.name) saved to Photos"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runLoadingTask(_ operation: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveConnectionSettings() {
        defaults.set(serverURLText.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.serverURL)
        defaults.set(username, forKey: DefaultsKey.username)
        defaults.set(password, forKey: DefaultsKey.password)
    }

    private func normalizeServerURLText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return trimmed
        }
        return "http://\(trimmed)"
    }

    private static let defaultServerURL = "http://100.100.223.106:8090"

    private static func shouldPreferDefaultTailscale(over savedURLText: String?) -> Bool {
        guard let savedURLText,
              let url = URL(string: savedURLText),
              let host = url.host,
              !isTailscaleIPv4(host),
              IPv4Address(host) != nil else {
            return false
        }
        return true
    }

    private static func isTailscaleIPv4(_ value: String) -> Bool {
        guard let address = IPv4Address(value) else { return false }
        return (0x6440_0000...0x647F_FFFF).contains(address.rawValue)
    }
}

private func validate(_ manifest: RemoteLibraryManifest) throws {
    guard manifest.schemaVersion == 1 else {
        throw RemoteLibraryError.unsupportedSchema(manifest.schemaVersion)
    }
}

private enum DefaultsKey {
    static let serverURL = "RemoteLibrary.serverURL"
    static let username = "RemoteLibrary.username"
    static let password = "RemoteLibrary.password"
}

private struct IPv4Address {
    let rawValue: UInt32

    init?(_ value: String) {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let octet = UInt8(String(part)) else { return nil }
            result = (result << 8) | UInt32(octet)
        }
        rawValue = result
    }
}
