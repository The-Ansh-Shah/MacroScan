import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: UserProfile
    let foodCount: Int
    let entryCount: Int

    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    @State private var showingDocumentPicker = false
    @State private var isExporting = false
    @State private var exportErrorMessage: String?
    @State private var importResultMessage: String?
    @State private var showingExportError = false
    @State private var showingImportResult = false

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

                Button {
                    exportData()
                } label: {
                    HStack {
                        Label(isExporting ? "Exporting…" : "Export data", systemImage: "square.and.arrow.up")
                            .font(.mBody)
                        Spacer()
                    }
                }
                .disabled(isExporting)

                Button {
                    showingDocumentPicker = true
                } label: {
                    Label("Import from file", systemImage: "square.and.arrow.down")
                        .font(.mBody)
                }

                Text("Export creates a complete backup of your foods, logs, recipes, and measurements. Import merges data from a previous export — existing entries are kept, new ones added.")
                    .font(.mCaption)
                    .foregroundStyle(Color.mTextTertiary)
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
        .alert("Export Error", isPresented: $showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .alert("Import Complete", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResultMessage ?? "")
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showingDocumentPicker) {
            #if canImport(UIKit)
            DocumentPicker { url in
                importData(from: url)
                showingDocumentPicker = false
            }
            #endif
        }
    }

    // MARK: - Data helpers

    private func exportData() {
        isExporting = true
        Task {
            do {
                let url = try DataExportService(modelContext: modelContext).exportAll()
                await MainActor.run {
                    exportURL = url
                    isExporting = false
                    showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportErrorMessage = error.localizedDescription
                    showingExportError = true
                }
            }
        }
    }

    private func importData(from url: URL) {
        Task {
            do {
                let result = try DataExportService(modelContext: modelContext).importFrom(url)
                await MainActor.run {
                    importResultMessage = result.summary
                    showingImportResult = true
                }
            } catch {
                await MainActor.run {
                    importResultMessage = error.localizedDescription
                    showingImportResult = true
                }
            }
        }
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

// MARK: - Share Sheet (Phase 40)

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
#endif

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
