import Foundation

/// FatSecret Platform API — the third search source. Covers restaurant chain items and
/// branded foods that OFF misses. Uses OAuth 2.0 client credentials with bearer token.
///
/// All calls route through a Cloudflare Worker proxy (FATSECRET_PROXY_URL in Secrets.plist)
/// to avoid IP whitelist restrictions on mobile. The proxy holds the consumer credentials;
/// the iOS app only stores the proxy URL.
///
/// Premier Free tier: ~5000 calls/day. Attribution required: "Powered by FatSecret".
actor FatSecretAPI {
    enum FatSecretError: Error, LocalizedError {
        case missingProxyURL
        case authFailed
        case rateLimited
        case notFound
        case networkError(Error)
        case decodingError(Error)
        case proxyError(String)
        case httpError(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .missingProxyURL:
                return "FatSecret proxy URL not configured. Add FATSECRET_PROXY_URL to Secrets.plist."
            case .authFailed:
                return "FatSecret authentication failed. Check proxy credentials."
            case .rateLimited:
                return "FatSecret daily limit reached."
            case .notFound:
                return "No match on FatSecret."
            case .networkError(let e):
                return "Network error: \(e.localizedDescription)"
            case .decodingError(let e):
                return "Decode error: \(e.localizedDescription)"
            case .proxyError(let msg):
                return "Proxy error: \(msg)"
            case .httpError(let s, let b):
                return "FatSecret HTTP \(s): \(b.prefix(200))"
            }
        }
    }

    // MARK: - Search

    func search(query: String, limit: Int = 10) async throws -> [Food] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let params: [String: Any] = [
            "method": "foods.search.v3",
            "search_expression": trimmed,
            "max_results": limit,
            "include_food_images": false
        ]

        let data = try await proxyRequest(params: params)

        do {
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            let items = decoded.foodsSearch?.results?.food ?? decoded.foodsSearch?.results?.foodArray ?? []
            return items.prefix(limit).map(Self.mapSearchItem)
        } catch {
            print("[FatSecret] search decode error: \(error)")
            print("[FatSecret] raw response: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            throw FatSecretError.decodingError(error)
        }
    }

    // MARK: - Food Detail

    func foodDetail(id: String) async throws -> Food {
        let params: [String: Any] = [
            "method": "food.get.v4",
            "food_id": id
        ]

        let data = try await proxyRequest(params: params)

        do {
            let decoded = try JSONDecoder().decode(FoodDetailResponse.self, from: data)
            guard let item = decoded.food else { throw FatSecretError.notFound }
            print("[FatSecret] foodDetail raw: \(String(data: data, encoding: .utf8) ?? "")")
            let food = Self.mapDetailItem(item)
            print("[FatSecret] mapped: servingGrams=\(food.servingSizeGrams) cal=\(food.calories) pro=\(food.proteinG) carbs=\(food.carbsG) fat=\(food.fatG)")
            return food
        } catch let e as FatSecretError {
            throw e
        } catch {
            print("[FatSecret] foodDetail decode error: \(error)")
            print("[FatSecret] raw: \(String(data: data, encoding: .utf8) ?? "")")
            throw FatSecretError.decodingError(error)
        }
    }

    // MARK: - Natural Language

    func parseNaturalLanguage(_ text: String) async throws -> [Food] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let params: [String: Any] = [
            "method": "natural_language_processing",
            "text": trimmed
        ]

        let data = try await proxyRequest(params: params)

        do {
            let decoded = try JSONDecoder().decode(NLPResponse.self, from: data)
            let items = decoded.naturalLanguageProcessing?.foods ?? []
            return items.map(Self.mapNLPItem)
        } catch {
            throw FatSecretError.decodingError(error)
        }
    }

    // MARK: - Autocomplete

    func autocomplete(query: String, maxResults: Int = 7) async throws -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let params: [String: Any] = [
            "method": "foods.autocomplete",
            "expression": trimmed,
            "max_results": maxResults
        ]

        let data = try await proxyRequest(params: params)

        do {
            let decoded = try JSONDecoder().decode(AutocompleteResponse.self, from: data)
            return decoded.suggestions?.suggestion ?? []
        } catch {
            throw FatSecretError.decodingError(error)
        }
    }

    // MARK: - Barcode Lookup

    func barcodeLookup(barcode: String) async throws -> Food {
        let params: [String: Any] = [
            "method": "food.find_id_for_barcode",
            "barcode": barcode
        ]
        let data = try await proxyRequest(params: params)
        do {
            let decoded = try JSONDecoder().decode(BarcodeLookupResponse.self, from: data)
            guard let foodId = decoded.foodId?.value, !foodId.isEmpty else {
                throw FatSecretError.notFound
            }
            let food = try await foodDetail(id: foodId)
            food.barcode = barcode
            return food
        } catch let e as FatSecretError {
            throw e
        } catch {
            throw FatSecretError.decodingError(error)
        }
    }

    // MARK: - Proxy request

    private func proxyRequest(params: [String: Any]) async throws -> Data {
        // Make sure you also load FATSECRET_CLIENT_SECRET from your .plist in SecretsLoader!
        guard let proxyURLString = SecretsLoader.fatSecretProxyURL,
              let clientSecret = SecretsLoader.fatSecretClientSecret else {
            throw FatSecretError.missingProxyURL
        }

        // 1. Construct the URL with query parameters instead of a JSON body
        guard var urlComponents = URLComponents(string: proxyURLString) else {
            throw FatSecretError.proxyError("Invalid proxy URL")
        }
        
        urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: "\($0.value)") }

        guard let url = urlComponents.url else {
            throw FatSecretError.proxyError("Failed to construct URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET" // Change to GET since params are in the URL
        request.timeoutInterval = 20
        
        // 2. Add the required Client Secret header for your Worker proxy
        request.setValue(clientSecret, forHTTPHeaderField: "X-Client-Secret")
        // (Optional but good practice)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FatSecretError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { return data }
        if http.statusCode == 429 { throw FatSecretError.rateLimited }
        if http.statusCode == 401 { throw FatSecretError.authFailed }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw FatSecretError.httpError(status: http.statusCode, body: body)
        }
        return data
    }

    // MARK: - Mapping

    private nonisolated static func mapSearchItem(_ item: FSSearchFood) -> Food {
        let serving = item.servings?.serving?.first
        let cal = Double(serving?.calories ?? item.foodDescription?.extractCalories() ?? "0") ?? 0
        let pro = Double(serving?.protein ?? "0") ?? 0
        let carbs = Double(serving?.carbohydrate ?? "0") ?? 0
        let fat = Double(serving?.fat ?? "0") ?? 0
        let fiber = Double(serving?.fiber ?? "0") ?? 0
        let servingGrams = Double(serving?.metricServingAmount ?? "100") ?? 100

        return Food(
            name: item.foodName ?? "Unknown",
            brand: item.brandName,
            servingSizeGrams: servingGrams,
            calories: cal,
            proteinG: pro,
            carbsG: carbs,
            fatG: fat,
            fiberG: fiber,
            source: .fatSecret
        )
    }

    private nonisolated static func mapDetailItem(_ item: FSDetailFood) -> Food {
        let serving = item.servings?.serving?.first
        let cal = Double(serving?.calories ?? "0") ?? 0
        let pro = Double(serving?.protein ?? "0") ?? 0
        let carbs = Double(serving?.carbohydrate ?? "0") ?? 0
        let fat = Double(serving?.fat ?? "0") ?? 0
        let fiber = Double(serving?.fiber ?? "0") ?? 0
        let iron = Double(serving?.iron ?? "0") ?? 0
        let servingGrams = Double(serving?.metricServingAmount ?? "100") ?? 100

        return Food(
            name: item.foodName ?? "Unknown",
            brand: item.brandName,
            servingSizeGrams: servingGrams,
            calories: cal,
            proteinG: pro,
            carbsG: carbs,
            fatG: fat,
            fiberG: fiber,
            ironMg: iron,
            vitaminDMcg: 0,
            vitaminB12Mcg: 0,
            source: .fatSecret
        )
    }

    private nonisolated static func mapNLPItem(_ item: FSNLPFood) -> Food {
        let cal = Double(item.calories ?? "0") ?? 0
        let pro = Double(item.protein ?? "0") ?? 0
        let carbs = Double(item.carbohydrate ?? "0") ?? 0
        let fat = Double(item.fat ?? "0") ?? 0
        let fiber = Double(item.fiber ?? "0") ?? 0
        let servingGrams = Double(item.metricServingAmount ?? "100") ?? 100

        return Food(
            name: (item.foodName ?? "Unknown").capitalized,
            brand: item.brandName,
            servingSizeGrams: servingGrams,
            calories: cal,
            proteinG: pro,
            carbsG: carbs,
            fatG: fat,
            fiberG: fiber,
            source: .fatSecret
        )
    }
}

// MARK: - Response types

private struct SearchResponse: Decodable, Sendable {
    let foodsSearch: FoodsSearch?

    enum CodingKeys: String, CodingKey {
        case foodsSearch = "foods_search"
    }
}

private struct FoodsSearch: Decodable, Sendable {
    let results: FoodsSearchResults?
}

private struct FoodsSearchResults: Decodable, Sendable {
    let food: [FSSearchFood]?
    let foodArray: [FSSearchFood]?

    enum CodingKeys: String, CodingKey {
        case food
        case foodArray = "food_array"
    }
}

private struct FSSearchFood: Decodable, Sendable {
    let foodId: String?
    let foodName: String?
    let brandName: String?
    let foodDescription: String?
    let servings: FSSearchServings?

    enum CodingKeys: String, CodingKey {
        case foodId = "food_id"
        case foodName = "food_name"
        case brandName = "brand_name"
        case foodDescription = "food_description"
        case servings
    }
}

private struct FSSearchServings: Decodable, Sendable {
    let serving: [FSServing]?
}

private struct FSServing: Decodable, Sendable {
    let calories: String?
    let protein: String?
    let carbohydrate: String?
    let fat: String?
    let fiber: String?
    let iron: String?
    let metricServingAmount: String?

    enum CodingKeys: String, CodingKey {
        case calories
        case protein
        case carbohydrate
        case fat
        case fiber
        case iron
        case metricServingAmount = "metric_serving_amount"
    }
}

private struct FoodDetailResponse: Decodable, Sendable {
    let food: FSDetailFood?
}

private struct FSDetailFood: Decodable, Sendable {
    let foodId: String?
    let foodName: String?
    let brandName: String?
    let servings: FSDetailServings?

    enum CodingKeys: String, CodingKey {
        case foodId = "food_id"
        case foodName = "food_name"
        case brandName = "brand_name"
        case servings
    }
}

private struct FSDetailServings: Decodable, Sendable {
    let serving: [FSServing]?
}

private struct NLPResponse: Decodable, Sendable {
    let naturalLanguageProcessing: NLPResult?

    enum CodingKeys: String, CodingKey {
        case naturalLanguageProcessing = "natural_language_processing"
    }
}

private struct NLPResult: Decodable, Sendable {
    let foods: [FSNLPFood]?
}

private struct FSNLPFood: Decodable, Sendable {
    let foodName: String?
    let brandName: String?
    let calories: String?
    let protein: String?
    let carbohydrate: String?
    let fat: String?
    let fiber: String?
    let metricServingAmount: String?

    enum CodingKeys: String, CodingKey {
        case foodName = "food_name"
        case brandName = "brand_name"
        case calories
        case protein
        case carbohydrate
        case fat
        case fiber
        case metricServingAmount = "metric_serving_amount"
    }
}

private struct BarcodeLookupResponse: Decodable, Sendable {
    let foodId: BarcodeIdValue?
    enum CodingKeys: String, CodingKey { case foodId = "food_id" }
}

private struct BarcodeIdValue: Decodable, Sendable {
    let value: String?
}

private struct AutocompleteResponse: Decodable, Sendable {
    let suggestions: AutocompleteSuggestions?
}

private struct AutocompleteSuggestions: Decodable, Sendable {
    let suggestion: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let arr = try? c.decode([String].self, forKey: .suggestion) {
            suggestion = arr
        } else if let str = try? c.decode(String.self, forKey: .suggestion) {
            suggestion = [str]
        } else {
            suggestion = []
        }
    }

    enum CodingKeys: String, CodingKey { case suggestion }
}

// MARK: - Food description parser

private extension String {
    func extractCalories() -> String? {
        let pattern = #"Calories:\s*(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let range = Range(match.range(at: 1), in: self)
        else { return nil }
        return String(self[range])
    }
}
