import Foundation

#if os(iOS)
import Photos
import UIKit
#endif

enum PhotoAssetExporter {
    static func save(asset: RemoteAsset, baseURL: URL?, authorizationHeader: String?) async throws {
        guard let remoteURL = asset.resolvedURL(relativeTo: baseURL) else {
            throw RemoteLibraryError.missingAssetURL
        }

        #if os(iOS)
        let session = URLSession(configuration: .wallpaperDownload)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: remoteURL)
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        let (localURL, response) = try await session.download(for: request)
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
            try await saveVideo(localURL, preferredExtension: preferredVideoExtension(for: asset, remoteURL: remoteURL))
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

    private static func preferredVideoExtension(for asset: RemoteAsset, remoteURL: URL) throws -> String {
        let assetExtension = URL(fileURLWithPath: asset.name).pathExtension
        let remoteExtension = remoteURL.pathExtension
        let preferredExtension = (assetExtension.isEmpty ? remoteExtension : assetExtension).lowercased()
        let photoCompatibleExtensions = ["mp4", "mov", "m4v"]
        guard photoCompatibleExtensions.contains(preferredExtension) else {
            throw RemoteLibraryError.unsupportedPhotoVideoFormat(preferredExtension.isEmpty ? "unknown" : preferredExtension)
        }
        return preferredExtension
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

private func saveVideo(_ url: URL, preferredExtension: String) async throws {
    let tempURL = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appendingPathExtension(preferredExtension)
    try FileManager.default.copyItem(at: url, to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(tempURL.path) else {
        throw RemoteLibraryError.unsupportedPhotoVideoFormat(preferredExtension)
    }

    try await PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
    }
}
#endif
