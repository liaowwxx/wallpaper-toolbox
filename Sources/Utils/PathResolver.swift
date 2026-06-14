import Foundation

/// Resolves a string path to an absolute file URL.
///
/// If the path is already absolute (starts with "/"), it is returned directly.
/// Otherwise the path is resolved relative to the current working directory.
enum PathResolver {
    static func resolve(_ path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        if url.isFileURL && path.hasPrefix("/") { return url.standardizedFileURL }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return URL(fileURLWithPath: path, relativeTo: cwd).standardizedFileURL
    }
}
