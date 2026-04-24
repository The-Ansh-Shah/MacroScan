import Foundation

/// Open Food Facts free API client — no auth required
actor OpenFoodFactsAPI {
    private let baseURL = "https://world.openfoodfacts.org/api/v2/product"

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

    /// Look up a barcode and return a Food object
    func lookup(barcode: String) async throws -> Food {
        let urlString = "\(baseURL)/\(barcode).json"
        guard let url = URL(string: urlString) else {
            throw OFFError.invalidData
        }

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw OFFError.networkError(error)
        }

        let response: OFFResponse
        do {
            response = try JSONDecoder().decode(OFFResponse.self, from: data)
        } catch {
            throw OFFError.invalidData
        }

        guard response.status == 1, let product = response.product else {
            throw OFFError.productNotFound
        }

        return mapToFood(product: product, barcode: barcode)
    }

    private func mapToFood(product: OFFProduct, barcode: String) -> Food {
        let nutriments = product.nutriments
        let servingGrams = product.servingQuantityG ?? 100.0
        let scale = servingGrams / 100.0

        let ingredientsLower = (product.ingredientsText ?? "").lowercased()
        let containsEggs = ingredientsLower.contains("egg")
        let containsMushrooms = ingredientsLower.contains("mushroom")

        return Food(
            name: product.productName ?? "Unknown Product",
            brand: product.brands,
            barcode: barcode,
            servingSizeGrams: servingGrams,
            calories: (nutriments.energyKcal100g ?? 0) * scale,
            proteinG: (nutriments.proteins100g ?? 0) * scale,
            carbsG: (nutriments.carbohydrates100g ?? 0) * scale,
            fatG: (nutriments.fat100g ?? 0) * scale,
            fiberG: (nutriments.fiber100g ?? 0) * scale,
            ironMg: (nutriments.ironMg100g ?? 0) * scale,
            vitaminDMcg: (nutriments.vitaminDMcg100g ?? 0) * scale,
            vitaminB12Mcg: (nutriments.vitaminB12Mcg100g ?? 0) * scale,
            source: .barcode,
            isVegetarian: !ingredientsLower.contains("meat") &&
                         !ingredientsLower.contains("chicken") &&
                         !ingredientsLower.contains("beef") &&
                         !ingredientsLower.contains("pork") &&
                         !ingredientsLower.contains("fish"),
            containsEggs: containsEggs,
            containsMushrooms: containsMushrooms
        )
    }
}

// MARK: - API Response Types (private)

private struct OFFResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

private struct OFFProduct: Decodable {
    let productName: String?
    let brands: String?
    let servingQuantityG: Double?
    let ingredientsText: String?
    let nutriments: OFFNutriments

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case servingQuantityG = "serving_quantity"
        case ingredientsText = "ingredients_text"
        case nutriments
    }
}

private struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    let fiber100g: Double?
    let ironMg100g: Double?
    let vitaminDMcg100g: Double?
    let vitaminB12Mcg100g: Double?

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
