import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit

/// Presents the AI estimate after a photo capture.
/// Handles loading, error, and editable-confirm states. Logs on save.
struct AIEstimateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]

    let image: UIImage

    @State private var phase: Phase = .analyzing
    @State private var estimate: AIVisionService.EstimatedFood?
    @State private var errorMessage: String?
    @State private var progressLabel: String = "Analyzing…"
    @State private var showingFallback = false
    @State private var lastErrorWasQuota = false

    // Editable fields (populated once estimate arrives)
    @State private var name = ""
    @State private var gramsEaten = ""
    @State private var calories = ""
    @State private var proteinG = ""
    @State private var carbsG = ""
    @State private var fatG = ""
    @State private var fiberG = ""
    @State private var selectedMealType: MealType = .lunch

    private let vision = AIVisionService()

    enum Phase { case analyzing, ready, errored }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .analyzing: analyzingView
                case .ready: readyView
                case .errored: errorView
                }
            }
            .navigationTitle("Meal Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Haptics.sheetDismissed()
                        dismiss()
                    }
                }
                if phase == .ready {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Log") { saveAndLog() }
                            .bold()
                            .disabled(!isValid)
                    }
                }
            }
            .task { await analyze() }
            .sheet(isPresented: $showingFallback, onDismiss: { dismiss() }) {
                AIFallbackSheet(image: image, quotaError: lastErrorWasQuota)
            }
        }
    }

    // MARK: - Phase views

    private var analyzingView: some View {
        VStack(spacing: Spacing.lg) {
            thumbnail
            ProgressView()
                .controlSize(.large)
            Text(progressLabel)
                .font(.mBody)
                .foregroundStyle(Color.mTextSecondary)
                .animation(.easeInOut, value: progressLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xl)
    }

    private var errorView: some View {
        VStack(spacing: Spacing.md) {
            thumbnail
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.mOver)
            Text(errorMessage ?? "Could not analyze this photo.")
                .font(.mBody)
                .foregroundStyle(Color.mTextSecondary)
                .multilineTextAlignment(.center)
            PrimaryButton("Try Again", icon: "arrow.clockwise") {
                Task { await analyze() }
            }
            .frame(maxWidth: 220)

            Button("Log manually instead") {
                showingFallback = true
            }
            .font(.mBody)
            .foregroundStyle(Color.mAccent)
        }
        .padding(Spacing.xl)
    }

    private var readyView: some View {
        Form {
            Section {
                HStack(spacing: Spacing.md) {
                    thumbnail.frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        TextField("Name", text: $name)
                            .font(.mHeadline)
                        if let estimate {
                            confidenceBadge(confidence: estimate.confidence)
                        }
                    }
                }
            }

            if let estimate, !estimate.warnings.isEmpty {
                Section {
                    ForEach(estimate.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.mApproaching)
                            .font(.mSubheadline)
                    }
                }
            }

            Section("Portion") {
                numberField("Grams eaten", text: $gramsEaten)
            }

            Section("Nutrition (estimated)") {
                numberField("Calories", text: $calories)
                numberField("Protein (g)", text: $proteinG)
                numberField("Carbs (g)", text: $carbsG)
                numberField("Fat (g)", text: $fatG)
                numberField("Fiber (g)", text: $fiberG)
            }

            Section("Meal") {
                Picker("Meal", selection: $selectedMealType) {
                    ForEach(MealType.allCases) { type in
                        Label(type.displayName, systemImage: type.icon).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedMealType) { _, _ in Haptics.selectionChanged() }
            }
        }
    }

    // MARK: - Sub-views

    private var thumbnail: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: 220, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: DesignConstants.cardCornerRadius))
    }

    @ViewBuilder
    private func confidenceBadge(confidence: Double) -> some View {
        let (color, label, icon): (Color, String, String) = {
            switch confidence {
            case 0.8...: return (.mOnTarget, "High confidence", "checkmark.seal.fill")
            case 0.5..<0.8: return (.mApproaching, "Medium confidence", "questionmark.circle.fill")
            default: return (.mOver, "Low confidence — verify", "exclamationmark.triangle.fill")
            }
        }()
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
            Text(label)
                .font(.mCaption)
            Text("\(Int(confidence * 100))%")
                .font(.mCaption)
                .monospacedDigit()
        }
        .foregroundStyle(color)
    }

    @ViewBuilder
    private func numberField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.mBody)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    // MARK: - Logic

    private var isValid: Bool {
        !name.isEmpty &&
        (Double(gramsEaten) ?? 0) > 0 &&
        Double(calories) != nil &&
        Double(proteinG) != nil &&
        Double(carbsG) != nil &&
        Double(fatG) != nil
    }

    private func analyze() async {
        phase = .analyzing
        errorMessage = nil
        progressLabel = "Analyzing…"
        lastErrorWasQuota = false

        guard let jpeg = ImageResizing.resizeForUpload(image) else {
            await MainActor.run {
                errorMessage = "Could not process image."
                phase = .errored
            }
            return
        }
        let base64 = ImageResizing.base64Encode(jpeg)

        let profile = profiles.first
        let exclusions = profile?.excludedIngredients ?? ["eggs", "mushrooms"]
        let vegetarian = profile?.isVegetarian ?? true

        // Telemetry increment (best-effort; safe to skip if no profile yet).
        if let profile {
            profile.aiCallsTotal += 1
        }

        do {
            let result = try await vision.analyze(
                imageBase64: base64,
                excludedIngredients: exclusions,
                isVegetarian: vegetarian,
                progress: { label in
                    Task { @MainActor in progressLabel = label }
                }
            )
            await MainActor.run {
                estimate = result
                name = result.name
                gramsEaten = String(Int(result.estimatedGrams))
                calories = String(Int(result.calories))
                proteinG = String(format: "%.1f", result.proteinG)
                carbsG = String(format: "%.1f", result.carbsG)
                fatG = String(format: "%.1f", result.fatG)
                fiberG = String(format: "%.1f", result.fiberG)
                selectedMealType = .currentGuess
                phase = .ready
            }
        } catch {
            await MainActor.run {
                if let aiError = error as? AIVisionService.AIError,
                   AIVisionService.isQuotaError(aiError) {
                    lastErrorWasQuota = true
                    errorMessage = "AI analysis is temporarily rate-limited. This usually resolves within a few minutes."
                    if let profile {
                        profile.aiQuotaErrorsTotal += 1
                        profile.aiLastErrorAt = Date()
                    }
                } else {
                    errorMessage = error.localizedDescription
                }
                phase = .errored
            }
        }
    }

    private func saveAndLog() {
        guard let estimate,
              let grams = Double(gramsEaten),
              let cal = Double(calories),
              let pro = Double(proteinG),
              let carb = Double(carbsG),
              let fat = Double(fatG) else { return }

        // Stored macros on Food represent "one serving" — treat the AI-estimated
        // portion as the serving size so future re-logs scale cleanly.
        let servingGrams = grams

        let food = Food(
            name: name,
            servingSizeGrams: servingGrams,
            calories: cal,
            proteinG: pro,
            carbsG: carb,
            fatG: fat,
            fiberG: Double(fiberG) ?? estimate.fiberG,
            ironMg: estimate.ironMg,
            vitaminDMcg: estimate.vitaminDMcg,
            vitaminB12Mcg: estimate.vitaminB12Mcg,
            source: .aiVision,
            isVegetarian: estimate.isVegetarian,
            containsEggs: estimate.containsEggs,
            containsMushrooms: estimate.containsMushrooms
        )

        let photoData = ImageResizing.resizeForUpload(image, maxDimension: 512, jpegQuality: 0.6)

        let repo = FoodRepository(modelContext: modelContext)
        repo.save(food: food)
        repo.logFood(
            food,
            grams: grams,
            mealType: selectedMealType,
            photoData: photoData,
            aiConfidence: estimate.confidence
        )
        Haptics.logFood()
        dismiss()
    }
}
#endif
