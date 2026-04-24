import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            if let profile {
                SettingsFormView(
                    profile: profile,
                    foodCount: foodCount,
                    entryCount: entryCount
                )
            } else {
                EmptyStateView(
                    symbol: "gearshape",
                    message: "Loading profile..."
                )
            }
        }
    }

    private var foodCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Food>())) ?? 0
    }

    private var entryCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<LogEntry>())) ?? 0
    }
}

// MARK: - Settings Form

/// Extracted so we can use @Bindable on the SwiftData @Model
private struct SettingsFormView: View {
    @Bindable var profile: UserProfile
    let foodCount: Int
    let entryCount: Int

    private var profileSummary: String {
        var parts: [String] = []
        if let h = profile.heightIn {
            let feet = Int(h) / 12
            let inches = Int(h) % 12
            parts.append("\(feet)'\(inches)\"")
        }
        if let age = profile.ageYears { parts.append("\(age)") }
        if profile.biologicalSex != .unspecified { parts.append(profile.biologicalSex.displayName) }
        parts.append(profile.activityLevel.displayName)
        return parts.isEmpty ? "Not set" : parts.joined(separator: ", ")
    }

    var body: some View {
        Form {
            Section("Profile") {
                NavigationLink {
                    ProfileEditorSheet(profile: profile)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edit profile")
                            .font(.mBody)
                        Text(profileSummary)
                            .font(.mCaption)
                            .foregroundStyle(Color.mTextSecondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Body Weight") {
                HStack {
                    Text("Weight")
                        .font(.mBody)
                    Spacer()
                    TextField("lbs", value: $profile.bodyWeightLb, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        #if canImport(UIKit)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("lbs")
                        .font(.mBody)
                        .foregroundStyle(Color.mTextSecondary)
                }

                if let weight = profile.bodyWeightLb, weight > 0,
                   profile.currentGoal?.isActive != true {
                    Button("Auto-set protein from weight") {
                        profile.proteinTargetG = weight * profile.dietGoal.proteinMultiplier
                        Haptics.logFood()
                    }
                    .font(.mBody)
                }
            }

            Section("Diet Preferences") {
                Toggle("Vegetarian", isOn: $profile.isVegetarian)
                    .font(.mBody)

                NavigationLink {
                    ExclusionsEditor(profile: profile)
                } label: {
                    HStack {
                        Text("Excluded Ingredients")
                            .font(.mBody)
                        Spacer()
                        Text(profile.excludedIngredients.joined(separator: ", "))
                            .font(.mCaption)
                            .foregroundStyle(Color.mTextSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Section("Library") {
                NavigationLink {
                    RecipesView()
                } label: {
                    Label("My Recipes", systemImage: "book.closed")
                        .font(.mBody)
                }
            }

            Section("Data") {
                HStack {
                    Text("Foods in library")
                        .font(.mBody)
                    Spacer()
                    Text("\(foodCount)")
                        .font(.mBody)
                        .foregroundStyle(Color.mTextSecondary)
                }
                HStack {
                    Text("Total log entries")
                        .font(.mBody)
                    Spacer()
                    Text("\(entryCount)")
                        .font(.mBody)
                        .foregroundStyle(Color.mTextSecondary)
                }
            }

            Section("Apple Health") {
                HealthKitSettingsSection()
            }

            Section("Credits") {
                Link(destination: URL(string: "https://www.fatsecret.com")!) {
                    HStack {
                        Text("Powered by FatSecret")
                            .font(.mBody)
                            .foregroundStyle(Color.mTextPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.mCaption)
                            .foregroundStyle(Color.mTextTertiary)
                    }
                }
            }

            Section("AI Usage") {
                HStack {
                    Text("Total analyses").font(.mBody)
                    Spacer()
                    Text("\(profile.aiCallsTotal)")
                        .font(.mBody)
                        .foregroundStyle(Color.mTextSecondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Quota errors").font(.mBody)
                    Spacer()
                    Text("\(profile.aiQuotaErrorsTotal)")
                        .font(.mBody)
                        .foregroundStyle(profile.aiQuotaErrorsTotal > 0 ? Color.mApproaching : Color.mTextSecondary)
                        .monospacedDigit()
                }
                if let lastErr = profile.aiLastErrorAt {
                    HStack {
                        Text("Last error").font(.mBody)
                        Spacer()
                        Text(lastErr, style: .relative)
                            .font(.mBody)
                            .foregroundStyle(Color.mTextSecondary)
                    }
                }
            }
        }
        .keyboardDoneButton()
        .navigationTitle("Settings")
    }

}

// MARK: - HealthKit Settings

struct HealthKitSettingsSection: View {
    @State private var isAvailable = false
    @State private var isConnected = false
    @State private var isRequesting = false

    var body: some View {
        Group {
            if !isAvailable {
                Label("Not available on this device", systemImage: "heart.slash")
                    .font(.mBody)
                    .foregroundStyle(Color.mTextSecondary)
            } else if isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.mBody)
                    .foregroundStyle(Color.mOnTarget)
                Text("Reads: weight, body fat, active energy\nWrites: nutrition, body measurements")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextSecondary)
                Button("Re-request Permissions") {
                    requestAccess()
                }
                .font(.mBody)
            } else {
                Button {
                    requestAccess()
                } label: {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text(isRequesting ? "Requesting…" : "Connect Apple Health")
                            .font(.mBody)
                    }
                }
                .disabled(isRequesting)
            }
        }
        .task {
            let available = await HealthKitService.shared.isAvailable
            await MainActor.run { isAvailable = available }
        }
    }

    private func requestAccess() {
        isRequesting = true
        Task {
            try? await HealthKitService.shared.requestAuthorization()
            await MainActor.run {
                isConnected = true
                isRequesting = false
            }
        }
    }
}

// MARK: - Exclusions Editor

struct ExclusionsEditor: View {
    let profile: UserProfile
    @State private var newIngredient: String = ""

    var body: some View {
        List {
            Section {
                ForEach(profile.excludedIngredients, id: \.self) { ingredient in
                    Text(ingredient)
                        .font(.mBody)
                }
                .onDelete { indexSet in
                    profile.excludedIngredients.remove(atOffsets: indexSet)
                }
            }

            Section {
                HStack {
                    TextField("Add ingredient...", text: $newIngredient)
                        .font(.mBody)
                    Button {
                        let trimmed = newIngredient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        guard !trimmed.isEmpty, !profile.excludedIngredients.contains(trimmed) else { return }
                        profile.excludedIngredients.append(trimmed)
                        newIngredient = ""
                        Haptics.logFood()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.mAccent)
                    }
                    .disabled(newIngredient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle("Exclusions")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
