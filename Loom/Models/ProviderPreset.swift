import Foundation

struct ProviderPreset: Identifiable, Sendable {
    let id: String
    let title: String
    let name: String
    let endpoint: String
    var protocolKind: ModelConfiguration.APIProtocol = .openAI

    static let all: [ProviderPreset] = [
        .init(id: "openai", title: "OpenAI · GPT", name: "OpenAI", endpoint: "https://api.openai.com/v1"),
        .init(id: "anthropic", title: "Anthropic · Claude", name: "Claude", endpoint: "https://api.anthropic.com/v1", protocolKind: .anthropic),
        .init(id: "google", title: "Google · Gemini", name: "Gemini", endpoint: "https://generativelanguage.googleapis.com/v1beta/openai"),
        .init(id: "deepseek", title: "DeepSeek", name: "DeepSeek", endpoint: "https://api.deepseek.com/v1"),
        .init(id: "qwen", title: "阿里云 · 千问（中国内地）", name: "千问", endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1"),
        .init(id: "kimi", title: "月之暗面 · Kimi（中国内地）", name: "Kimi", endpoint: "https://api.moonshot.cn/v1"),
        .init(id: "zhipu", title: "智谱 · GLM", name: "GLM", endpoint: "https://open.bigmodel.cn/api/paas/v4"),
        .init(id: "xai", title: "xAI · Grok", name: "Grok", endpoint: "https://api.x.ai/v1")
    ]
    static func matching(_ configuration: ModelConfiguration) -> ProviderPreset? {
        all.first { $0.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == configuration.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) && $0.protocolKind == configuration.protocolKind }
    }
    func apply(to configuration: inout ModelConfiguration) {
        configuration.name = name
        configuration.endpoint = endpoint
        configuration.protocolKind = protocolKind
        configuration.model = ""
    }
}

struct ModelDiscoveryInput: Hashable {
    let endpoint: String
    let protocolKind: String
    let key: String
    let relay: String?
    var valid: Bool {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: endpoint), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        return true
    }
}
