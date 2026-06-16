import Foundation

#if os(iOS)
import Photos
import UIKit
#endif

enum PhotoAssetExporter {
    static func save(asset: RemoteAsset, baseURL: URL?) async throws {
        guard let remoteURL = asset.resolvedURL(relativeTo: baseURL) else {
            throw RemoteLibraryError.missingAssetURL
        }

        #if os(iOS)
        let session = URLSession(configuration: .wallpaperDownload)
        defer { session.finishTasksAndInvalidate() }
        let (localURL, response) = try await session.download(from: remoteURL)
        try validate(response)

        try await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            .authorizedForSaving()

        switch asset.kind {
        case .image:
            guard let data = try? Data(contentsOf: localURL),
                  let image = UIImage(data: data) else {
                throw RemoteLibraryError.missingAssetURL
            }
            try await saveImage(image)
        case .video:
            try await saveVideo(localURL)
        case .unknown:
            throw RemoteLibraryError.missingAssetURL
        }
        #else
        throw RemoteLibraryError.photoSavingUnavailable
        #endif
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw RemoteLibraryError.httpStatus(http.statusCode)
        }
    }
}

private extension URLSessionConfiguration {
    static var wallpaperDownload: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = true
        return configuration
    }
}

#if os(iOS)
private extension PHAuthorizationStatus {
    func authorizedForSaving() throws {
        switch self {
        case .authorized, .limited:
            return
        case .denied, .restricted, .notDetermined:
            throw RemoteLibraryError.photoSavingUnavailable
        @unknown default:
            throw RemoteLibraryError.photoSavingUnavailable
        }
    }
}

private func saveImage(_ image: UIImage) async throws {
    try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAsset(from: image)
    }
}

private func saveVideo(_ url: URL) async throws {
    let tempURL = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appendingPathExtension(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
    try FileManager.default.copyItem(at: url, to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
    }
}
#endif
