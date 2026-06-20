import SwiftUI
import SwiftData

/// Collapsible insights card — surfaces `BalanceFlag`s for the current day.
/// See Phase 13 for the flag-generation logic.
struct InsightsCard: View {
    @Environment(\.modelContext) private var modelContext
    let date: Date
    let profile: UserProfile
    var onDeepLink: ((BalanceFlag.DeepLink) -> Void)? = nil

    @State private var isExpanded: Bool = true
    @State private var dismissedThisSession: Set<String> = []

    private var flags: [BalanceFlag] {
        let repo = FoodRepository(modelContext: modelContext)
        return repo.balanceFlags(forDate: date, profile: profile)
            .filter { !dismissedThisSession.contains($0.id) }
            .sorted { $0.severity.rank > $1.severity.rank }
            .prefix(2)
            .map { $0 }
    }

    var body: some View {
        if !flags.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.mAccent)
                        Text("Insights")
                            .font(.mHeadline)
                            .foregroundStyle(Color.mTextPrimary)
                        Spacer()
                        Text("\(flags.count)")
                            .font(.mCaption)
                            .foregroundStyle(Color.mTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.mBgPrimary, in: Capsule())
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.mCaption)
                            .foregroundStyle(Color.mTextTertiary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    ForEach(flags) { flag in
                        flagRow(flag)
                    }
                }
            }
            .padding(Spacing.md)
            .mCard()
            .overlay(
                RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                    .stroke(borderColor, lineWidth: flags.first?.severity == .critical ? 1.5 : 0)
            )
        }
    }

    private var borderColor: Color {
        guard let top = flags.first?.severity else { return .clear }
        switch top {
        case .critical: return .mOver
        case .warning: return .mApproaching
        case .info: return .clear
        }
    }

    @ViewBuilder
    private func flagRow(_ flag: BalanceFlag) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: flag.symbol)
                .foregroundStyle(flag.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(flag.title)
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextPrimary)
                Text(flag.message)
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if flag.deepLink != nil {
                Image(systemName: "chevron.right")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            }

            if flag.severity == .info {
                Button {
                    withAnimation { _ = dismissedThisSession.insert(flag.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.mTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let link = flag.deepLink else { return }
            Haptics.selectionChanged()
            onDeepLink?(link)
        }
    }
}
