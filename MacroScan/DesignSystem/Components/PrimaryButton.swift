import SwiftUI

struct PrimaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(.mHeadline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: DesignConstants.minTapTarget)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius, style: .continuous)
                    .fill(Color.mAccentGradient)
            )
            .shadow(color: Color.mAccent.opacity(0.30), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Tactile press feedback: a gentle spring scale + opacity dip on press.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(DesignConstants.springAnimation, value: configuration.isPressed)
    }
}

/// Empty state view for lists — SF Symbol + message + action button
struct EmptyStateView: View {
    let symbol: String
    let message: String
    let buttonTitle: String?
    let action: (() -> Void)?

    init(symbol: String, message: String, buttonTitle: String? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.message = message
        self.buttonTitle = buttonTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(Color.mTextTertiary)

            Text(message)
                .font(.mBody)
                .foregroundStyle(Color.mTextSecondary)
                .multilineTextAlignment(.center)

            if let buttonTitle, let action {
                PrimaryButton(buttonTitle, action: action)
                    .frame(maxWidth: 200)
            }
        }
        .padding(Spacing.xl)
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        PrimaryButton("Log Food", icon: "plus.circle.fill") {}
        EmptyStateView(
            symbol: "fork.knife",
            message: "No meals logged today.\nTap below to get started.",
            buttonTitle: "Add Food",
            action: {}
        )
    }
    .padding()
}
