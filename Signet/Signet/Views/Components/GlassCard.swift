import SwiftUI

struct GlassCard<Content: View>: View {
    let content: () -> Content
    var padding: CGFloat = 16

    init(padding: CGFloat = 16, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background { cardBackground }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 26, *) {
            GlassCardBackground26()
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                )
        }
    }
}

@available(iOS 26, *)
private struct GlassCardBackground26: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .glassEffect()
    }
}
