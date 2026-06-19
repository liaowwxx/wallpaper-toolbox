import SwiftUI
import AVKit

// MARK: - Per-video player state

@MainActor
@Observable
final class VideoPlayerState {
    let player: AVPlayer
    var currentTime: Double = 0
    var duration: Double = 0
    var isReady = false

    @ObservationIgnored private var timeObserver: Any?

    init(url: URL) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let sec = CMTimeGetSeconds(time)
            MainActor.assumeIsolated {
                self.currentTime = sec
                if !self.isReady { self.isReady = true }
                if self.duration <= 0, let item = self.player.currentItem,
                   item.status == .readyToPlay {
                    let d = CMTimeGetSeconds(item.duration)
                    if d.isFinite, d > 0 { self.duration = d }
                }
            }
        }

        player.play()
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    func pause() { player.pause() }
    func resume() { player.play() }

    deinit {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        player.pause()
    }
}

// MARK: - Asset Picker Sheet

struct AssetPickerSheet: View {
    let item: WallpaperItem
    let assets: [AssetFile]
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @State private var hoveredAsset: AssetFile.ID?
    @State private var expandedVideo: AssetFile.ID?
    @State private var playerState = VideoPlayerStateHolder()

    private let videoSize = CGSize(width: 260, height: 146)
    private var isSceneItem: Bool {
        item.type.lowercased() == "scene"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Wallpaper Asset")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            if isSceneItem {
                directSceneOption
                Divider()
            }

            if assets.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No media files found")
                        .foregroundStyle(.secondary)
                    Text("Extract the wallpaper first to find video/image files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(assets) { asset in
                            if asset.isVideo {
                                videoAssetSection(asset)
                            } else {
                                imageAssetRow(asset)
                            }
                            Divider()
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text("\(assets.count) files found")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
        }
        .frame(minWidth: 540, idealWidth: 620, minHeight: 400, idealHeight: 550)
        .onDisappear {
            playerState.clear()
        }
    }

    private var directSceneOption: some View {
        Button {
            viewModel.finishSceneDirectSelection(item)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cube.transparent")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 46, height: 46)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Render Scene Directly")
                        .font(.body.weight(.semibold))
                    Text("Use wallpaper-wgpu to render this scene as a live wallpaper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Render scene directly")
        .accessibilityHint("Set this scene wallpaper through the realtime renderer")
    }

    // MARK: - Image Asset

    private func imageAssetRow(_ asset: AssetFile) -> some View {
        Button {
            viewModel.finishWallpaperSelection(asset)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: asset.url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.blue.opacity(0.12))
                            Image(systemName: "photo").foregroundStyle(.blue)
                        }
                    }
                }
                .frame(width: 96, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                assetInfo(asset)

                Spacer()

                if hoveredAsset == asset.id {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2).foregroundStyle(.tint)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hoveredAsset == asset.id ? Color.accentColor.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(asset.name), \(asset.isVideo ? "Video" : "Image"), \(asset.formattedSize)")
        .accessibilityHint("Double-tap to set as wallpaper")
        .animation(.easeInOut(duration: 0.15), value: hoveredAsset)
        .onHover { hovering in
            hoveredAsset = hovering ? asset.id : nil
        }
    }

    // MARK: - Video Asset

    private func videoAssetSection(_ asset: AssetFile) -> some View {
        let isExpanded = expandedVideo == asset.id

        return VStack(spacing: 0) {
            Button {
                if isExpanded {
                    expandedVideo = nil
                    playerState.clear()
                } else {
                    expandedVideo = asset.id
                    playerState.load(url: asset.url)
                }
            } label: {
                HStack(spacing: 12) {
                    videoThumbnail(asset, size: CGSize(width: 96, height: 64))

                    assetInfo(asset)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "play.circle.fill")
                        .font(.title2).foregroundStyle(.tint)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, let state = playerState.state {
                videoPlayerPanel(asset, state: state)
            }
        }
    }

    private func videoThumbnail(_ asset: AssetFile, size: CGSize) -> some View {
        Group {
            if expandedVideo == asset.id, let state = playerState.state, state.isReady {
                PlayerPreview(player: state.player)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.purple.opacity(0.12))
                        .frame(width: size.width, height: size.height)
                    if expandedVideo == asset.id {
                        ProgressView().scaleEffect(0.5)
                    } else {
                        Image(systemName: "play.rectangle")
                            .font(.title).foregroundStyle(.purple)
                    }
                }
            }
        }
    }

    private func videoPlayerPanel(_ asset: AssetFile, state: VideoPlayerState) -> some View {
        VideoPlayerPanelView(
            state: state,
            asset: asset,
            videoSize: videoSize,
            onSetWallpaper: { viewModel.finishWallpaperSelection(asset); dismiss() },
            onSetFrame: { time in
                Task {
                    if let frameURL = await WallpaperService.captureFrame(videoURL: asset.url, at: time) {
                        viewModel.applyStaticWallpaper(frameURL, assetName: asset.name)
                    }
                }
            }
        )
    }

    // MARK: - Shared

    private func assetInfo(_ asset: AssetFile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(asset.name)
                .font(.body).fontWeight(.medium)
                .lineLimit(1).truncationMode(.middle)
            HStack(spacing: 8) {
                Label(asset.formattedSize, systemImage: "arrow.down.doc")
                    .font(.caption).foregroundStyle(.secondary)
                Label(asset.isVideo ? "Video" : "Image", systemImage: asset.icon)
                    .font(.caption)
                    .foregroundStyle(asset.isVideo ? .purple : .blue)
            }
        }
    }

}

// MARK: - Player State Holder (triggers SwiftUI updates)

@MainActor
@Observable
final class VideoPlayerStateHolder {
    var state: VideoPlayerState?

    func load(url: URL) {
        state?.player.pause()
        state = VideoPlayerState(url: url)
    }

    func clear() {
        state?.player.pause()
        state = nil
    }
}

// MARK: - Video Player Panel (extracted subview for efficient diffing)

private struct VideoPlayerPanelView: View {
    @Bindable var state: VideoPlayerState
    let asset: AssetFile
    let videoSize: CGSize
    let onSetWallpaper: () -> Void
    let onSetFrame: (CMTime) -> Void

    var body: some View {
        VStack(spacing: 10) {
            PlayerPreview(player: state.player)
                .frame(width: videoSize.width, height: videoSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if state.duration > 0 {
                Slider(value: $state.currentTime, in: 0...state.duration) { editing in
                    if editing {
                        state.pause()
                    } else {
                        state.resume()
                    }
                }
                .padding(.horizontal, 4)

                HStack {
                    Text(formatTime(state.currentTime))
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTime(state.duration))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            } else {
                ProgressView("Loading...").scaleEffect(0.7)
            }

            HStack(spacing: 16) {
                Button(action: onSetWallpaper) {
                    Label("Set as Wallpaper", systemImage: "display").font(.caption)
                }

                Button {
                    onSetFrame(CMTime(seconds: state.currentTime, preferredTimescale: 600))
                } label: {
                    Label("Set Frame", systemImage: "camera.viewfinder").font(.caption)
                }
                .disabled(state.duration <= 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - AVPlayerView Preview (macOS native, no manual layer management)

private struct PlayerPreview: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
