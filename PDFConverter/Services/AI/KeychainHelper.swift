import Foundation
import Security

/// 使用 macOS Security 框架（Keychain Services API）安全地存储和读取 API Key。
///
/// Keychain（钥匙串）是 macOS/iOS 提供的**系统级加密存储**，专门用于保存
/// 密码、密钥、证书等敏感信息。相比直接存在 UserDefaults 或文件中，
/// Keychain 有以下优势：
/// - **加密存储**：数据以加密形式保存在磁盘上
/// - **进程隔离**：不同 App 无法读取彼此的 Keychain 条目
/// - **跨设备同步**：可通过 iCloud Keychain 在多设备间同步
///
/// 这里使用通用密码类型（`kSecClassGenericPassword`），
/// 通过 service（`com.local.pdfconverter.deepseek`）和 account（`apiKey`）标识唯一记录。
enum KeychainHelper {
    /// Keychain 中的 service 标识，用于区分不同应用的 Keychain 条目。
    /// 一般使用反向域名格式（如 `com.company.app.feature`）避免冲突。
    private static let service = "com.local.pdfconverter.deepseek"

    /// 保存 API Key 到 Keychain。
    ///
    /// 实现策略：先删除旧 Key，再保存新的。
    /// 这是因为 Keychain 不允许同一个 service+account 组合有重复条目，
    /// 直接覆盖可能会导致 `errSecDuplicateItem` 错误。
    /// 先删后加是最简单可靠的解决方案。
    static func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        try deleteAPIKey()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "apiKey",
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    /// 从 Keychain 加载 API Key。
    ///
    /// 关键参数：
    /// - `kSecReturnData: true`：要求 Keychain 返回存储的数据（而不是元信息）
    /// - `kSecMatchLimit: kSecMatchLimitOne`：只返回匹配的第一条记录
    ///
    /// 返回 nil 表示 Keychain 中没有对应的 API Key（用户尚未配置）。
    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "apiKey",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 从 Keychain 中删除 API Key。
    ///
    /// `SecItemDelete` 会删除所有匹配 service + account 的记录。
    /// 特殊处理 `errSecItemNotFound`——如果 Keychain 中没有对应的记录，
    /// 不作为错误处理（因为删除一个不存在的条目本身也是成功的结果）。
    static func deleteAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "apiKey"
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    /// 封装 Keychain 操作中可能发生的错误。
    ///
    /// 遵循 `LocalizedError` 协议，使得错误可以被 SwiftUI 的错误处理机制
    /// 以用户友好的方式显示。
    enum KeychainError: LocalizedError {
        case unhandled(OSStatus)
        var errorDescription: String? {
            switch self {
            case .unhandled(let status): return "Keychain 错误 (\(status))"
            }
        }
    }
}