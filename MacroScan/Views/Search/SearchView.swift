import SwiftUI
import SwiftData

/// Live text search for foods — local DB first, FatSecret + OFF remote when local is thin.
/// Debounced 250ms. Tap a result to open `ScanResultSheet` for logging.
struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var initialQuery: String = ""

    @State private var query: String = ""
    @State private var results: [FoodSearchService.Result] = []
    @State private var isSearching = false
    @State private var selectedFood: Food?
    @State private var searchTask: Task<Void, Never>?

    private let offAPI = OpenFoodFactsAPI()
    private let fatSecretAPI = FatSecretAPI()

    private var hasFatSecretResults: Bool {
        results.contains { $0.source == .fatSecret }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField

                if query.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        message: "Search foods by name.\nYour library, FatSecret, and Open Food Facts are checked."
                    )
                } else if isSearching && results.isEmpty {
                    VStack(spacing: Spacing.md) {
                        ProgressView()
                        Text("Searching...")
                            .font(.mCaption)
                            .foregroundStyle(Color.mTextSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    EmptyStateView(
                        symbol: "questionmark.circle",
                        message: "No foods matched \"\(query)\".\nTry a different spelling or add it manually."
                    )
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search Foods")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $selectedFood) { food in
                ScanResultSheet(food: food)
            }
            .onAppear {
                if query.isEmpty, !initialQuery.isEmpty {
                    query = initialQuery
                    debounceSearch(initialQuery)
                }
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.mTextTertiary)
            TextField("e.g. greek yogurt, chalupa, oatmeal", text: $query)
                .font(.mBody)
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .onChange(of: query) { _, newValue in
                    debounceSearch(newValue)
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.mTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.sm)
        .background(Color.mBgSecondary, in: RoundedRectangle(cornerRadius: 10))
        .padding(Spacing.md)
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            List(results) { result in
                Button {
                    handleSelect(result)
                } label: {
                    resultRow(result)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)

            if hasFatSecretResults {
                Text("Powered by FatSecret")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
                    .padding(.vertical, Spacing.xs)
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ result: FoodSearchService.Result) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: sourceIcon(result.source))
                .foregroundStyle(sourceColor(result.source))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(result.food.name)
                    .font(.mBody)
                    .foregroundStyle(Color.mTextPrimary)
                    .lineLimit(1)
                HStack(spacing: Spacing.xs) {
                    if let brand = result.food.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.mCaption)
                            .foregroundStyle(Color.mTextSecondary)
                    }
                    Text(macroSummary(result.food))
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.mCaption)
                .foregroundStyle(Color.mTextTertiary)
        }
        .frame(minHeight: DesignConstants.minTapTarget)
        .contentShape(Rectangle())
    }

    private func macroSummary(_ food: Food) -> String {
        let serving = food.servingSizeGrams > 0 ? food.servingSizeGrams : 100
        let scale = 100.0 / serving
        let cal = Int(food.calories * scale)
        let pro = Int(food.proteinG * scale)
        return "\(cal) cal · \(pro)g P / 100g"
    }

    private func sourceIcon(_ source: FoodSearchService.Source) -> String {
        switch source {
        case .localFavorite: return "star.fill"
        case .localFrequent: return "bookmark.fill"
        case .localOccasional: return "tray"
        case .fatSecret: return "fork.knife"
        case .off: return "globe"
        }
    }

    private func sourceColor(_ source: FoodSearchService.Source) -> Color {
        switch source {
        case .localFavorite: return .mApproaching
        case .localFrequent, .localOccasional: return .mAccent
        case .fatSecret: return .mOnTarget
        case .off: return .mTextSecondary
        }
    }

    private func handleSelect(_ result: FoodSearchService.Result) {
        let food = result.food
        if (result.source == .off || result.source == .fatSecret), !foodAlreadyExists(food) {
            modelContext.insert(food)
        }
        selectedFood = food
    }

    private func foodAlreadyExists(_ food: Food) -> Bool {
        if let barcode = food.barcode, !barcode.isEmpty {
            let repo = FoodRepository(modelContext: modelContext)
            return repo.findByBarcode(barcode) != nil
        }
        return false
    }

    private func debounceSearch(_ text: String) {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await runSearch(text)
        }
    }

    private func runSearch(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        let suppressed = isFatSecretSuppressed()
        let service = FoodSearchService(
            modelContext: modelContext,
            offAPI: offAPI,
            fatSecretAPI: fatSecretAPI,
            fatSecretSuppressed: suppressed
        )
        let hits = await service.search(query: text)
        guard !Task.isCancelled else { return }
        results = hits
        isSearching = false
    }

    private func isFatSecretSuppressed() -> Bool {
        let repo = FoodRepository(modelContext: modelContext)
        guard let profile = repo.userProfile() else { return false }
        if let resetAt = profile.fatSecretCallsResetAt,
           !Calendar.current.isDateInToday(resetAt) {
            profile.fatSecretCallsToday = 0
            profile.fatSecretCallsResetAt = nil
        }
        return profile.fatSecretCallsToday >= 4500
    }
}
