import SwiftUI

// MARK: - Glass Effect Modifiers

struct ToolbarGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .glassEffect(.regular)
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
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
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
}
