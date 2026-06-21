import SwiftUI

// MARK: - Motion

enum AppMotion {
    static let hover = Animation.easeOut(duration: 0.16)
    static let selection = Animation.spring(response: 0.34, dampingFraction: 0.88)
    static let panel = Animation.easeInOut(duration: 0.22)
    static let content = Animation.spring(response: 0.38, dampingFraction: 0.86)
}

// MARK: - Gallery Colors

enum GalleryTheme {
    static let backgroundTop = Color(nsColor: .windowBackgroundColor)
    static let backgroundBottom = Color.black.opacity(0.12)
    static let violet = Color(red: 0.44, green: 0.36, blue: 0.95)
    static let rose = Color(red: 1.0, green: 0.25, blue: 0.45)
    static let cyan = Color(red: 0.10, green: 0.72, blue: 1.0)
    static let green = Color(red: 0.20, green: 0.78, blue: 0.48)
    static let orange = Color(red: 1.0, green: 0.54, blue: 0.20)

    static func accent(for type: String) -> Color {
        switch type.lowercased() {
        case "video":
            return rose
        case "image":
            return cyan
        case "scene":
            return violet
        case "web":
            return green
        case "application":
            return orange
        default:
            return .accentColor
        }
    }
}

// MARK: - Glass Effect Modifiers

struct ToolbarGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct GalleryGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var isInteractive = false

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(.regularMaterial)
                    .overlay {
                        if let tint {
                            shape.fill(tint.opacity(0.08))
                        }
                    }
                    .overlay {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.04),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
            }
            .glassEffect(
                isInteractive ? .regular.interactive() : .regular,
                in: shape
            )
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.08),
                            tint?.opacity(0.20) ?? Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            }
    }
}

struct GalleryAtmosphereBackground: View {
    var accent: Color = GalleryTheme.violet

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    GalleryTheme.backgroundTop,
                    Color(nsColor: .controlBackgroundColor),
                    GalleryTheme.backgroundBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.14),
                            accent.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            GalleryTheme.cyan.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.035),
                    Color.clear,
                    Color.black.opacity(0.045)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Shadow Modifiers

struct SubtleShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            .shadow(color: .black.opacity(0.04), radius: 1, y: 0.5)
    }
}

struct CardShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
}

// MARK: - View Extensions

extension View {
    func toolbarGlass() -> some View {
        modifier(ToolbarGlass())
    }

    func subtleShadow() -> some View {
        modifier(SubtleShadow())
    }

    func cardShadow() -> some View {
        modifier(CardShadow())
    }

    func galleryGlassSurface<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        modifier(GalleryGlassSurface(shape: shape, tint: tint, isInteractive: isInteractive))
    }
}
