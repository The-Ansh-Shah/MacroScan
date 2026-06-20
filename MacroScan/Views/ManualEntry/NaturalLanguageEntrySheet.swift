import SwiftUI
import SwiftData

struct NaturalLanguageEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    @State private var text: String = ""
    @State private var parsedFoods: [Food] = []
    @State private var selectedMealType: MealType = .lunch
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingConfirm = false
    @State private var suggestions: [String] = []
    @State private var searchTask: Task<Void, Never>? = nil

    private let fatSecretAPI = FatSecretAPI()
    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.md) {
                inputSection
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                Spacer()
            }
            .padding(Spacing.md)
            .navigationTitle("Search Food")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.sheetDismissed()
                        dismiss()
                    }
                }
            }
            .onAppear { guessMealType() }
            .sheet(isPresented: $showingConfirm) {
                NaturalLanguageConfirmSheet(
                    foods: parsedFoods,
                    mealType: selectedMealType,
                    onBack: { showingConfirm = false },
                    onDismissAll: { showingConfirm = false; dismiss() }
                )
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("What did you eat?")
                .font(.mHeadline)
                .foregroundStyle(Color.mTextPrimary)

            TextField("e.g. chicken burrito, greek yogurt…", text: $text)
                .font(.mBody)
                .padding(Spacing.sm)
                .background(Color.mBgSecondary, in: RoundedRectangle(cornerRadius: 10))
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .onChange(of: text) { _, newValue in
                    errorMessage = nil
                    searchTask?.cancel()
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.count >= 2 else {
                        suggestions = []
                        return
                    }
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        guard !Task.isCancelled else { return }
                        await fetchSuggestions(query: trimmed)
                    }
                }

            if !suggestions.isEmpty && !isLoading {
                suggestionsDropdown
            } else if !isLoading && text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                Text("No results")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
                    .padding(.vertical, Spacing.xs)
            }

            if isLoading {
                HStack(spacing: Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Searching…")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                }
                .padding(.vertical, Spacing.xs)
            }

            Picker("Meal", selection: $selectedMealType) {
                ForEach(MealType.allCases) { type in
                    Label(type.displayName, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedMealType) { _, _ in
                Haptics.selectionChanged()
            }

            Text("Powered by FatSecret")
                .font(.mCaption)
                .foregroundStyle(Color.mTextTertiary)
        }
    }

    private var suggestionsDropdown: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                Button {
                    Task { await selectSuggestion(suggestion) }
                } label: {
                    HStack {
                        Text(suggestion)
                            .font(.mBody)
                            .foregroundStyle(Color.mTextPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.mCaption)
                            .foregroundStyle(Color.mTextTertiary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: DesignConstants.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < suggestions.count - 1 {
                    Divider().padding(.leading, Spacing.sm)
                }
            }
        }
        .background(Color.mBgSecondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.mApproaching)
            Text(message)
                .font(.mCaption)
                .foregroundStyle(Color.mTextSecondary)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mApproaching.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    @MainActor
    private func fetchSuggestions(query: String) async {
        print("[Autocomplete] fetching for query='\(query)'")
        do {
            let results = try await fatSecretAPI.autocomplete(query: query)
            print("[Autocomplete] got \(results.count) suggestions: \(results)")
            suggestions = results
        } catch {
            print("[Autocomplete] error: \(error)")
            suggestions = []
        }
    }

    @MainActor
    private func selectSuggestion(_ suggestion: String) async {
        text = suggestion
        suggestions = []
        isLoading = true
        errorMessage = nil

        do {
            incrementFatSecretCounter()
            let foods = try await fatSecretAPI.search(query: suggestion)
            guard !foods.isEmpty else {
                errorMessage = "No results found for \"\(suggestion)\". Try a different term."
                isLoading = false
                return
            }
            parsedFoods = foods
            isLoading = false
            showingConfirm = true
        } catch let error as FatSecretAPI.FatSecretError {
            isLoading = false
            switch error {
            case .rateLimited:
                handleRateLimited()
                errorMessage = "FatSecret daily limit reached. Try again tomorrow."
            case .missingProxyURL:
                errorMessage = "FatSecret proxy URL not configured in Secrets.plist."
            case .authFailed:
                errorMessage = "FatSecret authentication failed. Check proxy credentials."
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            isLoading = false
            errorMessage = "Something went wrong. Check your connection and try again."
        }
    }

    private func incrementFatSecretCounter() {
        guard let profile else { return }
        if let resetAt = profile.fatSecretCallsResetAt,
           !Calendar.current.isDateInToday(resetAt) {
            profile.fatSecretCallsToday = 0
        }
        profile.fatSecretCallsToday += 1
        profile.fatSecretCallsResetAt = Date()
    }

    private func handleRateLimited() {
        guard let profile else { return }
        profile.fatSecretCallsToday = 5000
        profile.fatSecretCallsResetAt = Date()
        Haptics.warning()
    }

    private func guessMealType() {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: selectedMealType = .breakfast
        case 11..<15: selectedMealType = .lunch
        case 15..<21: selectedMealType = .dinner
        default: selectedMealType = .snack
        }
    }

}

// MARK: - Confirm Sheet

private struct NaturalLanguageConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss

    let foods: [Food]
    let mealType: MealType
    let onBack: () -> Void
    let onDismissAll: () -> Void

    @State private var selectedFood: Food? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(foods.enumerated()), id: \.offset) { _, food in
                        Button {
                            selectedFood = food
                        } label: {
                            foodRow(food)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(foods.count) result\(foods.count == 1 ? "" : "s") — tap to customize & log")
                }
            }
            .navigationTitle("Select Food")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        onBack()
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedFood) { food in
                ScanResultSheet(food: food, afterLog: onDismissAll)
            }
        }
    }

    @ViewBuilder
    private func foodRow(_ food: Food) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(food.name)
                    .font(.mBody)
                    .foregroundStyle(Color.mTextPrimary)
                HStack(spacing: Spacing.xs) {
                    if let brand = food.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.mCaption)
                            .foregroundStyle(Color.mTextSecondary)
                    }
                    Text("\(Int(food.servingSizeGrams))g")
                        .font(.mCaption)
                        .foregroundStyle(Color.mTextTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text("\(Int(food.calories)) cal")
                    .font(.mBody)
                    .foregroundStyle(Color.mTextPrimary)
                Text("\(Int(food.proteinG))g P")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextSecondary)
            }
        }
        .frame(minHeight: DesignConstants.minTapTarget)
    }
}
