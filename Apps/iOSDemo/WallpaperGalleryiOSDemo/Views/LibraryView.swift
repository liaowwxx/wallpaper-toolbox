import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LibraryView: View {
    @Environment(RemoteLibraryViewModel.self) private var library

    private let columns = [
        GridItem(.adaptive(minimum: 156, maximum: 240), spacing: 12)
    ]

    var body: some View {
        @Bindable var library = library

        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(library.filteredItems) { item in
                    NavigationLink(value: item) {
                        RemoteWallpaperCard(item: item, baseURL: library.baseURL)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
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
}

private struct RemoteWallpaperCard: View {
    let item: RemoteWallpaperItem
    let baseURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                ThumbnailImage(url: item.thumbnailURL(relativeTo: baseURL), fallbackIcon: item.typeIcon)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
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

            HStack(spacing: 6) {
                Image(systemName: item.isUnpacked ? "checkmark.circle.fill" : "shippingbox")
                    .foregroundStyle(item.isUnpacked ? .green : .orange)
                Text(item.isUnpacked ? "Unpacked" : "Needs unpack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(8)
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
