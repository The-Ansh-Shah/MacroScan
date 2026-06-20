import Foundation

/// Open Food Facts free API client — no auth required
actor OpenFoodFactsAPI {
    enum OFFError: Error, LocalizedError {
        case productNotFound
        case networkError(Error)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .productNotFound: return "Product not found in Open Food Facts."
            case .networkError(let error): return "Network error: \(error.localizedDescription)"
            case .invalidData: return "Could not parse product data."
            }
        }
    }

    /// Free-text search against the OFF product catalog.
    /// Maps each search hit directly into a `Food`.
    func search(query: String, limit: Int = 10) async throws -> [Food] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl") else {
            throw OFFError.invalidData
        }
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(limit))
        ]
        guard let url = components.url else { throw OFFError.invalidData }

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw OFFError.networkError(error)
        }

        let response = try Self.decodeSearch(data)
        return response.products.map { Self.mapToFood(product: $0, barcode: $0.code) }
    }

    private nonisolated static func decodeSearch(_ data: Data) throws(OFFError) -> OFFSearchResponse {
        do {
            return try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        } catch {
            throw OFFError.invalidData
        }
    }

    private nonisolated static func mapToFood(product: OFFProduct, barcode: String?) -> Food {
        let nutriments = product.nutriments
        let servingGrams = product.servingQuantityG?.value ?? 100.0
        let scale = servingGrams / 100.0

        let ingredientsText = product.ingredientsText ?? ""
        let ingredientsLower = ingredientsText.lowercased()
        let containsEggs = ingredientsLower.contains("egg")
        let containsMushrooms = ingredientsLower.contains("mushroom")

        // Parse ingredients list: split on comma, strip parenthetical percentages / notes,
        // trim, drop empty. Keeps the ordering OFF uses (most → least by weight).
        let parsedIngredients: [String] = ingredientsText
            .split(separator: ",")
            .map { raw -> String in
                var s = String(raw)
                // Remove parenthetical content like "(10%)" or "(organic)"
                while let open = s.firstIndex(of: "("), let close = s[open...].firstIndex(of: ")") {
                    s.removeSubrange(open...close)
                }
                return s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        return Food(
            name: product.productName ?? "Unknown Product",
            brand: product.brands,
            barcode: barcode,
            servingSizeGrams: servingGrams,
            calories: (nutriments.energyKcal100g?.value ?? 0) * scale,
            proteinG: (nutriments.proteins100g?.value ?? 0) * scale,
            carbsG: (nutriments.carbohydrates100g?.value ?? 0) * scale,
            fatG: (nutriments.fat100g?.value ?? 0) * scale,
            fiberG: (nutriments.fiber100g?.value ?? 0) * scale,
            ironMg: (nutriments.ironMg100g?.value ?? 0) * scale,
            vitaminDMcg: (nutriments.vitaminDMcg100g?.value ?? 0) * scale,
            vitaminB12Mcg: (nutriments.vitaminB12Mcg100g?.value ?? 0) * scale,
            source: .barcode,
            isVegetarian: !ingredientsLower.contains("meat") &&
                         !ingredientsLower.contains("chicken") &&
                         !ingredientsLower.contains("beef") &&
                         !ingredientsLower.contains("pork") &&
                         !ingredientsLower.contains("fish"),
            containsEggs: containsEggs,
            containsMushrooms: containsMushrooms,
            ingredients: parsedIngredients
        )
    }
}

// MARK: - API Response Types (private)

private struct OFFProduct: Decodable, Sendable {
    let code: String?
    let productName: String?
    let brands: String?
    let servingQuantityG: DoubleOrString?
    let ingredientsText: String?
    let nutriments: OFFNutriments

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case servingQuantityG = "serving_quantity"
        case ingredientsText = "ingredients_text"
        case nutriments
    }
}

private struct OFFSearchResponse: Decodable, Sendable {
    let products: [OFFProduct]
}

private struct OFFNutriments: Decodable, Sendable {
    let energyKcal100g: DoubleOrString?
    let proteins100g: DoubleOrString?
    let carbohydrates100g: DoubleOrString?
    let fat100g: DoubleOrString?
    let fiber100g: DoubleOrString?
    let ironMg100g: DoubleOrString?
    let vitaminDMcg100g: DoubleOrString?
    let vitaminB12Mcg100g: DoubleOrString?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case fiber100g = "fiber_100g"
        case ironMg100g = "iron_100g"
        case vitaminDMcg100g = "vitamin-d_100g"
        case vitaminB12Mcg100g = "vitamin-b12_100g"
    }
}

/// OFF's search endpoint sometimes returns nutrient values as strings; the product endpoint
/// returns numbers. This decoder tolerates both and yields a single Double value.
private struct DoubleOrString: Decodable, Sendable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            value = d
        } else if let s = try? container.decode(String.self),
                  let d = Double(s.trimmingCharacters(in: .whitespaces)) {
            value = d
        } else {
            value = 0
        }
    }
}
