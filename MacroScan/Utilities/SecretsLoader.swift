import Foundation

enum SecretsLoader {
    /// Load a secret from Info.plist (sourced from Secrets.xcconfig)
    static func apiKey(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    static var geminiAPIKey: String? {
        apiKey(for: "GEMINI_API_KEY")
    }
}
