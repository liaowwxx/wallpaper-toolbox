import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LibraryView: View {
    @Environment(RemoteLibraryViewModel.self) private var library
    @State private var baseCardWidth: CGFloat = 156
    @GestureState private var magnification: CGFloat = 1.0

    private var cardWidth: CGFloat {
        clampedCardWidth(baseCardWidth * magnification)
    }

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 12)
        ]
    }

    var body: some View {
        @Bindable var library = library

        ScrollView {
            LibraryFilterBar()
                .padding(.horizontal, 16)
                .padding(.top, 12)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(library.filteredItems) { item in
                    NavigationLink(value: item) {
                        RemoteWallpaperCard(item: item, baseURL: library.baseURL, cardWidth: cardWidth)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .contentShape(.rect)
            .simultaneousGesture(zoomGesture)
        }
        .navigationTitle("Library")
        .searchable(text: $library.query, prompt: "Search wallpapers")
        .navigationDestination(for: RemoteWallpaperItem.self) { item in
            WallpaperDetailView(item: item)
        }
        .overlay {
            if library.filteredItems.isEmpty {
                ContentUnavailableView(
                    "No Wallpapers",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Connect to a Windows library or clear the current filter.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await library.connect() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(library.isLoading)
                .accessibilityLabel("Reload library")
            }
        }
        .statusOverlay()
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                baseCardWidth = clampedCardWidth(baseCardWidth * value.magnification)
            }
    }

    private func clampedCardWidth(_ value: CGFloat) -> CGFloat {
        min(260, max(96, value))
    }
}

private struct LibraryFilterBar: View {
    @Environment(RemoteLibraryViewModel.self) private var library

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "All",
                    systemImage: "square.grid.2x2",
                    isSelected: library.activeFilterCount == 0
                ) {
                    library.clearFilters()
                }

                ForEach(library.availableTypes, id: \.self) { type in
                    FilterChip(
                        title: type.label,
                        systemImage: type.icon,
                        isSelected: library.selectedType == type
                    ) {
                        library.selectedType = library.selectedType == type ? nil : type
                    }
                }

                ForEach(library.allCollections, id: \.self) { collection in
                    FilterChip(
                        title: collection,
                        systemImage: "rectangle.stack",
                        isSelected: library.selectedCollection == collection
                    ) {
                        library.selectedCollection = library.selectedCollection == collection ? nil : collection
                    }
                }

                ForEach(library.allTags, id: \.self) { tag in
                    FilterChip(
                        title: tag,
                        systemImage: "tag",
                        isSelected: library.selectedTag == tag
                    ) {
                        library.selectedTag = library.selectedTag == tag ? nil : tag
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

private struct FilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10), in: .capsule)
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct RemoteWallpaperCard: View {
    let item: RemoteWallpaperItem
    let baseURL: URL?
    let cardWidth: CGFloat

    private var previewSize: CGFloat {
        max(80, cardWidth - 16)
    }

    private var cardHeight: CGFloat {
        previewSize + 88
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                ThumbnailImage(url: item.thumbnailURL(relativeTo: baseURL), fallbackIcon: item.typeIcon)
                    .frame(width: previewSize, height: previewSize)
                    .clipShape(.rect(cornerRadius: 8))

                Label(item.typeLabel, systemImage: item.typeIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.58), in: .capsule)
                    .padding(7)
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: 38, alignment: .topLeading)

            HStack(spacing: 6) {
                Image(systemName: item.isUnpacked ? "checkmark.circle.fill" : "shippingbox")
                    .foregroundStyle(item.isUnpacked ? .green : .orange)
                Text(item.isUnpacked ? "Unpacked" : "Needs unpack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 18)
        }
        .padding(8)
        .frame(width: cardWidth, height: cardHeight, alignment: .topLeading)
        .background(.background, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.typeLabel)")
    }
}

struct ThumbnailImage: View {
    @Environment(RemoteLibraryViewModel.self) private var library

    let url: URL?
    let fallbackIcon: String
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: loadID) {
            await loadImage()
        }
        .clipped()
    }

    private var loadID: String {
        "\(url?.absoluteString ?? "")|\(library.authorizationHeader ?? "")"
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo, .teal, .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: fallbackIcon)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
        }
    }

    @MainActor
    private func loadImage() async {
        image = nil
        guard let url else { return }

        var request = URLRequest(url: url)
        if let authorizationHeader = library.authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return
            }
            #if os(iOS)
            guard let uiImage = UIImage(data: data) else { return }
            image = Image(uiImage: uiImage)
            #endif
        } catch {
            image = nil
        }
    }
}
