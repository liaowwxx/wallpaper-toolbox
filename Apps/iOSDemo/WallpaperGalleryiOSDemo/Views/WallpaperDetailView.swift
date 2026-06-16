import AVKit
import SwiftUI

struct WallpaperDetailView: View {
    @Environment(RemoteLibraryViewModel.self) private var library
    let item: RemoteWallpaperItem

    private var currentItem: RemoteWallpaperItem {
        library.item(withID: item.id) ?? item
    }

    var body: some View {
        let item = currentItem

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AssetPreview(
                    asset: primaryAsset(for: item),
                    thumbnailURL: item.thumbnailURL(relativeTo: library.baseURL),
                    baseURL: library.baseURL,
                    fallbackIcon: item.typeIcon
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                            .font(.title2.weight(.bold))
                        Spacer()
                        Label(item.typeLabel, systemImage: item.typeIcon)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.thinMaterial, in: .capsule)
                    }

                    if !item.tags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(item.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(.secondary.opacity(0.10), in: .capsule)
                            }
                        }
                    }
                }

                if shouldShowUnpackPanel(for: item) {
                    UnpackPanel(item: item)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Assets")
                        .font(.headline)

                    if item.assets.isEmpty {
                        ContentUnavailableView(
                            "No Assets Yet",
                            systemImage: item.type == .video ? "film" : "shippingbox",
                            description: Text(emptyAssetMessage(for: item))
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        ForEach(item.assets) { asset in
                            AssetActionRow(asset: asset)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(item.title)
        .iOSInlineNavigationTitle()
        .task(id: autoUnpackTaskID(for: item)) {
            guard shouldAutoUnpack(for: item) else { return }
            await library.triggerUnpack(for: item)
        }
        .statusOverlay()
    }

    private func primaryAsset(for item: RemoteWallpaperItem) -> RemoteAsset? {
        item.assets.first { $0.kind == .video } ?? item.assets.first { $0.kind == .image } ?? item.assets.first
    }

    private func shouldShowUnpackPanel(for item: RemoteWallpaperItem) -> Bool {
        item.type != .video && !item.isUnpacked
    }

    private func shouldAutoUnpack(for item: RemoteWallpaperItem) -> Bool {
        shouldShowUnpackPanel(for: item)
            && item.assets.isEmpty
            && library.canTriggerUnpack
            && !library.isLoading
    }

    private func autoUnpackTaskID(for item: RemoteWallpaperItem) -> String {
        "\(item.id)-\(item.isUnpacked)-\(item.assets.count)"
    }

    private func emptyAssetMessage(for item: RemoteWallpaperItem) -> String {
        if item.type == .video {
            return "The Windows server did not expose a direct video asset for this wallpaper."
        }
        if item.isUnpacked {
            return "The package was unpacked, but no image or video files were found."
        }
        return "The Windows server will unpack this package and refresh the list."
    }
}

private extension View {
    @ViewBuilder
    func iOSInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

private struct AssetPreview: View {
    @Environment(RemoteLibraryViewModel.self) private var library

    let asset: RemoteAsset?
    let thumbnailURL: URL?
    let baseURL: URL?
    let fallbackIcon: String

    var body: some View {
        ZStack {
            if let asset,
               asset.kind == .video,
               let url = asset.resolvedURL(relativeTo: baseURL) {
                AuthenticatedVideoPlayer(url: url, authorizationHeader: library.authorizationHeader)
            } else {
                ThumbnailImage(url: thumbnailURL ?? asset?.resolvedURL(relativeTo: baseURL), fallbackIcon: fallbackIcon)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(.secondary.opacity(0.10), in: .rect(cornerRadius: 8))
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct AuthenticatedVideoPlayer: View {
    let url: URL
    let authorizationHeader: String?
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
            }
        }
        .task(id: playerID) {
            player?.pause()
            player = makePlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private var playerID: String {
        "\(url.absoluteString)|\(authorizationHeader ?? "")"
    }

    private func makePlayer() -> AVPlayer {
        var options: [String: Any] = [:]
        if let authorizationHeader {
            options["AVURLAssetHTTPHeaderFieldsKey"] = ["Authorization": authorizationHeader]
        }
        let asset = AVURLAsset(url: url, options: options.isEmpty ? nil : options)
        return AVPlayer(playerItem: AVPlayerItem(asset: asset))
    }
}

private struct UnpackPanel: View {
    @Environment(RemoteLibraryViewModel.self) private var library
    let item: RemoteWallpaperItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("This wallpaper is not unpacked on the Windows server.", systemImage: "shippingbox")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task { await library.triggerUnpack(for: item) }
            } label: {
                Label("Trigger Remote Unpack", systemImage: "bolt.horizontal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!library.canTriggerUnpack || library.isLoading)
        }
        .padding(14)
        .background(.secondary.opacity(0.10), in: .rect(cornerRadius: 8))
    }
}

private struct AssetActionRow: View {
    @Environment(RemoteLibraryViewModel.self) private var library
    let asset: RemoteAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: asset.systemImage)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(asset.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack {
                if let url = asset.resolvedURL(relativeTo: library.baseURL) {
                    ShareLink(item: url) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    Task { await library.saveToPhotos(asset) }
                } label: {
                    if library.savingAssetID == asset.id {
                        ProgressView()
                    } else {
                        Label("Save", systemImage: "photo.badge.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(library.savingAssetID != nil)
            }
        }
        .padding(12)
        .background(.background, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}
