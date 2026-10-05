import Foundation

struct LoomBackup: Codable {
    var version = 1
    var createdAt = Date()
    var state: SavedState
    var keys: [String: String]? = nil

    func validate() throws {
        func require(_ valid: Bool) throws {
            if !valid { throw RelayClient.ClientError(message: "备份格式无效，或版本暂不支持。原有记录未被替换。") }
        }
        func unique<T: Hashable>(_ values: [T]) -> Bool { Set(values).count == values.count }
        try require(version == 1 && (1...5).contains(state.configurations.count) && !state.conversations.isEmpty)
        try require(unique(state.configurations.map(\.id)) && unique(state.conversations.map(\.id)))
        let configs = state.configurations + state.conversations.flatMap { $0.threads.map(\.configuration) }
        for config in configs {
            let url = URL(string: config.endpoint)
            try require(url?.scheme == "https" && url?.host != nil && url?.user == nil && url?.password == nil && url?.query == nil && url?.fragment == nil)
        }
        let ids = Set(configs.map { $0.id.uuidString })
        try require(keys?.keys.allSatisfy { ids.contains($0) } ?? true)
        for conversation in state.conversations {
            try require((1...5).contains(conversation.threads.count) && unique(conversation.threads.map(\.id)) && conversation.round >= 0)
            for thread in conversation.threads {
                try require(unique(thread.messages.map(\.id)))
                for message in thread.messages {
                    try require(["user", "assistant"].contains(message.role) && message.round >= 0)
                    for mark in message.highlights {
                        try require(mark.location >= 0 && mark.length > 0 && mark.location <= Int.max - mark.length)
                    }
                }
            }
        }
    }
}
