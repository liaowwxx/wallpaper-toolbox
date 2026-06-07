import Foundation

struct FlatMetaItem: Codable {
    var contentrating: String?
    var repkgcollection: [String]?
    var tags: [String]?
}

struct FlatMetaFile: Codable {
    var items: [String: FlatMetaItem]
}

final class MetadataService {
    static let shared = MetadataService()
    private init() {}

    // MARK: - Project JSON (subdir mode)

    func readProjectJSON(in directory: URL) -> ProjectJSON? {
        let jsonPath = directory.appendingPathComponent("project.json")
        guard FileManager.default.fileExists(atPath: jsonPath.path),
              let data = try? Data(contentsOf: jsonPath) else { return nil }
        return try? JSONDecoder().decode(ProjectJSON.self, from: data)
    }

    private func readProjectDict(in directory: URL) -> [String: Any] {
        let jsonPath = directory.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: jsonPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    @discardableResult
    private func writeProjectDict(_ dict: [String: Any], in directory: URL) -> Bool {
        let jsonPath = directory.appendingPathComponent("project.json")
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        do {
            try data.write(to: jsonPath, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Flat meta (_repkg_meta.json)

    func readFlatMeta(root: URL) -> [String: FlatMetaItem] {
        let metaPath = root.appendingPathComponent("_repkg_meta.json")
        guard FileManager.default.fileExists(atPath: metaPath.path),
              let data = try? Data(contentsOf: metaPath),
              let meta = try? JSONDecoder().decode(FlatMetaFile.self, from: data) else {
            return [:]
        }
        return meta.items
    }

    @discardableResult
    func writeFlatMeta(_ items: [String: FlatMetaItem], root: URL) -> Bool {
        let metaPath = root.appendingPathComponent("_repkg_meta.json")
        let meta = FlatMetaFile(items: items)
        guard let data = try? JSONEncoder().encode(meta) else { return false }
        do {
            try data.write(to: metaPath, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Save metadata

    func saveMetadata(for item: WallpaperItem, mode: ScanMode, flatRoot: URL?) {
        switch mode {
        case .subdir:
            var dict = readProjectDict(in: item.path)
            dict["contentrating"] = item.contentRating
            dict["repkgcollection"] = item.collections.isEmpty ? nil : item.collections
            dict["preview_tagger"] = item.tags.isEmpty ? nil : item.tags
            dict = dict.compactMapValues { $0 }
            writeProjectDict(dict, in: item.path)

        case .flat:
            guard let root = flatRoot else { return }
            var meta = readFlatMeta(root: root)
            let key = item.title
            let entry = FlatMetaItem(
                contentrating: item.contentRating,
                repkgcollection: item.collections.isEmpty ? nil : item.collections,
                tags: item.tags.isEmpty ? nil : item.tags
            )
            meta[key] = entry
            writeFlatMeta(meta, root: root)
        }
    }
}
