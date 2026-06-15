import SwiftUI

extension View {
    func statusOverlay() -> some View {
        modifier(StatusOverlayModifier())
    }
}

private struct StatusOverlayModifier: ViewModifier {
    @Environment(RemoteLibraryViewModel.self) private var library

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if library.isLoading {
                    StatusPill {
                        ProgressView()
                        Text("Loading")
                    }
                } else if let error = library.errorMessage {
                    StatusPill {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                            .lineLimit(2)
                    }
                    .foregroundStyle(.orange)
                } else if !library.statusMessage.isEmpty {
                    StatusPill {
                        Image(systemName: "checkmark.circle.fill")
                        Text(library.statusMessage)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }
    }
}

private struct StatusPill<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: .capsule)
        .padding(.bottom, 10)
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}
