import Foundation

struct RelayClient: Sendable {
    static let defaultURL = "https://relay.minidesk.online:8443/loom"
    var baseURL: String
    var session: URLSession = ProviderClient.secureSession

    private struct Payload: Encodable {
        let endpoint: String
        let key: String
        let model: String
        let `protocol`: String
        var messages: [APIMessage]? = nil
    }
    private struct ChatResponse: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
        let choices: [Choice]
    }
    private struct ModelsResponse: Decodable { let models: [AvailableModel] }
    private struct Failure: Decodable { let error: String }

    func chat(configuration: ModelConfiguration, key: String, messages: [APIMessage]) async throws -> String {
        let payload = Payload(endpoint: configuration.endpoint, key: key, model: configuration.model,
                              protocol: configuration.protocolKind.rawValue, messages: messages)
        let data = try await post("api/chat", payload: payload, key: key)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let answer = response.choices.first?.message.content,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError(message: "模型没有返回文本，请检查型号或额度。")
        }
        return answer
    }

    func models(configuration: ModelConfiguration, key: String) async throws -> [AvailableModel] {
        let payload = Payload(endpoint: configuration.endpoint, key: key, model: configuration.model,
                              protocol: configuration.protocolKind.rawValue)
        return try JSONDecoder().decode(ModelsResponse.self, from: await post("api/models", payload: payload, key: key)).models
    }

    private func post(_ path: String, payload: Payload, key: String) async throws -> Data {
        guard let base = URL(string: baseURL), base.scheme == "https", base.host != nil,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else {
            throw ClientError(message: "转发服务地址必须是有效的 HTTPS 地址。")
        }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError(message: "网络响应无效。") }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "请求失败（HTTP \(http.statusCode)）。"
            throw ClientError(message: key.isEmpty ? message : message.replacingOccurrences(of: key, with: "[REDACTED]"))
        }
        return data
    }
    struct ClientError: LocalizedError { var message: String; var errorDescription: String? { message } }
}
