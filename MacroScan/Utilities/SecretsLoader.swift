import Foundation

/// Loads secrets from a bundled Secrets.plist (gitignored) with Info.plist fallback.
enum SecretsLoader: Sendable {
    /// Cache is populated once at launch and never mutated — safe across threads.
    private nonisolated(unsafe) static let secretsCache: [String: Any]? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist
    }()

    static func apiKey(for key: String) -> String? {
        if let value = secretsCache?[key] as? String, !value.isEmpty, !value.hasPrefix("PASTE_") {
            return value
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
           !value.isEmpty, !value.hasPrefix("PASTE_") {
            return value
        }
        return nil
    }

    static var geminiAPIKey: String? {
        apiKey(for: "GEMINI_API_KEY")
    }

    static var fatSecretProxyURL: String? {
        apiKey(for: "FATSECRET_PROXY_URL")
    }
    
    // Add this to match your Secrets.plist!
    static var fatSecretClientSecret: String? {
        apiKey(for: "FATSECRET_CLIENT_SECRET")
    }
}