import Foundation

struct RemoteLibraryClient {
    var baseURL: URL
    var username: String
    var password: String

    var authorizationHeader: String? {
        Self.authorizationHeader(username: username, password: password)
    }

    func fetchManifest() async throws -> RemoteLibraryManifest {
        let url = baseURL.appending(path: "library.json")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuth(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let manifest = try Self.decoder.decode(RemoteLibraryManifest.self, from: data)
        guard manifest.schemaVersion == 1 else {
            throw RemoteLibraryError.unsupportedSchema(manifest.schemaVersion)
        }
        return manifest
    }

    func checkHealth(timeout: TimeInterval = 3) async throws {
        let url = baseURL.appending(path: "library.json")
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuth(to: &request)

        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    func downloadArchive(
        from url: URL,
        progress: @escaping @MainActor (RemoteDownloadUpdate) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(to: &request)
        return try await RemoteArchiveDownloader().download(request: request, progress: progress)
    }

    private func applyAuth(to request: inout URLRequest) {
        guard let header = authorizationHeader else { return }
        request.setValue(header, forHTTPHeaderField: "Authorization")
    }

    static func authorizationHeader(username: String, password: String) -> String? {
        guard !username.isEmpty || !password.isEmpty else { return nil }
        let token = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() ?? ""
        return "Basic \(token)"
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw RemoteLibraryError.downloadFailed("Server returned HTTP \(http.statusCode).")
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct RemoteDownloadUpdate: Equatable {
    var progress: Double
    var bytesPerSecond: Double?
}

private final class RemoteArchiveDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var downloadedURL: URL?
    private var progressHandler: (@MainActor (RemoteDownloadUpdate) -> Void)?
    private var lastSampleTime: Date?
    private var lastSampleBytes: Int64 = 0

    func download(
        request: URLRequest,
        progress: @escaping @MainActor (RemoteDownloadUpdate) -> Void
    ) async throws -> URL {
        progressHandler = progress
        lastSampleTime = Date()
        lastSampleBytes = 0
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        let now = Date()
        var speed: Double?
        if let lastSampleTime {
            let elapsed = now.timeIntervalSince(lastSampleTime)
            if elapsed >= 0.5 {
                let bytesDelta = max(0, totalBytesWritten - lastSampleBytes)
                speed = Double(bytesDelta) / elapsed
                self.lastSampleTime = now
                lastSampleBytes = totalBytesWritten
            }
        } else {
            lastSampleTime = now
            lastSampleBytes = totalBytesWritten
        }
        Task { @MainActor in
            self.progressHandler?(RemoteDownloadUpdate(progress: value, bytesPerSecond: speed))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallpaper-remote-\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            downloadedURL = destination
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
            cleanup()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            continuation?.resume(throwing: error)
        } else if let downloadedURL {
            continuation?.resume(returning: downloadedURL)
        } else {
            continuation?.resume(throwing: RemoteLibraryError.invalidDownloadResponse)
        }
        continuation = nil
        cleanup()
    }

    private func cleanup() {
        session?.invalidateAndCancel()
        session = nil
        progressHandler = nil
        lastSampleTime = nil
        lastSampleBytes = 0
    }
}
