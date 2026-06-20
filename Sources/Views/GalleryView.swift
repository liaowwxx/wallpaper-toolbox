import SwiftUI

struct GalleryView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(SettingsStore.self) private var settings

    private let columnSpacing: CGFloat = 10
    private let cardMinWidth: CGFloat = 160

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cardMinWidth, maximum: 240), spacing: columnSpacing)]
    }

    var body: some View {
        let remoteAuthorizationHeader = viewModel.remoteAuthorizationHeader

        ScrollView {
            LazyVGrid(columns: columns, spacing: columnSpacing) {
                ForEach(viewModel.filteredWallpapers) { item in
                    let isDownloaded = viewModel.isRemoteWallpaperDownloaded(item)
                    WallpaperCard(
                        item: item,
                        isSelected: viewModel.selectedIDs.contains(item.id),
                        isDownloaded: isDownloaded,
                        appLanguage: settings.appLanguage,
                        remoteAuthorizationHeader: remoteAuthorizationHeader,
                        onTap: { viewModel.toggleSelection(item.id) }
                    )
                    .equatable()
                    .id("\(item.id)-\(isDownloaded)")
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(12)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: viewModel.filterGeneration)
        }
    }
}

// MARK: - POD Wrapper (fast memcmp diffing)

struct WallpaperCard: View, Equatable {
    let item: WallpaperItem
    let isSelected: Bool
    let isDownloaded: Bool
    let appLanguage: AppLanguage
    let remoteAuthorizationHeader: String?
    let onTap: () -> Void

    static func == (lhs: WallpaperCard, rhs: WallpaperCard) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.item.title == rhs.item.title
            && lhs.item.type == rhs.item.type
            && lhs.item.pkgPath == rhs.item.pkgPath
            && lhs.item.previewPath == rhs.item.previewPath
            && lhs.item.thumbnailPath == rhs.item.thumbnailPath
            && lhs.item.thumbnailVersion == rhs.item.thumbnailVersion
            && lhs.item.contentRating == rhs.item.contentRating
            && lhs.item.collections == rhs.item.collections
            && lhs.item.tags == rhs.item.tags
            && lhs.item.isExtracted == rhs.item.isExtracted
            && lhs.item.isRemote == rhs.item.isRemote
            && lhs.item.isDownloaded == rhs.item.isDownloaded
            && lhs.item.remoteThumbnailURL == rhs.item.remoteThumbnailURL
            && lhs.isSelected == rhs.isSelected
            && lhs.isDownloaded == rhs.isDownloaded
            && lhs.appLanguage == rhs.appLanguage
            && lhs.remoteAuthorizationHeader == rhs.remoteAuthorizationHeader
    }

    var body: some View {
        WallpaperCardInternal(
            item: item,
            isSelected: isSelected,
            isDownloaded: isDownloaded,
            appLanguage: appLanguage,
            remoteAuthorizationHeader: remoteAuthorizationHeader,
            onTap: onTap
        )
    }
}

// MARK: - Internal (stateful, only diffed when POD inputs change)

private struct WallpaperCardInternal: View {
    @Environment(AppViewModel.self) private var viewModel

    let item: WallpaperItem
    let isSelected: Bool
    let isDownloaded: Bool
    let appLanguage: AppLanguage
    let remoteAuthorizationHeader: String?
    let onTap: () -> Void

    @State private var isHovered = false
    @State private var isConfirmingDelete = false

    var body: some View {
        Button(action: onTap) {
            thumbnailArea
                .aspectRatio(1, contentMode: .fill)
                .overlay(alignment: .bottom) { infoOverlay }
                .overlay(alignment: .topLeading) { typeBadge }
                .overlay(alignment: .bottomTrailing) { statusBadge }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .compositingGroup()
                .overlay(selectionBorder)
                .overlay(selectionCheckmark)
                .cardShadow()
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !isSelected ? 1.04 : 1.0)
        .shadow(
            color: isHovered ? Color.accentColor.opacity(0.25) : .clear,
            radius: 12, y: 0
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu { contextMenuContent }
        .confirmationDialog(L10n.t("Delete Wallpaper?", appLanguage), isPresented: $isConfirmingDelete) {
            Button(L10n.t("Delete", appLanguage), role: .destructive) {
                viewModel.deleteWallpaper(item)
            }
            Button(L10n.t("Cancel", appLanguage), role: .cancel) { }
        } message: {
            Text(L10n.t("This removes the wallpaper from disk.", appLanguage))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(L10n.wallpaperType(item.type, appLanguage))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? L10n.t("Press to deselect", appLanguage) : L10n.t("Press to select", appLanguage))
    }

    private var thumbnailArea: some View {
        Group {
            if let thumbPath = item.thumbnailPath {
                ThumbnailView(url: thumbPath, version: item.thumbnailVersion, fallbackIcon: item.typeIcon)
            } else if let previewPath = item.previewPath {
                ThumbnailView(url: previewPath, version: item.thumbnailVersion, fallbackIcon: item.typeIcon)
            } else if item.isRemote, let thumbnailURL = item.remoteThumbnailURL {
                AuthenticatedThumbnailView(
                    url: thumbnailURL,
                    authorizationHeader: remoteAuthorizationHeader,
                    fallbackIcon: item.typeIcon
                )
            } else {
                remotePlaceholder
            }
        }
    }

    private var remotePlaceholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: item.typeIcon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    private var infoOverlay: some View {
        Text(item.title)
            .font(.caption).fontWeight(.medium)
            .foregroundStyle(.white)
            .lineLimit(2).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private var typeBadge: some View {
        Text(L10n.wallpaperType(item.type, appLanguage))
            .font(.caption2).fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            .padding(5)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if item.isRemote || item.isExtracted || item.pkgPath != nil {
            HStack(spacing: 4) {
                if item.isRemote {
                    Image(systemName: isDownloaded ? "checkmark.icloud.fill" : "icloud.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(isDownloaded ? .green : .blue)
                }
                if item.isExtracted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
                if item.pkgPath != nil {
                    Image(systemName: "shippingbox.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(4)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            .padding(6)
        }
    }

    @ViewBuilder
    private var selectionBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(.tint, lineWidth: 2.5)
            .opacity(isSelected ? 1 : 0)
    }

    @ViewBuilder
    private var selectionCheckmark: some View {
        if isSelected {
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .background(Circle().fill(.white).frame(width: 20, height: 20))
                        .scaleEffect(isSelected ? 1.0 : 0.5)
                        .padding(8)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        let needsExtract = item.pkgPath != nil

        if item.isRemote && !isDownloaded {
            Button(L10n.t("Download", appLanguage)) {
                viewModel.downloadRemoteWallpaper(item)
            }
        } else {
            Button(L10n.t(needsExtract ? "Set as Wallpaper..." : "Set as Wallpaper", appLanguage)) {
                viewModel.setAsWallpaper(item)
            }
            Button(L10n.t(needsExtract ? "Set on All Screens..." : "Set on All Screens", appLanguage)) {
                viewModel.setAsWallpaperForAllScreens(item)
            }
            if needsExtract {
                Divider()
                Button(L10n.t("Extract to Disk...", appLanguage)) {
                    viewModel.selectedIDs = [item.id]
                    viewModel.showExtractSheet = true
                }
            }

            Divider()

            Menu(L10n.t("Change Rating", appLanguage)) {
                ForEach(["Everyone", "Questionable", "Mature"], id: \.self) { rating in
                    Button(L10n.contentRating(rating, appLanguage)) {
                        viewModel.setContentRating(item, rating: rating)
                    }
                    if item.contentRating == rating {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Menu(L10n.t("Add to Collection", appLanguage)) {
                ForEach(viewModel.allCollections, id: \.self) { collection in
                    Button(collection) {
                        viewModel.addToCollection(item, collection: collection)
                    }
                }
                if !viewModel.allCollections.isEmpty {
                    Divider()
                }
                Button(L10n.t("New Collection...", appLanguage)) {
                    viewModel.selectedIDs = [item.id]
                    viewModel.showNewCollectionSheet = true
                }
            }

            if !item.collections.isEmpty {
                Menu(L10n.t("Remove from Collection", appLanguage)) {
                    ForEach(item.collections, id: \.self) { collection in
                        Button(collection) {
                            viewModel.removeFromCollection(item, collection: collection)
                        }
                    }
                }
            }

            Divider()
            Button(L10n.t("Show in Finder", appLanguage)) { viewModel.openInFinder(item) }

            Divider()
            Button(L10n.t("Delete", appLanguage)) {
                isConfirmingDelete = true
            }
        }
    }
}
