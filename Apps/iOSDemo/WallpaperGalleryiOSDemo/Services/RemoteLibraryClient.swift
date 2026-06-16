import Foundation

struct RemoteLibraryClient {
    var baseURL: URL
    var username: String
    var password: String

    func fetchManifest() async throws -> RemoteLibraryManifest {
        let url = baseURL.appending(path: "library.json")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try Self.decoder.decode(RemoteLibraryManifest.self, from: data)
    }

    func triggerUnpack(itemID: String) async throws -> UnpackJob {
        let url = baseURL.appending(path: "api/wallpapers/\(itemID)/unpack")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuth(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try Self.decoder.decode(UnpackJob.self, from: data)
    }

    private func applyAuth(to request: inout URLRequest) {
        guard let header = Self.authorizationHeader(username: username, password: password) else { return }
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
            throw RemoteLibraryError.httpStatus(http.statusCode)
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum RemoteLibraryError: LocalizedError {
    case invalidServerURL
    case unsupportedSchema(Int)
    case httpStatus(Int)
    case missingAssetURL
    case unsupportedPhotoVideoFormat(String)
    case photoSavingUnavailable
    case sampleMissing

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid Windows library server URL."
        case .unsupportedSchema(let version):
            return "This demo supports schemaVersion 1. Server returned \(version)."
        case .httpStatus(let status):
            return "Server returned HTTP \(status)."
        case .missingAssetURL:
            return "This asset does not have a valid URL."
        case .unsupportedPhotoVideoFormat(let format):
            return "Photos cannot save this video format (\(format)). Use Export instead."
        case .photoSavingUnavailable:
            return "Saving to Photos is only available on iPhone and iPad."
        case .sampleMissing:
            return "Bundled sample library.json could not be loaded."
        }
    }
}
