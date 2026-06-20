import SwiftUI

/// A consolidated, search-first "Add" sheet presented from `DayView`.
///
/// Routes to the existing logging flows via closures so that `DayView`
/// remains the single source of truth for sheet presentation state. Each
/// closure is expected to dismiss this sheet, then trip the matching
/// `showing…` bool back in `DayView`.
struct AddFoodSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSearch: () -> Void
    #if canImport(UIKit)
    let onScan: () -> Void
    let onPhoto: () -> Void
    #endif
    let onRecipes: () -> Void
    let onQuickAdd: () -> Void
    let onManual: () -> Void
    let onGenerateRecipe: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    searchButton

                    #if canImport(UIKit)
                    primaryActions
                    #endif

                    secondaryList
                }
                .padding(Spacing.md)
            }
            .navigationTitle("Add Food")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Search (prominent, top)

    private var searchButton: some View {
        Button(action: onSearch) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.mHeadline)
                    .foregroundStyle(Color.mAccent)
                Text("Search foods")
                    .font(.mHeadline)
                    .foregroundStyle(Color.mTextPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: DesignConstants.minTapTarget)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                    .fill(Color.mBgSecondary)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Primary actions (Scan / Photo) — UIKit only

    #if canImport(UIKit)
    private var primaryActions: some View {
        HStack(spacing: Spacing.md) {
            primaryAction(
                title: "Scan",
                systemImage: "barcode.viewfinder",
                action: onScan
            )
            primaryAction(
                title: "Photo",
                systemImage: "camera.fill",
                action: onPhoto
            )
        }
    }

    private func primaryAction(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.mTitle3)
                Text(title)
                    .font(.mBody)
            }
            .foregroundStyle(Color.mAccent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                    .fill(Color.mBgSecondary)
            )
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Secondary list (Recipes / Quick add / Manual)

    private var secondaryList: some View {
        VStack(spacing: 0) {
            secondaryRow(
                title: "Recipes",
                systemImage: "book.closed",
                action: onRecipes
            )
            Divider().padding(.leading, Spacing.md)
            secondaryRow(
                title: "Generate a recipe (AI)",
                systemImage: "sparkles",
                action: onGenerateRecipe
            )
            Divider().padding(.leading, Spacing.md)
            secondaryRow(
                title: "Quick add calories",
                systemImage: "bolt.fill",
                action: onQuickAdd
            )
            Divider().padding(.leading, Spacing.md)
            secondaryRow(
                title: "Manual entry",
                systemImage: "square.and.pencil",
                action: onManual
            )
        }
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
    }

    private func secondaryRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: systemImage)
                    .font(.mBody)
                    .foregroundStyle(Color.mAccent)
                    .frame(width: 24)
                Text(title)
                    .font(.mBody)
                    .foregroundStyle(Color.mTextPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: DesignConstants.minTapTarget)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
