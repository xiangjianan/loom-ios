import Foundation

/// All model discovery and chat requests go directly to the configured provider.
struct ProviderClient: Sendable {
    var session: URLSession = secureSession
    static let secureSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 150
        return URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }()
    private final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    private struct OpenAIRequest: Encodable {
        let model: String
        let messages: [APIMessage]
        let stream = false
    }
    private struct AnthropicRequest: Encodable {
        let model: String
        let messages: [APIMessage]
        let max_tokens = 8192
    }
    private struct ChatResponse: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
        struct Block: Decodable { let type: String; let text: String? }
        var choices: [Choice]?
        var content: [Block]?
    }
    private struct ModelResponse: Decodable {
        struct Model: Decodable {
            let id: String
            var display_name: String?
            var name: String?
        }
        let data: [Model]
        var has_more: Bool?
        var last_id: String?
    }
    private struct ErrorResponse: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
    func chat(configuration: ModelConfiguration, key: String, messages: [APIMessage]) async throws -> String {
        let anthropic = configuration.protocolKind == .anthropic
        var request = try request(configuration: configuration, key: key, path: anthropic ? "messages" : "chat/completions")
        request.httpMethod = "POST"
        request.httpBody = anthropic ? try JSONEncoder().encode(AnthropicRequest(model: configuration.model, messages: messages))
                                    : try JSONEncoder().encode(OpenAIRequest(model: configuration.model, messages: messages))
        let data = try await perform(request, key: key)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        let answer = anthropic ? response.content?.filter { $0.type == "text" }.compactMap(\.text).joined(separator: "\n\n")
                               : response.choices?.first?.message.content
        guard let answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RelayClient.ClientError(message: "模型没有返回文本，请检查型号或额度。")
        }
        return answer
    }
    func models(configuration: ModelConfiguration, key: String) async throws -> [AvailableModel] {
        var models: [AvailableModel] = []
        var after: String?
        for _ in 0..<20 {
            var request = try request(configuration: configuration, key: key, path: "models")
            if configuration.protocolKind == .anthropic {
                var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                url.queryItems = [URLQueryItem(name: "limit", value: "100")]
                if let after { url.queryItems!.append(URLQueryItem(name: "after_id", value: after)) }
                request.url = url.url
            }
            let data = try await perform(request, key: key)
            let response = try JSONDecoder().decode(ModelResponse.self, from: data)
            models.append(contentsOf: response.data.map { AvailableModel(id: $0.id, name: $0.display_name ?? $0.name) })
            guard configuration.protocolKind == .anthropic, response.has_more == true, let next = response.last_id, next != after else { break }
            after = next
        }
        var seen: Set<String> = []
        return models.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
    }
    private func request(configuration: ModelConfiguration, key: String, path: String) throws -> URLRequest {
        guard let base = URL(string: configuration.endpoint), base.scheme == "https", base.host != nil,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else {
            throw RelayClient.ClientError(message: "模型接入地址必须是有效的 HTTPS 地址。")
        }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.timeoutInterval = path == "models" ? 30 : 150
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if configuration.protocolKind == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        return request
    }
    private func perform(_ request: URLRequest, key: String) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RelayClient.ClientError(message: "网络响应无效。") }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data).error.message)
                ?? ((300..<400).contains(http.statusCode) ? "接口返回重定向，请填写服务商的最终接入地址。" : "模型请求失败（HTTP \(http.statusCode)）。")
            throw RelayClient.ClientError(message: key.isEmpty ? detail : detail.replacingOccurrences(of: key, with: "[REDACTED]"))
        }
        return data
    }
}
