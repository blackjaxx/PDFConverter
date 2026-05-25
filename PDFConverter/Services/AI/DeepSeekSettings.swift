import Foundation

enum DeepSeekSettings {
    private static let baseURLKey = "deepseek.baseURL"
    private static let modelKey = "deepseek.model"

    static let defaultBaseURL = "https://api.deepseek.com"
    static let defaultModel = "deepseek-chat"

    static var baseURL: String {
        get {
            let v = UserDefaults.standard.string(forKey: baseURLKey) ?? ""
            return v.isEmpty ? defaultBaseURL : v
        }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }

    static var model: String {
        get {
            let v = UserDefaults.standard.string(forKey: modelKey) ?? ""
            return v.isEmpty ? defaultModel : v
        }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    static var apiKey: String? {
        KeychainHelper.loadAPIKey()
    }

    static var isConfigured: Bool {
        guard let key = apiKey else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try KeychainHelper.deleteAPIKey()
            return
        }
        try KeychainHelper.saveAPIKey(trimmed)
    }

    static func clearAPIKey() throws {
        try KeychainHelper.deleteAPIKey()
    }
}
