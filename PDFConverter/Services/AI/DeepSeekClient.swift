import Foundation
import PDFConverterCore

/// OpenAI-compatible client for DeepSeek Chat API.
struct DeepSeekClient: Sendable {
    struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let max_tokens: Int
    }

    struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    struct APIErrorBody: Decodable {
        struct Detail: Decodable {
            let message: String?
        }
        let error: Detail?
    }

    let baseURL: String
    let apiKey: String
    let model: String

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

    private func parseErrorMessage(_ data: Data) -> String? {
        (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error?.message
    }
}
