import Foundation
import SwiftData

// MARK: - Export Payload

struct ExportPayload: Codable {
    var version: Int = 1
    var exportedAt: Date
    var appVersion: String
    var userProfile: UserProfileDTO?
    var foods: [FoodDTO]
    var logEntries: [LogEntryDTO]
    var bodyMeasurements: [BodyMeasurementDTO]
    var waterEntries: [WaterEntryDTO]
    var recipes: [RecipeDTO]
    var weightGoals: [WeightGoalDTO]
}

// MARK: - DTOs

struct FoodDTO: Codable {
    var exportID: UUID
    var name: String
    var brand: String?
    var barcode: String?
    var servingSizeGrams: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var ironMg: Double
    var vitaminDMcg: Double
    var vitaminB12Mcg: Double
    var sourceRaw: String
    var isVegetarian: Bool
    var containsEggs: Bool
    var containsMushrooms: Bool
    var isFavorite: Bool
    var ingredients: [String]
    var timesLogged: Int
    var lastLoggedAt: Date?
    var createdAt: Date
    var userVerified: Bool
    var lastVerifiedAt: Date?

    init(_ food: Food) {
        self.exportID = food.exportID
        self.name = food.name
        self.brand = food.brand
        self.barcode = food.barcode
        self.servingSizeGrams = food.servingSizeGrams
        self.calories = food.calories
        self.proteinG = food.proteinG
        self.carbsG = food.carbsG
        self.fatG = food.fatG
        self.fiberG = food.fiberG
        self.ironMg = food.ironMg
        self.vitaminDMcg = food.vitaminDMcg
        self.vitaminB12Mcg = food.vitaminB12Mcg
        self.sourceRaw = food.sourceRaw
        self.isVegetarian = food.isVegetarian
        self.containsEggs = food.containsEggs
        self.containsMushrooms = food.containsMushrooms
        self.isFavorite = food.isFavorite
        self.ingredients = food.ingredients
        self.timesLogged = food.timesLogged
        self.lastLoggedAt = food.lastLoggedAt
        self.createdAt = food.createdAt
        self.userVerified = food.userVerified
        self.lastVerifiedAt = food.lastVerifiedAt
    }

    func toModel() -> Food {
        let food = Food(
            name: name,
            brand: brand,
            barcode: barcode,
            servingSizeGrams: servingSizeGrams,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fiberG: fiberG,
            ironMg: ironMg,
            vitaminDMcg: vitaminDMcg,
            vitaminB12Mcg: vitaminB12Mcg,
            source: FoodSource(rawValue: sourceRaw) ?? .manual,
            isVegetarian: isVegetarian,
            containsEggs: containsEggs,
            containsMushrooms: containsMushrooms,
            isFavorite: isFavorite,
            ingredients: ingredients
        )
        food.exportID = exportID
        food.timesLogged = timesLogged
        food.lastLoggedAt = lastLoggedAt
        food.createdAt = createdAt
        food.userVerified = userVerified
        food.lastVerifiedAt = lastVerifiedAt
        return food
    }
}

struct LogEntryDTO: Codable {
    var exportID: UUID
    var foodExportID: UUID?
    var gramsEaten: Double
    var servingsEaten: Double?
    var mealTypeRaw: String
    var loggedAt: Date
    var photoData: Data?
    var aiConfidence: Double?
    var notes: String?
    var quickAddCalories: Double?
    var quickAddProteinG: Double?
    var quickAddCarbsG: Double?
    var quickAddFatG: Double?
    var quickAddFiberG: Double?
    var quickAddName: String?

    init(_ entry: LogEntry) {
        self.exportID = entry.exportID
        self.foodExportID = entry.food?.exportID
        self.gramsEaten = entry.gramsEaten
        self.servingsEaten = entry.servingsEaten
        self.mealTypeRaw = entry.mealTypeRaw
        self.loggedAt = entry.loggedAt
        self.photoData = entry.photoData
        self.aiConfidence = entry.aiConfidence
        self.notes = entry.notes
        self.quickAddCalories = entry.quickAddCalories
        self.quickAddProteinG = entry.quickAddProteinG
        self.quickAddCarbsG = entry.quickAddCarbsG
        self.quickAddFatG = entry.quickAddFatG
        self.quickAddFiberG = entry.quickAddFiberG
        self.quickAddName = entry.quickAddName
    }

    func toModel(foodMap: [UUID: Food]) -> LogEntry {
        let entry = LogEntry(
            food: foodExportID.flatMap { foodMap[$0] },
            gramsEaten: gramsEaten,
            mealType: MealType(rawValue: mealTypeRaw) ?? .snack,
            loggedAt: loggedAt,
            photoData: photoData,
            aiConfidence: aiConfidence,
            notes: notes
        )
        entry.exportID = exportID
        entry.servingsEaten = servingsEaten
        entry.quickAddCalories = quickAddCalories
        entry.quickAddProteinG = quickAddProteinG
        entry.quickAddCarbsG = quickAddCarbsG
        entry.quickAddFatG = quickAddFatG
        entry.quickAddFiberG = quickAddFiberG
        entry.quickAddName = quickAddName
        return entry
    }
}

struct BodyMeasurementDTO: Codable {
    var exportID: UUID
    var recordedAt: Date
    var weightLb: Double
    var bodyFatPct: Double?
    var waistIn: Double?
    var neckIn: Double?
    var hipIn: Double?
    var bodyFatSourceRaw: String?
    var notes: String?
    var source: String

    init(_ measurement: BodyMeasurement) {
        self.exportID = measurement.exportID
        self.recordedAt = measurement.recordedAt
        self.weightLb = measurement.weightLb
        self.bodyFatPct = measurement.bodyFatPct
        self.waistIn = measurement.waistIn
        self.neckIn = measurement.neckIn
        self.hipIn = measurement.hipIn
        self.bodyFatSourceRaw = measurement.bodyFatSourceRaw
        self.notes = measurement.notes
        self.source = measurement.source
    }

    func toModel() -> BodyMeasurement {
        let m = BodyMeasurement(
            recordedAt: recordedAt,
            weightLb: weightLb,
            bodyFatPct: bodyFatPct,
            waistIn: waistIn,
            neckIn: neckIn,
            hipIn: hipIn,
            bodyFatSource: bodyFatSourceRaw.flatMap { BodyFatSource(rawValue: $0) },
            notes: notes,
            source: source
        )
        m.exportID = exportID
        return m
    }
}

struct WaterEntryDTO: Codable {
    var exportID: UUID
    var recordedAt: Date
    var amountMl: Double
    var source: String

    init(_ entry: WaterEntry) {
        self.exportID = entry.exportID
        self.recordedAt = entry.recordedAt
        self.amountMl = entry.amountMl
        self.source = entry.source
    }

    func toModel() -> WaterEntry {
        let entry = WaterEntry(amountMl: amountMl, recordedAt: recordedAt, source: source)
        entry.exportID = exportID
        return entry
    }
}

struct RecipeIngredientDTO: Codable {
    var foodExportID: UUID?
    var grams: Double
    var order: Int

    init(_ ingredient: RecipeIngredient) {
        self.foodExportID = ingredient.food?.exportID
        self.grams = ingredient.grams
        self.order = ingredient.order
    }
}

struct RecipeDTO: Codable {
    var exportID: UUID
    var name: String
    var notes: String?
    var instructions: String?
    var totalServings: Double
    var ingredients: [RecipeIngredientDTO]
    var createdAt: Date
    var lastUsedAt: Date?
    var timesUsed: Int
    var isFavorite: Bool

    init(_ recipe: Recipe) {
        self.exportID = recipe.exportID
        self.name = recipe.name
        self.notes = recipe.notes
        self.instructions = recipe.instructions
        self.totalServings = recipe.totalServings
        self.ingredients = recipe.ingredients.map(RecipeIngredientDTO.init)
        self.createdAt = recipe.createdAt
        self.lastUsedAt = recipe.lastUsedAt
        self.timesUsed = recipe.timesUsed
        self.isFavorite = recipe.isFavorite
    }

    func toModel(foodMap: [UUID: Food]) -> Recipe {
        let recipe = Recipe(name: name, notes: notes, instructions: instructions ?? "", totalServings: totalServings, isFavorite: isFavorite)
        recipe.exportID = exportID
        recipe.createdAt = createdAt
        recipe.lastUsedAt = lastUsedAt
        recipe.timesUsed = timesUsed
        recipe.ingredients = ingredients.map { dto in
            RecipeIngredient(food: dto.foodExportID.flatMap { foodMap[$0] }, grams: dto.grams, order: dto.order)
        }
        return recipe
    }
}

struct WeightGoalDTO: Codable {
    var exportID: UUID
    var startedAt: Date
    var targetWeightLb: Double?
    var targetBodyFatPct: Double?
    var targetDate: Date
    var isActive: Bool
    var startingWeightLb: Double
    var startingBodyFatPct: Double?

    init(_ goal: WeightGoal) {
        self.exportID = goal.exportID
        self.startedAt = goal.startedAt
        self.targetWeightLb = goal.targetWeightLb
        self.targetBodyFatPct = goal.targetBodyFatPct
        self.targetDate = goal.targetDate
        self.isActive = goal.isActive
        self.startingWeightLb = goal.startingWeightLb
        self.startingBodyFatPct = goal.startingBodyFatPct
    }

    func toModel() -> WeightGoal {
        let goal = WeightGoal(
            startedAt: startedAt,
            targetWeightLb: targetWeightLb,
            targetBodyFatPct: targetBodyFatPct,
            targetDate: targetDate,
            isActive: isActive,
            startingWeightLb: startingWeightLb,
            startingBodyFatPct: startingBodyFatPct
        )
        goal.exportID = exportID
        return goal
    }
}

struct UserProfileDTO: Codable {
    var calorieTarget: Double
    var proteinTargetG: Double
    var carbTargetG: Double
    var fatTargetG: Double
    var fiberTargetG: Double
    var ironTargetMg: Double
    var vitaminDTargetMcg: Double
    var vitaminB12TargetMcg: Double
    var dietGoalRaw: String
    var isVegetarian: Bool
    var excludedIngredients: [String]
    var bodyWeightLb: Double?
    var heightIn: Double?
    var ageYears: Int?
    var biologicalSexRaw: String?
    var activityLevelRaw: String
    var dailyStepTarget: Int
    var dailyWaterTargetMl: Double

    init(_ profile: UserProfile) {
        self.calorieTarget = profile.calorieTarget
        self.proteinTargetG = profile.proteinTargetG
        self.carbTargetG = profile.carbTargetG
        self.fatTargetG = profile.fatTargetG
        self.fiberTargetG = profile.fiberTargetG
        self.ironTargetMg = profile.ironTargetMg
        self.vitaminDTargetMcg = profile.vitaminDTargetMcg
        self.vitaminB12TargetMcg = profile.vitaminB12TargetMcg
        self.dietGoalRaw = profile.dietGoalRaw
        self.isVegetarian = profile.isVegetarian
        self.excludedIngredients = profile.excludedIngredients
        self.bodyWeightLb = profile.bodyWeightLb
        self.heightIn = profile.heightIn
        self.ageYears = profile.ageYears
        self.biologicalSexRaw = profile.biologicalSexRaw
        self.activityLevelRaw = profile.activityLevelRaw
        self.dailyStepTarget = profile.dailyStepTarget
        self.dailyWaterTargetMl = profile.dailyWaterTargetMl
    }
}

// MARK: - Service

@MainActor
struct DataExportService {
    let modelContext: ModelContext

    enum ExportError: Error, LocalizedError {
        case encodingFailed(Error)
        case fileWriteFailed(Error)

        var errorDescription: String? {
            switch self {
            case .encodingFailed(let e): return "Export encoding failed: \(e.localizedDescription)"
            case .fileWriteFailed(let e): return "Could not write export file: \(e.localizedDescription)"
            }
        }
    }

    enum ImportError: Error, LocalizedError {
        case fileReadFailed(Error)
        case invalidFormat
        case versionUnsupported(Int)
        case decodingFailed(Error)

        var errorDescription: String? {
            switch self {
            case .fileReadFailed(let e): return "Could not read file: \(e.localizedDescription)"
            case .invalidFormat: return "File is not a valid MacroScan export."
            case .versionUnsupported(let v): return "Export version \(v) is not supported. Update MacroScan and try again."
            case .decodingFailed(let e): return "Could not decode export: \(e.localizedDescription)"
            }
        }
    }

    struct ImportResult {
        var foodsAdded: Int = 0
        var foodsSkipped: Int = 0
        var logEntriesAdded: Int = 0
        var logEntriesSkipped: Int = 0
        var measurementsAdded: Int = 0
        var measurementsSkipped: Int = 0
        var waterEntriesAdded: Int = 0
        var waterEntriesSkipped: Int = 0
        var recipesAdded: Int = 0
        var recipesSkipped: Int = 0
        var weightGoalsAdded: Int = 0
        var weightGoalsSkipped: Int = 0

        var summary: String {
            var parts: [String] = []
            if foodsAdded > 0 { parts.append("\(foodsAdded) food\(foodsAdded == 1 ? "" : "s")") }
            if logEntriesAdded > 0 { parts.append("\(logEntriesAdded) log entr\(logEntriesAdded == 1 ? "y" : "ies")") }
            if measurementsAdded > 0 { parts.append("\(measurementsAdded) measurement\(measurementsAdded == 1 ? "" : "s")") }
            if waterEntriesAdded > 0 { parts.append("\(waterEntriesAdded) water entr\(waterEntriesAdded == 1 ? "y" : "ies")") }
            if recipesAdded > 0 { parts.append("\(recipesAdded) recipe\(recipesAdded == 1 ? "" : "s")") }
            if weightGoalsAdded > 0 { parts.append("\(weightGoalsAdded) goal\(weightGoalsAdded == 1 ? "" : "s")") }

            let totalSkipped = foodsSkipped + logEntriesSkipped + measurementsSkipped + waterEntriesSkipped + recipesSkipped + weightGoalsSkipped

            if parts.isEmpty {
                return totalSkipped > 0 ? "All \(totalSkipped) entries already existed — nothing new to add." : "No data found in file."
            }
            var msg = "Added \(parts.joined(separator: ", "))."
            if totalSkipped > 0 { msg += " Skipped \(totalSkipped) existing." }
            return msg
        }
    }

    func exportAll() throws -> URL {
        let foods = (try? modelContext.fetch(FetchDescriptor<Food>())) ?? []
        let logEntries = (try? modelContext.fetch(FetchDescriptor<LogEntry>())) ?? []
        let measurements = (try? modelContext.fetch(FetchDescriptor<BodyMeasurement>())) ?? []
        let waterEntries = (try? modelContext.fetch(FetchDescriptor<WaterEntry>())) ?? []
        let recipes = (try? modelContext.fetch(FetchDescriptor<Recipe>())) ?? []
        let weightGoals = (try? modelContext.fetch(FetchDescriptor<WeightGoal>())) ?? []
        let profiles = (try? modelContext.fetch(FetchDescriptor<UserProfile>())) ?? []

        let payload = ExportPayload(
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            userProfile: profiles.first.map(UserProfileDTO.init),
            foods: foods.map(FoodDTO.init),
            logEntries: logEntries.map(LogEntryDTO.init),
            bodyMeasurements: measurements.map(BodyMeasurementDTO.init),
            waterEntries: waterEntries.map(WaterEntryDTO.init),
            recipes: recipes.map(RecipeDTO.init),
            weightGoals: weightGoals.map(WeightGoalDTO.init)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            throw ExportError.encodingFailed(error)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macroscan_\(dateStr).json")
        do {
            try data.write(to: url)
        } catch {
            throw ExportError.fileWriteFailed(error)
        }
        return url
    }

    func importFrom(_ url: URL) throws -> ImportResult {
        let data: Data
        do {
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.fileReadFailed(error)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload: ExportPayload
        do {
            payload = try decoder.decode(ExportPayload.self, from: data)
        } catch {
            throw ImportError.decodingFailed(error)
        }

        guard payload.version == 1 else {
            throw ImportError.versionUnsupported(payload.version)
        }

        var result = ImportResult()

        // Preload existing records and build lookup maps
        let existingFoods = (try? modelContext.fetch(FetchDescriptor<Food>())) ?? []
        var foodMap: [UUID: Food] = Dictionary(uniqueKeysWithValues: existingFoods.map { ($0.exportID, $0) })
        let existingLogIDs = Set((try? modelContext.fetch(FetchDescriptor<LogEntry>()))?.map(\.exportID) ?? [])
        let existingMeasIDs = Set((try? modelContext.fetch(FetchDescriptor<BodyMeasurement>()))?.map(\.exportID) ?? [])
        let existingWaterIDs = Set((try? modelContext.fetch(FetchDescriptor<WaterEntry>()))?.map(\.exportID) ?? [])
        let existingRecipeIDs = Set((try? modelContext.fetch(FetchDescriptor<Recipe>()))?.map(\.exportID) ?? [])
        let existingGoalIDs = Set((try? modelContext.fetch(FetchDescriptor<WeightGoal>()))?.map(\.exportID) ?? [])

        // Import foods first (other entities reference them)
        for dto in payload.foods {
            if foodMap[dto.exportID] != nil {
                result.foodsSkipped += 1
            } else {
                let food = dto.toModel()
                modelContext.insert(food)
                foodMap[dto.exportID] = food
                result.foodsAdded += 1
            }
        }

        for dto in payload.logEntries {
            if existingLogIDs.contains(dto.exportID) {
                result.logEntriesSkipped += 1
            } else {
                modelContext.insert(dto.toModel(foodMap: foodMap))
                result.logEntriesAdded += 1
            }
        }

        for dto in payload.bodyMeasurements {
            if existingMeasIDs.contains(dto.exportID) {
                result.measurementsSkipped += 1
            } else {
                modelContext.insert(dto.toModel())
                result.measurementsAdded += 1
            }
        }

        for dto in payload.waterEntries {
            if existingWaterIDs.contains(dto.exportID) {
                result.waterEntriesSkipped += 1
            } else {
                modelContext.insert(dto.toModel())
                result.waterEntriesAdded += 1
            }
        }

        for dto in payload.recipes {
            if existingRecipeIDs.contains(dto.exportID) {
                result.recipesSkipped += 1
            } else {
                modelContext.insert(dto.toModel(foodMap: foodMap))
                result.recipesAdded += 1
            }
        }

        for dto in payload.weightGoals {
            if existingGoalIDs.contains(dto.exportID) {
                result.weightGoalsSkipped += 1
            } else {
                modelContext.insert(dto.toModel())
                result.weightGoalsAdded += 1
            }
        }

        return result
    }
}
