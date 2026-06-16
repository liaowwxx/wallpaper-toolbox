import AVKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct WallpaperDetailView: View {
    @Environment(RemoteLibraryViewModel.self) private var library
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let item: RemoteWallpaperItem

    private var currentItem: RemoteWallpaperItem {
        library.item(withID: item.id) ?? item
    }

    var body: some View {
        let item = currentItem
        let sortedAssets = sortedAssets(for: item)

        Group {
            if horizontalSizeClass == .regular {
                iPadDetailLayout(item: item, sortedAssets: sortedAssets)
            } else {
                compactDetailLayout(item: item, sortedAssets: sortedAssets)
            }
        }
        .navigationTitle(item.title)
        .iOSInlineNavigationTitle()
        .task(id: autoUnpackTaskID(for: item)) {
            guard shouldAutoUnpack(for: item) else { return }
            await library.triggerUnpack(for: item)
        }
        .statusOverlay()
    }

    private func compactDetailLayout(item: RemoteWallpaperItem, sortedAssets: [RemoteAsset]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                preview(for: item)
                DetailHeader(item: item)
                if shouldShowUnpackPanel(for: item) {
                    UnpackPanel(item: item)
                }
                AssetsSection(item: item, assets: sortedAssets, emptyMessage: emptyAssetMessage(for: item))
            }
            .padding(16)
        }
    }

    private func iPadDetailLayout(item: RemoteWallpaperItem, sortedAssets: [RemoteAsset]) -> some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        preview(for: item)
                        DetailHeader(item: item)
                        if shouldShowUnpackPanel(for: item) {
                            UnpackPanel(item: item)
                        }
                    }
                    .padding(18)
                }
                .frame(width: max(360, geometry.size.width * 0.52))

                Divider()

                ScrollView {
                    AssetsSection(item: item, assets: sortedAssets, emptyMessage: emptyAssetMessage(for: item))
                        .padding(18)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func preview(for item: RemoteWallpaperItem) -> some View {
        AssetPreview(
            asset: primaryAsset(for: item),
            thumbnailURL: item.thumbnailURL(relativeTo: library.baseURL),
            baseURL: library.baseURL,
            fallbackIcon: item.typeIcon
        )
    }

    private func primaryAsset(for item: RemoteWallpaperItem) -> RemoteAsset? {
        item.assets.first { $0.kind == .video } ?? item.assets.first { $0.kind == .image } ?? item.assets.first
    }

    private func sortedAssets(for item: RemoteWallpaperItem) -> [RemoteAsset] {
        item.assets.sorted { left, right in
            (left.size ?? -1) > (right.size ?? -1)
        }
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

private struct DetailHeader: View {
    let item: RemoteWallpaperItem

    var body: some View {
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
    }
}

private struct AssetsSection: View {
    let item: RemoteWallpaperItem
    let assets: [RemoteAsset]
    let emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assets")
                .font(.headline)

            if assets.isEmpty {
                ContentUnavailableView(
                    "No Assets Yet",
                    systemImage: item.type == .video ? "film" : "shippingbox",
                    description: Text(emptyMessage)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(assets) { asset in
                    AssetActionRow(asset: asset)
                }
            }
        }
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
                AssetThumbnail(asset: asset, baseURL: library.baseURL)
                    .frame(width: 76, height: 56)
                    .clipShape(.rect(cornerRadius: 7))

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

private struct AssetThumbnail: View {
    let asset: RemoteAsset
    let baseURL: URL?

    var body: some View {
        if let url = asset.resolvedURL(relativeTo: baseURL) {
            switch asset.kind {
            case .image:
                ThumbnailImage(url: url, fallbackIcon: asset.systemImage)
            case .video:
                VideoThumbnailImage(url: url, fallbackIcon: asset.systemImage)
            case .unknown:
                fallback
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: asset.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct VideoThumbnailImage: View {
    @Environment(RemoteLibraryViewModel.self) private var library

    let url: URL
    let fallbackIcon: String
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: fallbackIcon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: loadID) {
            await loadThumbnail()
        }
        .clipped()
    }

    private var loadID: String {
        "\(url.absoluteString)|\(library.authorizationHeader ?? "")"
    }

    @MainActor
    private func loadThumbnail() async {
        image = nil
        let authorizationHeader = library.authorizationHeader
        do {
            let cgImage = try await Task.detached {
                var options: [String: Any] = [:]
                if let authorizationHeader {
                    options["AVURLAssetHTTPHeaderFieldsKey"] = ["Authorization": authorizationHeader]
                }
                let asset = AVURLAsset(url: url, options: options.isEmpty ? nil : options)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                return try generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil)
            }.value
            #if os(iOS)
            image = Image(uiImage: UIImage(cgImage: cgImage))
            #endif
        } catch {
            image = nil
        }
    }
}
