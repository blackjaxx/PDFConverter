import Foundation

/// DeepSeek 配置管理，负责持久化存储 BaseURL、模型名称和 API Key。
///
/// 存储策略：
/// - **BaseURL 和模型名**：存储在 `UserDefaults` 中（非敏感信息，适合 plist 存储）
/// - **API Key**：存储在系统 **Keychain** 中（敏感信息，Keychain 提供加密保护和沙盒隔离）
///
/// 这种分层存储策略是 macOS 开发的最佳实践：
/// 普通配置用 UserDefaults 简单方便，密码/密钥用 Keychain 安全可靠。
enum DeepSeekSettings {
    private static let baseURLKey = "deepseek.baseURL"
    private static let modelKey = "deepseek.model"

    /// API 默认地址，指向 DeepSeek 官方 API
    static let defaultBaseURL = "https://api.deepseek.com"
    /// 默认模型，`deepseek-chat` 是 DeepSeek 的通用对话模型
    static let defaultModel = "deepseek-chat"

    /// BaseURL 的存取：空字符串时回退到 `defaultBaseURL`。
    /// 这样在 UserDefaults 中没有值时也能正常工作。
    static var baseURL: String {
        get {
            let v = UserDefaults.standard.string(forKey: baseURLKey) ?? ""
            return v.isEmpty ? defaultBaseURL : v
        }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }

    /// 模型名称的存取：空字符串时回退到 `defaultModel`。
    static var model: String {
        get {
            let v = UserDefaults.standard.string(forKey: modelKey) ?? ""
            return v.isEmpty ? defaultModel : v
        }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    /// API Key 从 Keychain 加载，返回 nil 表示尚未配置。
    /// 这是计算属性，每次访问都会查询 Keychain（Keychain 查询很快，无需缓存）。
    static var apiKey: String? {
        KeychainHelper.loadAPIKey()
    }

    /// 判断是否已配置：API Key 存在且非空白字符串。
    static var isConfigured: Bool {
        guard let key = apiKey else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 保存 API Key 到 Keychain。空字符串会触发删除操作（清空已保存的 Key）。
    static func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try KeychainHelper.deleteAPIKey()
            return
        }
        try KeychainHelper.saveAPIKey(trimmed)
    }

    /// 从 Keychain 中删除 API Key。
    static func clearAPIKey() throws {
        try KeychainHelper.deleteAPIKey()
    }

    // MARK: - Snapshot

    /// 配置快照，用于在长任务开始时获取一致的配置状态。
    ///
    /// 为什么需要快照？
    /// - BaseURL 和 model 存储在 UserDefaults，每次访问直接读取
    /// - API Key 存储在 Keychain，每次访问会触发 Keychain 查询
    /// - 如果长任务（如 AI 转换）在执行过程中用户修改了配置，
    ///   直接读取会得到不一致的中间状态，可能导致部分操作使用旧配置，
    ///   部分使用新配置（如发送请求用的是旧 URL 但模型名已更新）
    ///
    /// 使用 `snapshot()` 在任务开始时一次性读取所有配置，后续使用快照，
    /// 避免状态变化带来的不确定性。
    static func snapshot() -> (baseURL: String, model: String, apiKey: String?) {
        (baseURL, model, apiKey)
    }
}