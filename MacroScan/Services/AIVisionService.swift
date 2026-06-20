import Foundation

/// THE ONLY AI CALL IN THE APP.
/// Uses Gemini 2.5 Flash to identify food from a photo and estimate nutrition.
actor AIVisionService {
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

    enum AIError: Error, LocalizedError {
        case noAPIKey
        case networkError(Error)
        case httpError(status: Int, body: String)
        case blocked(reason: String)
        case emptyResponse
        case parseFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "Gemini API key not configured. Add GEMINI_API_KEY to Secrets.plist."
            case .networkError(let e):
                return "Network error: \(e.localizedDescription)"
            case .httpError(let status, let body):
                let snippet = body.prefix(300)
                return "Gemini HTTP \(status): \(snippet)"
            case .blocked(let reason):
                return "Gemini blocked this request: \(reason)"
            case .emptyResponse:
                return "Gemini returned no candidates."
            case .parseFailed(let detail):
                return "Could not parse AI response: \(detail)"
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

    // MARK: - Recipe generation

    struct GeneratedRecipeIngredient {
        let name: String
        let grams: Double
        let calories, proteinG, carbsG, fatG, fiberG: Double
    }

    struct GeneratedRecipe {
        let name: String
        let totalServings: Double
        let notes: String?
        let instructions: [String]
        let ingredients: [GeneratedRecipeIngredient]
    }

    /// Generate a vegetarian recipe with Gemini, optionally tuned to remaining macros.
    /// Reuses the same endpoint/header/`responseMimeType` and retry/backoff path as `analyze()`.
    /// `targetCalories`/`targetProtein` (when non-nil) steer the PER-SERVING macros, protein-first.
    func generateRecipe(
        prompt userText: String,
        isVegetarian: Bool,
        excludedIngredients: [String],
        targetCalories: Double?,
        targetProtein: Double?,
        previousRecipeJSON: String? = nil,
        refinement: String? = nil
    ) async throws -> GeneratedRecipe {
        let backoffs: [UInt64] = [0, 1_000_000_000, 3_000_000_000, 8_000_000_000]
        var lastError: Error?

        for attempt in 0..<3 {
            if backoffs[attempt] > 0 {
                try? await Task.sleep(nanoseconds: backoffs[attempt])
            }
            do {
                return try await performGenerateRecipe(
                    userText: userText,
                    isVegetarian: isVegetarian,
                    excludedIngredients: excludedIngredients,
                    targetCalories: targetCalories,
                    targetProtein: targetProtein,
                    previousRecipeJSON: previousRecipeJSON,
                    refinement: refinement
                )
            } catch let error as AIError {
                lastError = error
                if Self.isRetryable(error), attempt < 2 {
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }
        throw lastError ?? AIError.emptyResponse
    }

    private func performGenerateRecipe(
        userText: String,
        isVegetarian: Bool,
        excludedIngredients: [String],
        targetCalories: Double?,
        targetProtein: Double?,
        previousRecipeJSON: String?,
        refinement: String?
    ) async throws -> GeneratedRecipe {
        let exclusions = excludedIngredients.isEmpty ? "none" : excludedIngredients.joined(separator: ", ")
        let dietLine = isVegetarian
            ? "The recipe MUST be vegetarian (no meat, poultry, or fish)."
            : "No strict dietary restriction, but keep it vegetarian-friendly."

        var goalLines: [String] = []
        if let p = targetProtein {
            goalLines.append("Design a single recipe whose PER-SERVING macros are close to ~\(Int(p)) g protein (protein is the priority).")
        }
        if let c = targetCalories {
            goalLines.append("Per-serving calories should be close to ~\(Int(c)) kcal.")
        }
        let goalBlock = goalLines.isEmpty ? "" : goalLines.joined(separator: "\n") + "\n"

        let keywords = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywordLine = keywords.isEmpty
            ? "The user did not give extra keywords; pick something tasty and balanced."
            : "User request / cuisine / keywords: \(keywords)."

        let trimmedRefinement = refinement?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isRefine = previousRecipeJSON != nil && !trimmedRefinement.isEmpty
        let refineBlock: String
        if let previous = previousRecipeJSON, isRefine {
            refineBlock = """
            Here is the current recipe as JSON:
            \(previous)
            Revise it per this request: "\(trimmedRefinement)". Keep what already works; return the COMPLETE revised recipe.

            """
        } else {
            refineBlock = ""
        }

        let prompt = """
        You are designing one vegetarian recipe.
        \(dietLine)
        HARD CONSTRAINT: do NOT include any of these excluded ingredients: \(exclusions).
        \(keywordLine)
        \(goalBlock)\(refineBlock)Provide realistic ingredient amounts in grams, and ACCURATE macros for EACH ingredient AT that gram amount (not per 100g), using standard food-composition values. Each ingredient's calories MUST be consistent with its macros: calories ≈ 4*protein_g + 4*carbs_g + 9*fat_g (within ~10%). Double-check every number.
        Also provide clear step-by-step preparation instructions.
        Do NOT include any micronutrients.
        Return ONLY valid JSON matching this exact schema:
        {
          "name": "string",
          "total_servings": number,
          "notes": "string or null",
          "instructions": ["step 1", "step 2"],
          "ingredients": [
            {
              "name": "string",
              "grams": number,
              "calories": number,
              "protein_g": number,
              "carbs_g": number,
              "fat_g": number,
              "fiber_g": number
            }
          ]
        }
        """

        let data = try await postGemini(parts: [["text": prompt]], temperature: isRefine ? 0.4 : 0.6)
        return try parseRecipeResponse(data)
    }

    private nonisolated func parseRecipeResponse(_ data: Data) throws -> GeneratedRecipe {
        let text = try candidateText(from: data)

        guard let jsonData = text.data(using: .utf8) else {
            throw AIError.parseFailed("text not utf8")
        }

        let result: AIRecipeResult
        do {
            result = try JSONDecoder().decode(AIRecipeResult.self, from: jsonData)
        } catch {
            throw AIError.parseFailed("schema mismatch: \(text.prefix(200))")
        }

        let ingredients = result.ingredients.map { ing in
            GeneratedRecipeIngredient(
                name: ing.name,
                grams: ing.grams,
                calories: ing.calories,
                proteinG: ing.proteinG,
                carbsG: ing.carbsG,
                fatG: ing.fatG,
                fiberG: ing.fiberG
            )
        }

        return GeneratedRecipe(
            name: result.name,
            totalServings: result.totalServings > 0 ? result.totalServings : 1,
            notes: result.notes,
            instructions: result.instructions ?? [],
            ingredients: ingredients
        )
    }

    /// Analyze a food photo using Gemini 2.5 Flash.
    /// This is the ONLY AI call in the entire app.
    ///
    /// `progress` is called on each attempt with a user-facing string
    /// ("Analyzing…", "Retrying…", "Still trying…"). Retries on quota/overload errors
    /// with exponential backoff (1s, 3s, 8s) up to 3 attempts total.
    func analyze(
        imageBase64: String,
        excludedIngredients: [String],
        isVegetarian: Bool,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> EstimatedFood {
        let labels = ["Analyzing…", "Retrying…", "Still trying…"]
        let backoffs: [UInt64] = [0, 1_000_000_000, 3_000_000_000, 8_000_000_000]
        var lastError: Error?

        for attempt in 0..<3 {
            if backoffs[attempt] > 0 {
                try? await Task.sleep(nanoseconds: backoffs[attempt])
            }
            progress?(labels[attempt])
            do {
                return try await performAnalyze(
                    imageBase64: imageBase64,
                    excludedIngredients: excludedIngredients,
                    isVegetarian: isVegetarian
                )
            } catch let error as AIError {
                lastError = error
                if Self.isRetryable(error), attempt < 2 {
                    continue
                }
                throw error
            } catch {
                // Non-AIError (e.g. CancellationError) — don't retry.
                throw error
            }
        }
        throw lastError ?? AIError.emptyResponse
    }

    /// Classify which AIError variants are worth retrying.
    /// Only quota / overload / "high demand" signals — everything else is terminal.
    nonisolated static func isRetryable(_ error: AIError) -> Bool {
        switch error {
        case .httpError(let status, let body):
            if status == 429 || status == 503 { return true }
            let lower = body.lowercased()
            return lower.contains("high demand") ||
                   lower.contains("overloaded") ||
                   lower.contains("quota") ||
                   lower.contains("rate limit")
        case .networkError:
            return true
        default:
            return false
        }
    }

    /// Returns true if the error was quota/rate-limit related (for messaging).
    nonisolated static func isQuotaError(_ error: AIError) -> Bool {
        if case .httpError(let status, let body) = error {
            if status == 429 { return true }
            let lower = body.lowercased()
            return lower.contains("quota") || lower.contains("rate limit")
        }
        return false
    }

    private func performAnalyze(imageBase64: String, excludedIngredients: [String], isVegetarian: Bool) async throws -> EstimatedFood {
        let exclusions = excludedIngredients.isEmpty ? "none" : excludedIngredients.joined(separator: ", ")
        let dietInfo = isVegetarian ? "User is vegetarian" : "No dietary restrictions"

        let prompt = """
        \(dietInfo) and excludes: \(exclusions).
        Identify the food in this image. Estimate grams, then estimate macros per the estimated portion.
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
          "is_vegetarian": boolean,
          "contains_eggs": boolean,
          "contains_mushrooms": boolean,
          "confidence": number between 0 and 1,
          "warnings": ["string"]
        }
        """

        let parts: [[String: Any]] = [
            ["text": prompt],
            [
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": imageBase64
                ]
            ]
        ]

        let data = try await postGemini(parts: parts, temperature: 0.2)
        return try parseResponse(data)
    }

    /// Shared Gemini POST used by both `analyze()` and `generateRecipe()`.
    /// Builds the request with the standard endpoint/header/`responseMimeType`,
    /// throws the same `AIError` variants, and returns the raw response `Data`.
    private func postGemini(parts: [[String: Any]], temperature: Double) async throws -> Data {
        guard let apiKey = await MainActor.run(body: { SecretsLoader.geminiAPIKey }) else {
            throw AIError.noAPIKey
        }

        let requestBody: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "temperature": temperature
            ]
        ]

        guard let url = URL(string: endpoint) else {
            throw AIError.parseFailed("bad endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw AIError.httpError(status: http.statusCode, body: body)
        }

        return data
    }

    private nonisolated func parseResponse(_ data: Data) throws -> EstimatedFood {
        let text = try candidateText(from: data)

        guard let jsonData = text.data(using: .utf8) else {
            throw AIError.parseFailed("text not utf8")
        }

        let result: AIFoodResult
        do {
            result = try JSONDecoder().decode(AIFoodResult.self, from: jsonData)
        } catch {
            throw AIError.parseFailed("schema mismatch: \(text.prefix(200))")
        }

        return EstimatedFood(
            name: result.name,
            estimatedGrams: result.estimatedGrams,
            calories: result.calories,
            proteinG: result.proteinG,
            carbsG: result.carbsG,
            fatG: result.fatG,
            fiberG: result.fiberG,
            ironMg: result.ironMg ?? 0,
            vitaminDMcg: result.vitaminDMcg ?? 0,
            vitaminB12Mcg: result.vitaminB12Mcg ?? 0,
            isVegetarian: result.isVegetarian,
            containsEggs: result.containsEggs,
            containsMushrooms: result.containsMushrooms,
            confidence: result.confidence,
            warnings: result.warnings
        )
    }

    /// Extract the model's JSON text payload from a Gemini response envelope.
    /// Shared by photo analysis and recipe generation. Throws the same
    /// `.blocked` / `.emptyResponse` / `.parseFailed` variants as before.
    private nonisolated func candidateText(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AIError.parseFailed("outer JSON invalid: \(raw.prefix(200))")
        }

        // Prompt-level blocks come back in promptFeedback.
        if let feedback = json["promptFeedback"] as? [String: Any],
           let reason = feedback["blockReason"] as? String {
            throw AIError.blocked(reason: reason)
        }

        guard let candidates = json["candidates"] as? [[String: Any]], !candidates.isEmpty else {
            throw AIError.emptyResponse
        }

        let first = candidates[0]
        if let finish = first["finishReason"] as? String, finish == "SAFETY" || finish == "RECITATION" {
            throw AIError.blocked(reason: finish)
        }

        guard let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw AIError.parseFailed("missing candidate text: \(raw.prefix(200))")
        }

        return text
    }
}

// MARK: - Private response type

private struct AIFoodResult: Decodable, Sendable {
    let name: String
    let estimatedGrams: Double
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let ironMg: Double?
    let vitaminDMcg: Double?
    let vitaminB12Mcg: Double?
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

private struct AIRecipeResult: Decodable, Sendable {
    let name: String
    let totalServings: Double
    let notes: String?
    let instructions: [String]?
    let ingredients: [Ingredient]

    enum CodingKeys: String, CodingKey {
        case name
        case totalServings = "total_servings"
        case notes
        case instructions
        case ingredients
    }

    struct Ingredient: Decodable, Sendable {
        let name: String
        let grams: Double
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fiberG: Double

        enum CodingKeys: String, CodingKey {
            case name
            case grams
            case calories
            case proteinG = "protein_g"
            case carbsG = "carbs_g"
            case fatG = "fat_g"
            case fiberG = "fiber_g"
        }
    }
}
