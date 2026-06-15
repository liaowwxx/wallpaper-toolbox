import SwiftUI

struct CollectionsView: View {
    @Environment(RemoteLibraryViewModel.self) private var library

    var body: some View {
        List {
            Section {
                Button {
                    library.selectedCollection = nil
                    library.selectedTab = .library
                } label: {
                    CollectionRow(
                        title: "All Wallpapers",
                        count: library.items.count,
                        isSelected: library.selectedCollection == nil
                    )
                }
            }

            Section("Collections") {
                ForEach(library.allCollections, id: \.self) { collection in
                    Button {
                        library.selectedCollection = collection
                        library.selectedTab = .library
                    } label: {
                        CollectionRow(
                            title: collection,
                            count: library.items.filter { $0.collections.contains(collection) }.count,
                            isSelected: library.selectedCollection == collection
                        )
                    }
                }
            }

            Section("Tags") {
                TagCloud(tags: Array(Set(library.items.flatMap(\.tags))).sorted())
            }
        }
        .navigationTitle("Collections")
        .overlay {
            if library.items.isEmpty {
                ContentUnavailableView(
                    "No Library",
                    systemImage: "rectangle.stack",
                    description: Text("Load the sample library or connect to a Windows server.")
                )
            }
        }
    }
}

private struct CollectionRow: View {
    let title: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack {
            Label(title, systemImage: isSelected ? "checkmark.circle.fill" : "rectangle.stack")
            Spacer()
            Text(count, format: .number)
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }
}

private struct TagCloud: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: .capsule)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews: subviews, proposal: proposal).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, proposal: ProposedViewSize(width: bounds.width, height: proposal.height))
        for item in rows.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.frame.minX, y: bounds.minY + item.frame.minY),
                proposal: ProposedViewSize(item.frame.size)
            )
        }
    }

    private func arrange(subviews: Subviews, proposal: ProposedViewSize) -> (items: [(index: Int, frame: CGRect)], size: CGSize) {
        let maxWidth = proposal.width ?? 320
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var items: [(Int, CGRect)] = []

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > maxWidth {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            items.append((index, CGRect(origin: origin, size: size)))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return (items, CGSize(width: maxWidth, height: origin.y + rowHeight))
    }
}
