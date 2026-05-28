import Foundation
import PDFConverterCore

/// DeepSeek Chat API 的 Swift 客户端，兼容 OpenAI API 格式。
///
/// DeepSeek 的 API 设计与 OpenAI 的 Chat Completions API 完全兼容，
/// 因此可以使用标准的 OpenAI 客户端模式来调用。只需要将 Base URL 设为
/// DeepSeek 的 API 地址，并使用 DeepSeek 的 API Key 即可。
struct DeepSeekClient: Sendable {
    /// 聊天消息，对应 API 中 `messages` 数组的元素。
    /// - `role`: 角色标识（"system"、"user"、"assistant"）
    /// - `content`: 消息正文
    struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    /// 聊天请求体，对应 POST `/v1/chat/completions` 的完整 JSON。
    /// - `model`: 模型名称，如 "deepseek-chat"
    /// - `messages`: 消息数组，至少包含一条 system 和一条 user 消息
    /// - `temperature`: 随机性参数（0~2），越低越确定
    /// - `max_tokens`: 生成的最大 Token 数
    struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let max_tokens: Int
    }

    /// 聊天响应体，从中提取 `choices[0].message.content`。
    struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    /// API 错误响应体，用于提取错误信息。
    /// DeepSeek/OpenAI 的错误格式：`{ "error": { "message": "..." } }`
    struct APIErrorBody: Decodable {
        struct Detail: Decodable {
            let message: String?
        }
        let error: Detail?
    }

    let baseURL: String
    let apiKey: String
    let model: String

    /// 发送聊天请求并返回模型生成的文本。
    ///
    /// 完整流程：
    /// 1. 构建请求 URL（`{baseURL}/v1/chat/completions`）
    /// 2. 设置 Authorization 头（`Bearer {apiKey}`）
    /// 3. 编码请求体为 JSON
    /// 4. 发送 POST 请求（超时 120 秒）
    /// 5. 检查 HTTP 状态码（非 200 时提取错误信息并抛出）
    /// 6. 解码响应 JSON，提取首个 choice 的 message.content
    func complete(system: String, user: String, temperature: Double = 0.3, maxTokens: Int = 4096) async throws -> String {
        let root = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(root)/v1/chat/completions") else {
            throw ConversionError.aiRequestFailed("无效的 API 地址")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: user)
            ],
            temperature: temperature,
            max_tokens: maxTokens
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ConversionError.aiRequestFailed("无有效 HTTP 响应")
        }

        if http.statusCode != 200 {
            let message = parseErrorMessage(data) ?? "HTTP \(http.statusCode)"
            throw ConversionError.aiRequestFailed(message)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw ConversionError.aiRequestFailed("模型返回空内容")
        }
        return content
    }

    /// 从 API 错误响应的 JSON 中提取 `error.message` 字段。
    /// 如果解析失败或字段不存在，返回 nil，调用方会使用 HTTP 状态码作为后备错误信息。
    private func parseErrorMessage(_ data: Data) -> String? {
        (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error?.message
    }
}