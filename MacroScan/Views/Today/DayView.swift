import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit

/// Wraps a captured UIImage so it can drive `.sheet(item:)`.
struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}
#endif

/// Shows entries, totals, and insights for a specific calendar day.
/// Accepts a bound `date` from the parent so chevron navigation + the date
/// scroller can swap the visible day in place.
struct DayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \LogEntry.loggedAt, order: .reverse)
    private var allEntries: [LogEntry]

    @Query private var profiles: [UserProfile]

    @Binding var date: Date

    /// When true, hides the "Today" navigation affordances (close-gap, add menu).
    /// Used when DayView is pushed from History for a past date.
    var isTodayTab: Bool = true

    @State private var showingManualEntry = false
    @State private var showingScanner = false
    @State private var showingCloseGap = false
    @State private var showingSearch = false

    @State private var showingRecipes = false
    @State private var showingQuickAdd = false
    @State private var prefilledSearchQuery: String = ""
    @State private var editingEntry: LogEntry?
    @State private var editingQuickAddEntry: LogEntry?
    @State private var copyingMealType: MealType?
    @State private var showCopyDatePicker = false
    @State private var copyTargetDate = Date()
    @State private var toastMessage: String?
    @State private var todayStepCount: Int?
    #if canImport(UIKit)
    @State private var showingPhotoCapture = false
    @State private var capturedPhoto: CapturedPhoto?
    #endif

    private var profile: UserProfile? { profiles.first }

    private var dayEntries: [LogEntry] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return allEntries.filter { $0.loggedAt >= start && $0.loggedAt < end }
    }

    private var dailyTotals: ScaledMacros {
        dayEntries.reduce(ScaledMacros.zero) { $0 + $1.scaledMacros }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var canGoForward: Bool {
        !isToday  // never navigate into the future
    }

    private var yesterdayHasEntries: Bool {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) else { return false }
        let start = Calendar.current.startOfDay(for: yesterday)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return allEntries.contains { $0.loggedAt >= start && $0.loggedAt < end }
    }

    private var canGoBack: Bool {
        // Disable if there are no entries on any earlier day
        guard let earliest = allEntries.last?.loggedAt else { return !isToday }
        return Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: earliest)
            || isToday  // always allow going back from today to show yesterday
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                if let profile {
                    macroRingsSection(profile: profile)

                    if isTodayTab && isToday {
                        QuickLogBar()
                    }

                    WaterCard(date: date, profile: profile)

                    if !dayEntries.isEmpty {
                        MicroBarsView(totals: dailyTotals, profile: profile)
                    }

                    if isToday {
                        InsightsCard(date: date, profile: profile, onDeepLink: handleDeepLink)
                    }
                }

                if dayEntries.isEmpty {
                    EmptyStateView(
                        symbol: "fork.knife",
                        message: emptyStateMessage,
                        buttonTitle: isTodayTab && isToday ? "Add Food" : nil,
                        action: isTodayTab && isToday ? { showingManualEntry = true } : nil
                    )
                    .padding(.top, Spacing.xl)

                    if isTodayTab && isToday && yesterdayHasEntries {
                        Button {
                            copyYesterdaysMeals()
                        } label: {
                            Label("Copy yesterday's meals", systemImage: "doc.on.doc")
                                .font(.mBody)
                                .frame(maxWidth: .infinity)
                                .padding(Spacing.sm)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.mAccent)
                    }
                } else {
                    mealSections

                    if isTodayTab && isToday {
                        Button {
                            showingCloseGap = true
                        } label: {
                            Label("What should I eat?", systemImage: "lightbulb")
                                .font(.mBody)
                                .frame(maxWidth: .infinity)
                                .padding(Spacing.sm)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.mAccent)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
        }
        .navigationTitle(titleForDate)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: Spacing.xs) {
                    Button {
                        stepDay(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!canGoBack)

                    Button {
                        stepDay(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canGoForward)
                }
            }

            if isTodayTab && isToday {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingSearch = true } label: {
                            Label("Search Foods", systemImage: "magnifyingglass")
                        }
                        #if canImport(UIKit)
                        Button { showingScanner = true } label: {
                            Label("Scan Barcode", systemImage: "barcode.viewfinder")
                        }
                        Button { showingPhotoCapture = true } label: {
                            Label("Snap Photo", systemImage: "camera.fill")
                        }
                        #endif
                        Button { showingRecipes = true } label: {
                            Label("Recipes", systemImage: "book.closed")
                        }
                        Button { showingQuickAdd = true } label: {
                            Label("Quick Add Calories", systemImage: "bolt.fill")
                        }
                        Button { showingManualEntry = true } label: {
                            Label("Manual Entry", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.mTitle3)
                    }
                }
            }
        }
        #if canImport(UIKit)
        .fullScreenCover(isPresented: $showingScanner) {
            ScannerView()
        }
        .fullScreenCover(isPresented: $showingPhotoCapture) {
            PhotoCaptureView(
                source: .camera,
                onCapture: { image in
                    showingPhotoCapture = false
                    capturedPhoto = CapturedPhoto(image: image)
                },
                onCancel: { showingPhotoCapture = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $capturedPhoto) { photo in
            AIEstimateSheet(image: photo.image)
        }
        #endif
        .sheet(isPresented: $showingManualEntry) {
            ManualFoodForm()
        }
        .sheet(isPresented: $showingCloseGap) {
            CloseGapView()
        }
        .sheet(isPresented: $showingSearch) {
            SearchView(initialQuery: prefilledSearchQuery)
        }
        .sheet(isPresented: $showingRecipes) {
            RecipesView()
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickAddSheet()
        }
        .sheet(item: $editingEntry) { entry in
            EditLogEntrySheet(entry: entry)
        }
        .sheet(item: $editingQuickAddEntry) { entry in
            QuickAddSheet(editingEntry: entry)
        }
        .confirmationDialog(
            "Copy \(copyingMealType?.displayName ?? "meal") to…",
            isPresented: .init(
                get: { copyingMealType != nil },
                set: { if !$0 { copyingMealType = nil } }
            ),
            titleVisibility: .visible
        ) {
            if !isToday {
                Button("Today") { copyMeal(to: Date()) }
            }
            Button("Tomorrow") {
                if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) {
                    copyMeal(to: tomorrow)
                }
            }
            Button("Pick a date…") {
                copyTargetDate = Date()
                showCopyDatePicker = true
            }
            Button("Cancel", role: .cancel) { copyingMealType = nil }
        }
        .sheet(isPresented: $showCopyDatePicker) {
            NavigationStack {
                DatePicker("Copy to", selection: $copyTargetDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Pick a date")
                    #if canImport(UIKit)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showCopyDatePicker = false
                                copyingMealType = nil
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Copy") {
                                showCopyDatePicker = false
                                copyMeal(to: copyTargetDate)
                            }
                            .bold()
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .overlay(alignment: .bottom) {
            if let message = toastMessage {
                Text(message)
                    .font(.mSubheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Capsule().fill(Color.mAccent))
                    .padding(.bottom, Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastMessage != nil)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && isToday {
                Task {
                    todayStepCount = try? await HealthKitService.shared.stepCount(forDate: Date())
                }
            }
        }
    }

    private var titleForDate: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    private var emptyStateMessage: String {
        if isToday {
            return "No meals logged today.\nScan, snap, or add manually."
        }
        return "No meals logged on this day."
    }

    private func handleDeepLink(_ link: BalanceFlag.DeepLink) {
        switch link {
        case .closeGap:
            showingCloseGap = true
        case .search(let query):
            prefilledSearchQuery = query
            showingSearch = true
        }
    }

    private func stepDay(by offset: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: offset, to: date) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            date = newDate
        }
        Haptics.selectionChanged()
    }

    private func copyMeal(to destDate: Date) {
        guard let mealType = copyingMealType else { return }
        let repo = FoodRepository(modelContext: modelContext)
        let count = repo.copyMeal(from: date, to: destDate, mealType: mealType)
        copyingMealType = nil

        let destName = destinationLabel(for: destDate)
        showToast("\(mealType.displayName) copied to \(destName) (\(count) items)")
        Haptics.logFood()
    }

    private func copyYesterdaysMeals() {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) else { return }
        let repo = FoodRepository(modelContext: modelContext)
        let count = repo.copyAllMeals(from: yesterday, to: date)

        showToast("Copied \(count) items from yesterday")
        Haptics.logFood()
    }

    private func destinationLabel(for destDate: Date) -> String {
        if Calendar.current.isDateInToday(destDate) { return "today" }
        if Calendar.current.isDateInTomorrow(destDate) { return "tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: destDate)
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }

    @ViewBuilder
    private func macroRingsSection(profile: UserProfile) -> some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                MacroRing(
                    label: "Calories",
                    current: dailyTotals.calories,
                    target: profile.calorieTarget,
                    unit: "cal",
                    isOverBad: true
                )
                MacroRing(
                    label: "Protein",
                    current: dailyTotals.proteinG,
                    target: profile.proteinTargetG,
                    unit: "g",
                    isOverBad: false
                )
                MacroRing(
                    label: "Carbs",
                    current: dailyTotals.carbsG,
                    target: profile.carbTargetG,
                    unit: "g",
                    isOverBad: false
                )
                MacroRing(
                    label: "Fat",
                    current: dailyTotals.fatG,
                    target: profile.fatTargetG,
                    unit: "g",
                    isOverBad: true
                )
            }

            if isToday {
                Divider()
                stepsRow(profile: profile)
                goalLabel(profile: profile)
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                .fill(Color.mBgSecondary)
        )
        .task(id: isToday) {
            guard isToday else { return }
            todayStepCount = try? await HealthKitService.shared.stepCount(forDate: Date())
        }
    }

    @ViewBuilder
    private func stepsRow(profile: UserProfile) -> some View {
        HStack {
            Image(systemName: "figure.walk")
                .foregroundStyle(Color.mAccent)
                .frame(width: 20)
            Text("Steps")
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
            Spacer()
            if let steps = todayStepCount {
                let target = profile.dailyStepTarget
                let fraction = min(Double(steps) / Double(target), 1.0)
                Text("\(steps.formatted()) / \(target.formatted())")
                    .font(.mCaption)
                    .foregroundStyle(fraction >= 1.0 ? Color.mOnTarget : Color.mTextPrimary)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
            }
        }
    }

    @ViewBuilder
    private func goalLabel(profile: UserProfile) -> some View {
        if let goal = profile.currentGoal, goal.isActive {
            let targetStr: String = {
                if let tw = goal.targetWeightLb {
                    return "\(String(format: "%.0f", tw)) lb"
                } else if let tbf = goal.targetBodyFatPct {
                    return "\(String(format: "%.0f", tbf))% BF"
                }
                return "goal"
            }()
            let dateStr = goal.targetDate.formatted(.dateTime.month(.abbreviated).day())
            NavigationLink(destination: MeView()) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "target")
                        .font(.system(size: 10))
                    Text("Targets: Cut to \(targetStr) by \(dateStr)")
                        .font(.system(.caption2, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                }
                .foregroundStyle(Color.mAccent.opacity(0.8))
            }
            .buttonStyle(.plain)
        } else {
            Text("Targets: Manual")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Color.mTextTertiary)
        }
    }

    @ViewBuilder
    private var mealSections: some View {
        ForEach(MealType.allCases) { mealType in
            let entries = dayEntries.filter { $0.mealType == mealType }
            if !entries.isEmpty {
                MealSectionView(
                    mealType: mealType,
                    entries: entries,
                    onDelete: { entry in
                        let repo = FoodRepository(modelContext: modelContext)
                        repo.deleteEntry(entry)
                    },
                    onEdit: { entry in
                        if entry.isQuickAdd {
                            editingQuickAddEntry = entry
                        } else {
                            editingEntry = entry
                        }
                    },
                    onCopyMeal: {
                        copyingMealType = mealType
                    }
                )
            }
        }
    }
}
