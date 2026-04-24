import SwiftUI
import SwiftData

struct DiningView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DiningMenu.date, order: .reverse)
    private var cachedMenus: [DiningMenu]

    @Query private var profiles: [UserProfile]
    @Query(sort: \LogEntry.loggedAt, order: .reverse)
    private var allEntries: [LogEntry]

    @State private var selectedLocation: DiningLocation = .crossroads
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingOptimizer = false

    private let menuService = DiningMenuService()

    private var profile: UserProfile? { profiles.first }

    private var todayMenus: [DiningMenu] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: startOfToday)!
        return cachedMenus.filter { $0.date >= startOfToday && $0.date < endOfToday && $0.location == selectedLocation }
    }

    private var todayTotals: ScaledMacros {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return allEntries
            .filter { $0.loggedAt >= startOfToday }
            .reduce(ScaledMacros.zero) { $0 + $1.scaledMacros }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Location picker
                Picker("Location", selection: $selectedLocation) {
                    ForEach(DiningLocation.allCases) { location in
                        Text(location.displayName).tag(location)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .onChange(of: selectedLocation) { _, _ in
                    Haptics.selectionChanged()
                }

                if isLoading {
                    Spacer()
                    ProgressView("Loading menus...")
                        .font(.mBody)
                    Spacer()
                } else if todayMenus.isEmpty {
                    Spacer()
                    EmptyStateView(
                        symbol: "building.2",
                        message: "No menu data available.\nPull to refresh or check back later.",
                        buttonTitle: "Refresh",
                        action: { Task { await loadMenus() } }
                    )
                    Spacer()
                } else {
                    menuList
                }
            }
            .navigationTitle("Dining")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingOptimizer = true
                    } label: {
                        Label("Optimize", systemImage: "wand.and.stars")
                    }
                }
            }
            .refreshable {
                await loadMenus()
            }
            .task {
                if todayMenus.isEmpty {
                    await loadMenus()
                }
            }
            .sheet(isPresented: $showingOptimizer) {
                if let profile {
                    OptimizerView(
                        menus: todayMenus,
                        currentTotals: todayTotals,
                        profile: profile
                    )
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var menuList: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                ForEach(todayMenus, id: \.mealPeriod) { menu in
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(menu.mealPeriod.capitalized)
                            .font(.mHeadline)
                            .foregroundStyle(Color.mTextPrimary)

                        ForEach(menu.items) { item in
                            diningItemRow(item: item)
                        }
                    }
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius)
                            .fill(Color.mBgSecondary)
                    )
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    @ViewBuilder
    private func diningItemRow(item: DiningMenuItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.name)
                    .font(.mBody)
                    .foregroundStyle(Color.mTextPrimary)
                Text(item.category)
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextSecondary)
            }
            Spacer()
            if let cal = item.calories, let pro = item.proteinG {
                VStack(alignment: .trailing, spacing: Spacing.xs) {
                    Text("\(Int(cal)) cal")
                        .font(.mSubheadline)
                        .foregroundStyle(Color.mTextPrimary)
                    Text("\(Int(pro))g protein")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextSecondary)
                }
            }
        }
        .padding(.vertical, Spacing.xs)
    }

    private func loadMenus() async {
        isLoading = true
        errorMessage = nil
        do {
            _ = try await menuService.fetchMenus(forDate: Date(), modelContext: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
