import Foundation

enum FoodSource: String, Codable, CaseIterable {
    case barcode
    case aiVision
    case manual
    case diningHall
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
}

enum DietGoal: String, Codable, CaseIterable {
    case cut
    case maintain
    case bulk

    var displayName: String {
        rawValue.capitalized
    }

    var proteinMultiplier: Double {
        switch self {
        case .cut: return 1.0
        case .maintain: return 0.9
        case .bulk: return 1.1
        }
    }
}

enum DiningLocation: String, Codable, CaseIterable, Identifiable {
    case cafe3
    case clarkKerr
    case crossroads
    case foothill

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cafe3: return "Cafe 3"
        case .clarkKerr: return "Clark Kerr"
        case .crossroads: return "Crossroads"
        case .foothill: return "Foothill"
        }
    }
}
