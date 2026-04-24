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
            .background(Color.mAccent)
            .clipShape(RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius))
        }
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
