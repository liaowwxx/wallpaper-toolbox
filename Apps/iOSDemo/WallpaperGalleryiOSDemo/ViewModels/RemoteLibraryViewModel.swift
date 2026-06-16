import Foundation
import Observation

@MainActor
@Observable
final class RemoteLibraryViewModel {
    var selectedTab: AppTab = .library
    var serverURLText = "http://localhost:8090"
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
        guard let url = URL(string: serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil else {
            errorMessage = RemoteLibraryError.invalidServerURL.localizedDescription
            return
        }

        await runLoadingTask {
            let client = RemoteLibraryClient(baseURL: url, username: username, password: password)
            let manifest = try await client.fetchManifest()
            try validate(manifest)
            self.manifest = manifest
            self.baseURL = url
            self.statusMessage = "\(manifest.items.count) wallpapers loaded from Windows library"
            self.selectedTab = .library
        }
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
        savingAssetID = asset.id
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
}

private func validate(_ manifest: RemoteLibraryManifest) throws {
    guard manifest.schemaVersion == 1 else {
        throw RemoteLibraryError.unsupportedSchema(manifest.schemaVersion)
    }
}
