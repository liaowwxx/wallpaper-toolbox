import SwiftUI

struct GalleryView: View {
    @Environment(AppViewModel.self) private var viewModel

    private let columnSpacing: CGFloat = 10
    private let cardMinWidth: CGFloat = 160

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cardMinWidth, maximum: 240), spacing: columnSpacing)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: columnSpacing) {
                ForEach(viewModel.filteredWallpapers) { item in
                    WallpaperCard(
                        item: item,
                        isSelected: viewModel.selectedIDs.contains(item.id),
                        onTap: { viewModel.toggleSelection(item.id) }
                    )
                    .equatable()
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
    let onTap: () -> Void

    static func == (lhs: WallpaperCard, rhs: WallpaperCard) -> Bool {
        lhs.item.id == rhs.item.id && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        WallpaperCardInternal(item: item, isSelected: isSelected, onTap: onTap)
    }
}

// MARK: - Internal (stateful, only diffed when POD inputs change)

private struct WallpaperCardInternal: View {
    @Environment(AppViewModel.self) private var viewModel

    let item: WallpaperItem
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        thumbnailArea
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottom) { infoOverlay }
            .overlay(alignment: .topLeading) { typeBadge }
            .overlay(alignment: .bottomTrailing) { statusBadge }
            .compositingGroup()
            .overlay(selectionBorder)
            .overlay(selectionCheckmark)
            .cardShadow()
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
            .onTapGesture(perform: onTap)
            .contextMenu { contextMenuContent }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.title), \(item.typeLabel)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(isSelected ? "Double-tap to deselect" : "Double-tap to select")
    }

    private var thumbnailArea: some View {
        Group {
            if let thumbPath = item.thumbnailPath {
                ThumbnailView(url: thumbPath, fallbackIcon: item.typeIcon)
            } else if let previewPath = item.previewPath {
                ThumbnailView(url: previewPath, fallbackIcon: item.typeIcon)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: item.typeIcon)
                        .font(.largeTitle).foregroundStyle(.secondary)
                }
            }
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
        Text(item.typeLabel)
            .font(.caption2).fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            .padding(5)
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
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

        Button(needsExtract ? "Set as Wallpaper..." : "Set as Wallpaper") {
            viewModel.setAsWallpaper(item)
        }
        Button(needsExtract ? "Set on All Screens..." : "Set on All Screens") {
            viewModel.setAsWallpaperForAllScreens(item)
        }
        if needsExtract {
            Divider()
            Button("Extract to Disk...") {
                viewModel.selectedIDs = [item.id]
                viewModel.showExtractSheet = true
            }
        }

        Divider()

        Menu("Change Rating") {
            ForEach(["Everyone", "Questionable", "Mature"], id: \.self) { rating in
                Button(rating) {
                    viewModel.setContentRating(item, rating: rating)
                }
                if item.contentRating == rating {
                    Image(systemName: "checkmark")
                }
            }
        }

        Menu("Add to Collection") {
            ForEach(viewModel.allCollections, id: \.self) { collection in
                Button(collection) {
                    viewModel.addToCollection(item, collection: collection)
                }
            }
            if !viewModel.allCollections.isEmpty {
                Divider()
            }
            Button("New Collection...") {
                viewModel.selectedIDs = [item.id]
                viewModel.showNewCollectionSheet = true
            }
        }

        if !item.collections.isEmpty {
            Menu("Remove from Collection") {
                ForEach(item.collections, id: \.self) { collection in
                    Button(collection) {
                        viewModel.removeFromCollection(item, collection: collection)
                    }
                }
            }
        }

        Divider()
        Button("Show in Finder") { viewModel.openInFinder(item) }

        Divider()
        Button("Delete") {
            viewModel.deleteWallpaper(item)
        }
    }
}
