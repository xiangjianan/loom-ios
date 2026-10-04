import Foundation

struct ModelConfiguration: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var endpoint: String
    var model: String
    var protocolKind: APIProtocol = .openAI

    enum APIProtocol: String, Codable, CaseIterable, Sendable {
        case openAI = "openai"
        case anthropic
        var title: String { self == .openAI ? "OpenAI 兼容" : "Anthropic" }
    }

    static let defaults = [
        ModelConfiguration(name: "OpenAI", endpoint: "https://api.openai.com/v1", model: ""),
        ModelConfiguration(name: "Claude", endpoint: "https://api.anthropic.com/v1", model: "", protocolKind: .anthropic)
    ]
}

struct Highlight: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var location: Int
    var length: Int
    var text: String
    var range: NSRange { NSRange(location: location, length: length) }
    func overlaps(_ other: NSRange) -> Bool { NSIntersectionRange(range, other).length > 0 }
}

struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var role: String
    var content: String
    var display: String? = nil
    var references: [Quote]? = nil
    var round: Int
    var highlights: [Highlight] = []
    var error: Bool = false
    var pending: Bool = false
}

struct ModelThread: Codable, Identifiable, Equatable, Sendable {
    var configuration: ModelConfiguration
    var messages: [ChatMessage] = []
    var id: UUID { configuration.id }
}

struct Quote: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var text: String
    var modelName: String
    var model: String
    var round: Int
}

struct Conversation: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title = "新对话"
    var updated = Date()
    var threads: [ModelThread]
    var round = 0
    var draft = ""
    var quotes: [Quote] = []
}

struct SavedState: Codable {
    var configurations: [ModelConfiguration]
    var conversations: [Conversation]
    var selectedConversation: UUID?
    var relayURL: String
    var useRelay: Bool? = nil
    var singleTapHighlight: Bool? = nil
    var highlightGesture: String? = nil
}

struct APIMessage: Codable, Equatable, Sendable {
    var role: String
    var content: String
}

struct AvailableModel: Decodable, Identifiable, Sendable {
    var id: String
    var name: String?
}

extension Conversation {
    static func prompt(_ text: String, quotes: [Quote]) -> String {
        guard !quotes.isEmpty else { return text }
        return text + "\n\n请结合以下高亮参考内容继续思考：\n" + quotes.map {
            "【\($0.modelName) / \($0.model) · 第 \($0.round) 轮】\n\($0.text)"
        }.joined(separator: "\n\n")
    }
}

// After a failed model round, merge adjacent user turns for providers requiring alternating roles.
extension ModelThread {
    var requestMessages: [APIMessage] {
        messages.filter { !$0.error && !$0.pending }.reduce(into: []) { result, message in
            if result.last?.role == message.role {
                result[result.count - 1].content += "\n\n" + message.content
            } else { result.append(APIMessage(role: message.role, content: message.content)) }
        }
    }
}
