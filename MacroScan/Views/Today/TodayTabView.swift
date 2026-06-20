import SwiftUI
import SwiftData

/// The Today tab's root — owns the selected date and shows a horizontal
/// scroller above a `DayView` bound to that date.
struct TodayTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LogEntry.loggedAt, order: .reverse)
    private var allEntries: [LogEntry]

    @Query private var profiles: [UserProfile]

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DateScroller(
                    selectedDate: $selectedDate,
                    allEntries: allEntries,
                    profile: profile
                )
                .padding(.vertical, Spacing.xs)
                .background(Color.mBgPrimary)

                Divider()

                DayView(date: $selectedDate, isTodayTab: true)
            }
        }
    }
}
