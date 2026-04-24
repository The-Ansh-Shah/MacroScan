import SwiftUI

/// Shimmer loading effect for skeleton placeholders.
/// Usage: `RoundedRectangle(cornerRadius: 8).shimmer()`
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.mTextTertiary.opacity(0.3),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 300
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

/// A skeleton placeholder row for loading states
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.mTextTertiary.opacity(0.2))
                    .frame(width: 120, height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.mTextTertiary.opacity(0.15))
                    .frame(width: 80, height: 10)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.mTextTertiary.opacity(0.2))
                    .frame(width: 50, height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.mTextTertiary.opacity(0.15))
                    .frame(width: 60, height: 10)
            }
        }
        .frame(minHeight: DesignConstants.minTapTarget)
        .shimmer()
    }
}
