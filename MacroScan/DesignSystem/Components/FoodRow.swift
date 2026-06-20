import SwiftUI

struct FoodRow: View {
    let name: String
    let detail: String
    let calories: Int
    let proteinG: Int
    let showChevron: Bool
    let isVerified: Bool

    init(name: String, detail: String, calories: Int, proteinG: Int, showChevron: Bool = true, isVerified: Bool = false) {
        self.name = name
        self.detail = detail
        self.calories = calories
        self.proteinG = proteinG
        self.showChevron = showChevron
        self.isVerified = isVerified
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.mBody)
                        .foregroundStyle(Color.mTextPrimary)
                        .lineLimit(1)
                    if isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.mOnTarget)
                    }
                }

                Text(detail)
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text("\(calories) cal")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextPrimary)

                Text("\(proteinG)g protein")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextSecondary)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            }
        }
        .frame(minHeight: DesignConstants.minTapTarget)
        .contentShape(Rectangle())
    }
}

#Preview {
    List {
        FoodRow(name: "Greek Yogurt", detail: "Fage 0% — 200g", calories: 130, proteinG: 24)
        FoodRow(name: "Brown Rice", detail: "Generic — 150g", calories: 165, proteinG: 4)
    }
}
