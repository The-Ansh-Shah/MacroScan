import SwiftUI

/// A section showing entries for a single meal type.
/// Swipe actions only work inside a `List`, but this view is rendered in a
/// card-based `VStack`, so we expose delete/edit via `.contextMenu` (long-press)
/// and a visible trailing ellipsis button that opens the same actions as a
/// `.confirmationDialog`. Both satisfy the reliable-delete requirement.
struct MealSectionView: View {
    let mealType: MealType
    let entries: [LogEntry]
    let onDelete: (LogEntry) -> Void
    let onEdit: (LogEntry) -> Void
    var onCopyMeal: (() -> Void)?

    @State private var entryActionTarget: LogEntry?

    private var sectionMacros: ScaledMacros {
        entries.reduce(ScaledMacros.zero) { $0 + $1.scaledMacros }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Image(systemName: mealType.icon)
                    .foregroundStyle(Color.mAccent)
                Text(mealType.displayName)
                    .font(.mHeadline)
                    .foregroundStyle(Color.mTextPrimary)

                Spacer()

                Text("\(Int(sectionMacros.calories)) cal")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextSecondary)
            }
            .contentShape(Rectangle())
            .contextMenu {
                if let onCopyMeal {
                    Button {
                        onCopyMeal()
                    } label: {
                        Label("Copy meal to…", systemImage: "doc.on.doc")
                    }
                }
            }

            ForEach(entries) { entry in
                entryRow(entry)
            }
        }
        .padding(Spacing.md)
        .mCard()
        .confirmationDialog(
            entryActionTarget?.displayName ?? "Log entry",
            isPresented: .init(
                get: { entryActionTarget != nil },
                set: { if !$0 { entryActionTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: entryActionTarget
        ) { entry in
            Button("Edit") {
                onEdit(entry)
                entryActionTarget = nil
            }
            Button("Delete", role: .destructive) {
                Haptics.deleted()
                onDelete(entry)
                entryActionTarget = nil
            }
            Button("Cancel", role: .cancel) {
                entryActionTarget = nil
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: LogEntry) -> some View {
        let macros = entry.scaledMacros
        HStack(spacing: Spacing.xs) {
            if entry.isQuickAdd {
                quickAddRow(entry: entry, macros: macros)
            } else if entry.food != nil {
                FoodRow(
                    name: entry.displayName,
                    detail: rowDetail(entry: entry),
                    calories: Int(macros.calories),
                    proteinG: Int(macros.proteinG),
                    showChevron: false,
                    isVerified: entry.food?.userVerified ?? false
                )
            }

            Button {
                entryActionTarget = entry
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.mBody)
                    .foregroundStyle(Color.mTextTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More actions for \(entry.displayName)")
        }
        .contextMenu {
            Button {
                onEdit(entry)
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
            Button(role: .destructive) {
                Haptics.deleted()
                onDelete(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func quickAddRow(entry: LogEntry, macros: ScaledMacros) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "pencil.circle")
                .font(.mBody)
                .foregroundStyle(Color.mTextTertiary)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(entry.displayName)
                    .font(.mBody)
                    .italic()
                    .foregroundStyle(Color.mTextPrimary)
                    .lineLimit(1)

                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text("\(Int(macros.calories)) cal")
                    .font(.mSubheadline)
                    .foregroundStyle(Color.mTextPrimary)

                if macros.proteinG > 0 {
                    Text("\(Int(macros.proteinG))g protein")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextSecondary)
                }
            }
        }
        .frame(minHeight: DesignConstants.minTapTarget)
        .contentShape(Rectangle())
    }

    private func rowDetail(entry: LogEntry) -> String {
        let amountStr: String
        if let sv = entry.servingsEaten, sv > 0,
           let sz = entry.food?.servingSizeGrams, sz > 0 {
            let svDisplay = sv == sv.rounded() ? "\(Int(sv))" : String(format: "%.1f", sv)
            amountStr = "\(svDisplay) serving\(sv == 1 ? "" : "s") (\(Int(entry.gramsEaten))g)"
        } else {
            amountStr = "\(Int(entry.gramsEaten))g"
        }
        if let notes = entry.notes, !notes.isEmpty {
            return "\(amountStr) · \(notes)"
        }
        return amountStr
    }
}
