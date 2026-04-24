import Foundation

/// THE ONLY AI CALL IN THE APP.
/// Uses Gemini 2.5 Flash to identify food from a photo and estimate nutrition.
actor AIVisionService {
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    enum AIError: Error, LocalizedError {
        case noAPIKey
        case networkError(Error)
        case invalidResponse
        case parseFailed

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "Gemini API key not configured."
            case .networkError(let e): return "Network error: \(e.localizedDescription)"
            case .invalidResponse: return "Invalid response from Gemini."
            case .parseFailed: return "Could not parse food estimate from AI response."
            }
        }
    }

    struct EstimatedFood {
        let name: String
        let estimatedGrams: Double
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fiberG: Double
        let ironMg: Double
        let vitaminDMcg: Double
        let vitaminB12Mcg: Double
        let isVegetarian: Bool
        let containsEggs: Bool
        let containsMushrooms: Bool
        let confidence: Double
        let warnings: [String]
    }

    /// Analyze a food photo using Gemini 2.5 Flash.
    /// This is the ONLY AI call in the entire app.
    func analyze(imageBase64: String, excludedIngredients: [String], isVegetarian: Bool) async throws -> EstimatedFood {
        guard let apiKey = SecretsLoader.geminiAPIKey else {
            throw AIError.noAPIKey
        }

        let exclusions = excludedIngredients.joined(separator: ", ")
        let dietInfo = isVegetarian ? "User is vegetarian" : "No dietary restrictions"

        let prompt = """
        \(dietInfo) and excludes: \(exclusions).
        Identify the food in this image. Estimate grams, then estimate macros and micros per the estimated portion.
        If the image contains excluded items (\(exclusions)), list them in warnings.
        Return ONLY valid JSON matching this exact schema:
        {
          "name": "string",
          "estimated_grams": number,
          "calories": number,
          "protein_g": number,
          "carbs_g": number,
          "fat_g": number,
          "fiber_g": number,
          "iron_mg": number,
          "vitamin_d_mcg": number,
          "vitamin_b12_mcg": number,
          "is_vegetarian": boolean,
          "contains_eggs": boolean,
          "contains_mushrooms": boolean,
          "confidence": number between 0 and 1,
          "warnings": ["string"]
        }
        """

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": imageBase64
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json"
            ]
        ]

        guard let url = URL(string: "\(endpoint)?key=\(apiKey)") else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.networkError(error)
        }

        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> EstimatedFood {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw AIError.invalidResponse
        }

        guard let jsonData = text.data(using: .utf8) else {
            throw AIError.parseFailed
        }

        let result: AIFoodResult
        do {
            result = try JSONDecoder().decode(AIFoodResult.self, from: jsonData)
        } catch {
            throw AIError.parseFailed
        }

        return EstimatedFood(
            name: result.name,
            estimatedGrams: result.estimatedGrams,
            calories: result.calories,
            proteinG: result.proteinG,
            carbsG: result.carbsG,
            fatG: result.fatG,
            fiberG: result.fiberG,
            ironMg: result.ironMg,
            vitaminDMcg: result.vitaminDMcg,
            vitaminB12Mcg: result.vitaminB12Mcg,
            isVegetarian: result.isVegetarian,
            containsEggs: result.containsEggs,
            containsMushrooms: result.containsMushrooms,
            confidence: result.confidence,
            warnings: result.warnings
        )
    }
}

// MARK: - Private response type

private struct AIFoodResult: Decodable {
    let name: String
    let estimatedGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let ironMg: Double
    let vitaminDMcg: Double
    let vitaminB12Mcg: Double
    let isVegetarian: Bool
    let containsEggs: Bool
    let containsMushrooms: Bool
    let confidence: Double
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case estimatedGrams = "estimated_grams"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case ironMg = "iron_mg"
        case vitaminDMcg = "vitamin_d_mcg"
        case vitaminB12Mcg = "vitamin_b12_mcg"
        case isVegetarian = "is_vegetarian"
        case containsEggs = "contains_eggs"
        case containsMushrooms = "contains_mushrooms"
        case confidence
        case warnings
    }
}
