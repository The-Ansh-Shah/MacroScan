import SwiftUI

/// Horizontal row of dates with a target-hit indicator dot.
/// Today is rightmost; scrolling left reveals older days (capped at 60 back).
struct DateScroller: View {
    @Binding var selectedDate: Date
    let allEntries: [LogEntry]
    let profile: UserProfile?

    private let daysToShow = 60

    private var dates: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<daysToShow).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: today)
        }.reversed()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(dates, id: \.self) { date in
                        DateScrollerCell(
                            date: date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                            dotColor: dotColor(for: date)
                        )
                        .id(date)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = date
                            }
                            Haptics.selectionChanged()
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            .onAppear {
                if let today = dates.last {
                    proxy.scrollTo(today, anchor: .trailing)
                }
            }
            .onChange(of: selectedDate) { _, newDate in
                let key = Calendar.current.startOfDay(for: newDate)
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(key, anchor: .center)
                }
            }
        }
    }

    /// Dot color reflects calorie target state for the day.
    private func dotColor(for date: Date) -> Color? {
        guard let profile else { return nil }
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let dayEntries = allEntries.filter { $0.loggedAt >= start && $0.loggedAt < end }
        guard !dayEntries.isEmpty else { return nil }

        let totals = dayEntries.reduce(ScaledMacros.zero) { $0 + $1.scaledMacros }

        // Red if significantly over calorie target
        if totals.calories > profile.calorieTarget * 1.1 {
            return .mOver
        }
        // Green if hit protein + within 90-110% calories
        let proteinRatio = profile.proteinTargetG > 0 ? totals.proteinG / profile.proteinTargetG : 0
        let calorieRatio = profile.calorieTarget > 0 ? totals.calories / profile.calorieTarget : 0
        if proteinRatio >= 0.9 && calorieRatio >= 0.9 && calorieRatio <= 1.1 {
            return .mOnTarget
        }
        if calorieRatio >= 0.7 {
            return .mApproaching
        }
        return .mUnder
    }
}

private struct DateScrollerCell: View {
    let date: Date
    let isSelected: Bool
    let dotColor: Color?

    private var dayOfMonth: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private var dayOfWeek: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(dayOfWeek)
                .font(.mCaption)
                .foregroundStyle(isSelected ? Color.white : Color.mTextSecondary)

            Text(dayOfMonth)
                .font(.mHeadline)
                .foregroundStyle(isSelected ? Color.white : Color.mTextPrimary)

            Circle()
                .fill(dotColor ?? Color.clear)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(isToday && dotColor == nil ? Color.mAccent : Color.clear, lineWidth: 1)
                )
        }
        .frame(width: 44, height: 64)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.mAccent : Color.clear)
        )
    }
}
