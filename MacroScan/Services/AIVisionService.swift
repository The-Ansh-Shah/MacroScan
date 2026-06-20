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
        guard let apiKey = await MainActor.run(body: { SecretsLoader.geminiAPIKey }) else {
            throw AIError.noAPIKey
        }

        let exclusions = excludedIngredients.isEmpty ? "none" : excludedIngredients.joined(separator: ", ")
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
                "responseMimeType": "application/json",
                "temperature": 0.2
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

        return try parseResponse(data)
    }

    private nonisolated func parseResponse(_ data: Data) throws -> EstimatedFood {
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

private struct AIFoodResult: Decodable, Sendable {
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
