import Foundation
import SwiftData

/// Fetches and caches dining hall menu data.
/// Currently uses a placeholder endpoint — swap URL once the GitHub Action
/// scraper or Cloudflare Worker is live.
actor DiningMenuService {
    /// Base URL for menu JSON files. Replace with real endpoint once data pipeline is confirmed.
    private let baseURL = "https://raw.githubusercontent.com/placeholder/cal-dining-menus/main"
    private let cacheMaxAge: TimeInterval = 4 * 3600 // 4 hours

    enum MenuError: Error, LocalizedError {
        case networkError(Error)
        case noData
        case parseFailed

        var errorDescription: String? {
            switch self {
            case .networkError(let e): return "Network error: \(e.localizedDescription)"
            case .noData: return "No menu data available for this date."
            case .parseFailed: return "Could not parse menu data."
            }
        }
    }

    /// Fetch menus for a given date. Returns cached data if fresh, otherwise fetches from network.
    @MainActor
    func fetchMenus(forDate date: Date, modelContext: ModelContext) async throws -> [DiningMenu] {
        let cached = cachedMenus(forDate: date, modelContext: modelContext)
        if !cached.isEmpty {
            return cached
        }

        let dateString = Self.dateFormatter.string(from: date)
        let menus = try await fetchFromNetwork(dateString: dateString)

        // Cache in SwiftData
        for menu in menus {
            modelContext.insert(menu)
        }

        return menus
    }

    /// Check local cache for menus within the cache window
    @MainActor
    private func cachedMenus(forDate date: Date, modelContext: ModelContext) -> [DiningMenu] {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let cutoff = Date().addingTimeInterval(-cacheMaxAge)

        let descriptor = FetchDescriptor<DiningMenu>(
            predicate: #Predicate { menu in
                menu.date >= startOfDay && menu.date < endOfDay && menu.lastFetched >= cutoff
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetch raw JSON from the remote endpoint
    private func fetchFromNetwork(dateString: String) async throws -> [DiningMenu] {
        var allMenus: [DiningMenu] = []

        for location in DiningLocation.allCases {
            let urlString = "\(baseURL)/\(dateString)/\(location.rawValue).json"
            guard let url = URL(string: urlString) else { continue }

            let data: Data
            do {
                (data, _) = try await URLSession.shared.data(from: url)
            } catch {
                continue // Skip locations that fail — partial data is OK
            }

            if let menu = try? Self.parseMenuJSON(data, location: location) {
                allMenus.append(contentsOf: menu)
            }
        }

        if allMenus.isEmpty {
            throw MenuError.noData
        }

        return allMenus
    }

    /// Parse the per-location JSON into DiningMenu models
    private nonisolated static func parseMenuJSON(_ data: Data, location: DiningLocation) throws -> [DiningMenu] {
        let raw = try JSONDecoder().decode(RawDiningResponse.self, from: data)
        var menus: [DiningMenu] = []

        let date = dateFormatter.date(from: raw.date) ?? Date()

        for (mealPeriod, mealData) in raw.meals {
            let items = mealData.items.map { item in
                DiningMenuItem(
                    name: item.name,
                    category: item.category,
                    servingGrams: item.servingG,
                    calories: item.calories,
                    proteinG: item.proteinG,
                    carbsG: item.carbsG,
                    fatG: item.fatG,
                    fiberG: item.fiberG,
                    ironMg: item.ironMg,
                    vitaminDMcg: item.vitaminDMcg,
                    vitaminB12Mcg: item.vitaminB12Mcg,
                    tags: item.tags ?? [],
                    allergens: item.allergens ?? []
                )
            }
            let menu = DiningMenu(location: location, date: date, mealPeriod: mealPeriod, items: items)
            menus.append(menu)
        }

        return menus
    }

    private nonisolated static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Private JSON types

private struct RawDiningResponse: Decodable, Sendable {
    let date: String
    let location: String
    let meals: [String: RawMealPeriod]
}

private struct RawMealPeriod: Decodable, Sendable {
    let start: String?
    let end: String?
    let items: [RawMenuItem]
}

private struct RawMenuItem: Decodable, Sendable {
    let name: String
    let category: String
    let servingG: Double?
    let calories: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?
    let ironMg: Double?
    let vitaminDMcg: Double?
    let vitaminB12Mcg: Double?
    let tags: [String]?
    let allergens: [String]?

    enum CodingKeys: String, CodingKey {
        case name, category, calories, tags, allergens
        case servingG = "serving_g"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case ironMg = "iron_mg"
        case vitaminDMcg = "vitamin_d_mcg"
        case vitaminB12Mcg = "vitamin_b12_mcg"
    }
}
