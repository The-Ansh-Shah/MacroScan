import Foundation
import SwiftData

/// Text search over local foods, Open Food Facts, and FatSecret.
/// All three sources run in parallel; results are merged, deduped, and ranked.
@MainActor
struct FoodSearchService {
    let modelContext: ModelContext
    let offAPI: OpenFoodFactsAPI
    let fatSecretAPI: FatSecretAPI
    var fatSecretSuppressed: Bool = false

    struct Result: Identifiable {
        let id: String
        let food: Food
        let source: Source
        let score: Double
    }

    enum Source {
        case localFavorite
        case localFrequent
        case localOccasional
        case fatSecret
        case off
    }

    func search(query: String) async -> [Result] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        let local = searchLocal(query: q)

        async let offResults = searchOFF(query: q)
        async let fsResults = searchFatSecret(query: q)

        let off = await offResults
        let fs = await fsResults

        return mergeDedup(local: local, fatSecret: fs, off: off)
    }

    // MARK: - Local

    private func searchLocal(query: String) -> [Result] {
        let descriptor = FetchDescriptor<Food>(sortBy: [SortDescriptor(\Food.timesLogged, order: .reverse)])
        let all = (try? modelContext.fetch(descriptor)) ?? []

        let hits = all.compactMap { food -> Result? in
            let name = food.name.lowercased()
            let brand = (food.brand ?? "").lowercased()
            let matchesName = name.contains(query)
            let matchesBrand = brand.contains(query)
            guard matchesName || matchesBrand else { return nil }

            let nameBoost: Double = matchesName ? 2.0 : 1.0
            let prefixBoost: Double = name.hasPrefix(query) ? 1.5 : 1.0
            let frequencyBoost = 1.0 + Double(food.timesLogged) * 0.1
            let score = nameBoost * prefixBoost * frequencyBoost

            let source: Source = {
                if food.isFavorite { return .localFavorite }
                if food.timesLogged >= 3 { return .localFrequent }
                return .localOccasional
            }()
            return Result(id: "local-\(food.persistentModelID.hashValue)", food: food, source: source, score: score)
        }

        return hits.sorted { $0.score > $1.score }
    }

    // MARK: - Remote: OFF

    private func searchOFF(query: String) async -> [Result] {
        do {
            let foods = try await offAPI.search(query: query)
            return foods.enumerated().map { idx, food in
                Result(
                    id: "off-\(food.barcode ?? UUID().uuidString)-\(idx)",
                    food: food,
                    source: .off,
                    score: 1.0 - Double(idx) * 0.01
                )
            }
        } catch {
            return []
        }
    }

    // MARK: - Remote: FatSecret

    private func searchFatSecret(query: String) async -> [Result] {
        guard !fatSecretSuppressed else { return [] }
        do {
            incrementFatSecretCounter()
            let foods = try await fatSecretAPI.search(query: query)
            return foods.enumerated().map { idx, food in
                Result(
                    id: "fs-\(food.name.hashValue)-\(idx)",
                    food: food,
                    source: .fatSecret,
                    score: 2.0 - Double(idx) * 0.01
                )
            }
        } catch let error as FatSecretAPI.FatSecretError {
            if case .rateLimited = error { markFatSecretRateLimited() }
            return []
        } catch {
            return []
        }
    }

    private func incrementFatSecretCounter() {
        guard let profile = FoodRepository(modelContext: modelContext).userProfile() else { return }
        if let resetAt = profile.fatSecretCallsResetAt,
           !Calendar.current.isDateInToday(resetAt) {
            profile.fatSecretCallsToday = 0
        }
        profile.fatSecretCallsToday += 1
        profile.fatSecretCallsResetAt = Date()
    }

    private func markFatSecretRateLimited() {
        guard let profile = FoodRepository(modelContext: modelContext).userProfile() else { return }
        profile.fatSecretCallsToday = 5000
        profile.fatSecretCallsResetAt = Date()
    }

    // MARK: - Merge + Dedup

    private func mergeDedup(local: [Result], fatSecret: [Result], off: [Result]) -> [Result] {
        let localNames = Set(local.map { $0.food.name.lowercased() })

        let filteredFS = fatSecret.filter { !localNames.contains($0.food.name.lowercased()) }
        let fsNames = Set(filteredFS.map { $0.food.name.lowercased() })
        let combinedNames = localNames.union(fsNames)
        let filteredOff = off.filter { !combinedNames.contains($0.food.name.lowercased()) }

        // Rank: local favorites → local frequent → FatSecret → OFF → local occasional
        let favorites = local.filter { $0.source == .localFavorite }
        let frequent = local.filter { $0.source == .localFrequent }
        let occasional = local.filter { $0.source == .localOccasional }

        return favorites + frequent + filteredFS + filteredOff + occasional
    }
}
