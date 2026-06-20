import Foundation

enum FoodSource: String, Codable, CaseIterable {
    case barcode
    case aiVision
    case manual
    case fatSecret
    /// Bundled vegetarian high-protein library seeded on first launch.
    case curated
    /// Ingredient created by the AI recipe generator.
    case aiRecipe
}

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch: return "sun.max"
        case .dinner: return "moon.stars"
        case .snack: return "leaf"
        }
    }

    /// Best-guess meal type for the current time of day.
    static var currentGuess: MealType {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<21: return .dinner
        default: return .snack
        }
    }
}

enum DietGoal: String, Codable, CaseIterable {
    case cut
    case maintain
    case bulk

    var displayName: String {
        rawValue.capitalized
    }

    var proteinMultiplier: Double { 0.75 }
}

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male
    case female
    case unspecified

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .unspecified: return "Prefer not to say"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary
    case lightlyActive
    case moderatelyActive
    case veryActive
    case extremelyActive

    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .lightlyActive: return 1.375
        case .moderatelyActive: return 1.55
        case .veryActive: return 1.725
        case .extremelyActive: return 1.9
        }
    }

    var displayName: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .lightlyActive: return "Lightly active"
        case .moderatelyActive: return "Moderately active"
        case .veryActive: return "Very active"
        case .extremelyActive: return "Extremely active"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: return "Desk job, little exercise"
        case .lightlyActive: return "Light exercise 1–3 days/week"
        case .moderatelyActive: return "Moderate exercise 3–5 days/week"
        case .veryActive: return "Hard exercise 6–7 days/week"
        case .extremelyActive: return "Athlete / physical job"
        }
    }
}

