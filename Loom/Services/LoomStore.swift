import Foundation
import Observation

@MainActor @Observable
final class LoomStore {
    private(set) var configurations: [ModelConfiguration]
    private(set) var conversations: [Conversation]
    var selectedConversation: UUID
    var selectedModel: UUID
    var singleTapHighlight: Bool
    var notice: String?
    private(set) var busyModels: Set<UUID> = []
    private(set) var pendingRoundStarts: [UUID: UUID] = [:]

    func takeRoundStart(for threadID: UUID) -> UUID? { pendingRoundStarts.removeValue(forKey: threadID) }
    @ObservationIgnored private var requests: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let keychain = KeychainStore()
    @ObservationIgnored private var canSave = true
    @ObservationIgnored private let demo: Bool

    var current: Conversation { conversations.first(where: { $0.id == selectedConversation }) ?? conversations[0] }
    var isWorking: Bool { !busyModels.isEmpty }
    var visibleThreads: [ModelThread] { current.threads.filter { isModelEnabled($0.id) } }

    func isModelEnabled(_ id: UUID) -> Bool {
        configurations.first(where: { $0.id == id })?.isEnabled ?? true
    }

    func setModelEnabled(_ id: UUID, enabled: Bool) {
        guard !isWorking, let index = configurations.firstIndex(where: { $0.id == id }) else { return }
        configurations[index].enabled = enabled
        ensureSelection()
        save()
    }
    var draft: String {
        get { current.draft }
        set { mutateCurrent { $0.draft = newValue }; save() }
    }

    init(fileURL: URL? = nil, demo: Bool = false, session: URLSession = ProviderClient.secureSession) {
        self.session = session
        self.demo = demo
        self.fileURL = fileURL ?? URL.applicationSupportDirectory.appending(path: "Loom/state.json")
        var state: SavedState?
        var loadError: String?
        if !demo, FileManager.default.fileExists(atPath: self.fileURL.path) {
            do {
                let decoded = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: self.fileURL))
                guard decoded.configurations.count <= 5,
                      decoded.conversations.allSatisfy({ !$0.threads.isEmpty && $0.threads.count <= 5 }) else {
                    throw RelayClient.ClientError(message: "本地模型配置无效。")
                }
                state = decoded
            }
            catch { loadError = "本地记录读取失败，原文件已保留。本次更改不会覆盖它。\(error.localizedDescription)" }
        }
        let configs = state?.configurations.isEmpty == false ? state!.configurations : ModelConfiguration.defaults
        configurations = configs
        singleTapHighlight = state?.highlightGesture != "double"
        let initial = Conversation(threads: configs.map { ModelThread(configuration: $0) })
        let loaded = state?.conversations.isEmpty == false ? state!.conversations : [initial]
        conversations = loaded
        let requestedID = state?.selectedConversation ?? loaded[0].id
        let selected = loaded.first(where: { $0.id == requestedID }) ?? loaded[0]
        selectedConversation = selected.id
        selectedModel = selected.threads.first?.id ?? configs[0].id
        notice = loadError
        canSave = loadError == nil
        for c in conversations.indices {
            for t in conversations[c].threads.indices {
                for m in conversations[c].threads[t].messages.indices {
                    conversations[c].threads[t].messages[m].recoverSentReferences()
                }
                for m in conversations[c].threads[t].messages.indices where conversations[c].threads[t].messages[m].pending {
                    conversations[c].threads[t].messages[m].pending = false
                    conversations[c].threads[t].messages[m].error = true
                    conversations[c].threads[t].messages[m].content = "上次请求因应用退出而中断，可以重试。"
                }
            }
        }
        if demo {
            seedDemo()
            if ProcessInfo.processInfo.arguments.contains("--demo-markdown") {
                mutateCurrent { $0.threads[0].messages[1].content = MarkdownPreview.content }
            }
            if ProcessInfo.processInfo.arguments.contains("--demo-svg") { mutateCurrent { $0.threads[0].messages[1].content = ReadingPreview.svg } }
            if ProcessInfo.processInfo.arguments.contains("--demo-rounds") {
                mutateCurrent { conversation in
                    conversation.round = 4
                    for index in conversation.threads.indices {
                        let config = conversation.threads[index].configuration
                        conversation.threads[index].messages = (1...4).flatMap { round in
                            let quote = Quote(id: UUID(), text: "这是上一轮保留的高亮观点。", modelName: config.name, model: config.model, round: round - 1)
                            return [
                                ChatMessage(role: "user", content: "继续讨论第\(round)轮的问题", display: "继续讨论第\(round)轮的问题", references: round > 1 ? [quote] : nil, round: round),
                                ChatMessage(role: "assistant", content: (1...10).map { "第\(round)轮 · 第\($0)段：这是一段可滚动的多轮回答。每个模型应该记住自己的阅读位置，轮次标记可以直接跳转。" }.joined(separator: "\n\n"), round: round)
                            ]
                        }
                    }
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--demo-long") { mutateCurrent { $0.threads[0].messages[1].content = ReadingPreview.long } }
        }
        ensureSelection()
    }

    func discoverModels(configuration: ModelConfiguration, key: String) async throws -> [AvailableModel] {
        return try await ProviderClient(session: session).models(configuration: configuration, key: key)
    }

    func key(for id: UUID) -> String { keychain.read(id) }

    func saveConfiguration(_ updated: ModelConfiguration, key: String) throws {
        var configuration = updated
        let originalID = updated.id
        guard !isWorking else { throw RelayClient.ClientError(message: "请等待回答完成后再修改模型。") }
        guard let url = URL(string: configuration.endpoint), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw RelayClient.ClientError(message: "模型接入地址必须是有效的 HTTPS 地址。")
        }
        guard !configuration.name.trimmingCharacters(in: .whitespaces).isEmpty,
              !configuration.model.trimmingCharacters(in: .whitespaces).isEmpty, !key.isEmpty else {
            throw RelayClient.ClientError(message: "请填写名称、模型型号和 API Key。")
        }
        guard configurations.contains(where: { $0.id == configuration.id }) || configurations.count < 5 else {
            throw RelayClient.ClientError(message: "最多可配置五个模型。")
        }
        // A provider change must never replace credentials used by archived provider threads.
        if let old = configurations.first(where: { $0.id == originalID }),
           (old.endpoint != configuration.endpoint || old.protocolKind != configuration.protocolKind),
           conversations.contains(where: { $0.threads.contains(where: { $0.id == originalID && !$0.messages.isEmpty }) }) {
            configuration.id = UUID()
        }
        try keychain.write(key, for: configuration.id)
        if let index = configurations.firstIndex(where: { $0.id == originalID }) {
            configurations[index] = configuration
        } else {
            guard configurations.count < 5 else { throw RelayClient.ClientError(message: "最多可配置五个模型。") }
            configurations.append(configuration)
        }
        // Existing conversation model identity stays immutable once messages exist.
        mutateCurrent { conversation in
            if let index = conversation.threads.firstIndex(where: { $0.id == originalID }) {
                if conversation.threads[index].messages.isEmpty { conversation.threads[index].configuration = configuration }
            } else if conversation.round == 0 { conversation.threads.append(ModelThread(configuration: configuration)) }
        }
        ensureSelection(); save()
    }

    func removeConfiguration(_ id: UUID) throws {
        guard !isWorking, configurations.count > 1 else { return }
        // Keep credentials while archived threads still reference them.
        if !conversations.contains(where: { $0.threads.contains(where: { $0.id == id && !$0.messages.isEmpty }) }) {
            try keychain.write("", for: id)
        }
        configurations.removeAll { $0.id == id }
        mutateCurrent { conversation in
            conversation.threads.removeAll { $0.id == id && $0.messages.isEmpty }
            if conversation.threads.isEmpty { conversation.threads = [ModelThread(configuration: configurations[0])] }
        }
        ensureSelection(); save()
    }

    func newConversation() {
        cancelAll()
        pendingRoundStarts.removeAll()
        conversations.removeAll { $0.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.quotes.isEmpty && $0.threads.allSatisfy { $0.messages.isEmpty } }
        let conversation = Conversation(threads: configurations.map { ModelThread(configuration: $0) })
        conversations.insert(conversation, at: 0)
        selectedConversation = conversation.id
        selectedModel = conversation.threads[0].id
        ensureSelection(); save()
    }

    func selectConversation(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        guard id != selectedConversation else { return }
        cancelAll(); pendingRoundStarts.removeAll()
        conversations.removeAll { $0.id == selectedConversation && $0.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.quotes.isEmpty && $0.threads.allSatisfy { $0.messages.isEmpty } }
        selectedConversation = id; ensureSelection(); save()
    }

    func deleteConversation(_ id: UUID) {
        if selectedConversation == id { cancelAll(); pendingRoundStarts.removeAll() }
        conversations.removeAll { $0.id == id }
        if conversations.isEmpty { newConversation() }
        else if selectedConversation == id { selectedConversation = conversations[0].id; ensureSelection() }
        save()
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        guard !visibleThreads.isEmpty else { notice = "请先启用至少一个模型。"; return }
        let enabledIDs = Set(visibleThreads.map(\.id))
        for thread in visibleThreads {
            if demo && ProcessInfo.processInfo.arguments.contains("--demo-next-round") { continue }
            guard !thread.configuration.model.isEmpty, !key(for: thread.id).isEmpty else {
                notice = "请先在模型设置里配置 \(thread.configuration.name) 的型号和 API Key。"
                return
            }
        }
        let references = current.quotes
        let content = Conversation.prompt(text, quotes: references)
        mutateCurrent { conversation in
            conversation.round += 1
            if conversation.round == 1 { conversation.title = String(text.prefix(60)) }
            conversation.draft = ""
            conversation.quotes = []
            for index in conversation.threads.indices where enabledIDs.contains(conversation.threads[index].id) {
                conversation.threads[index].messages.append(ChatMessage(role: "user", content: content, display: text, references: references.isEmpty ? nil : references, round: conversation.round))
            }
        }
        for thread in visibleThreads {
            pendingRoundStarts[thread.id] = thread.messages.last?.id
            startRequest(threadID: thread.id)
        }
        save()
    }

    func retry(_ threadID: UUID) {
        guard !isWorking, isModelEnabled(threadID), let thread = current.threads.first(where: { $0.id == threadID }),
              thread.messages.last?.error == true else { return }
        guard !key(for: threadID).isEmpty else { notice = "请先配置 API Key。"; return }
        mutateCurrent { conversation in
            guard let index = conversation.threads.firstIndex(where: { $0.id == threadID }) else { return }
            conversation.threads[index].messages.removeLast()
        }
        startRequest(threadID: threadID); save()
    }

    private func startRequest(threadID: UUID) {
        let conversationID = selectedConversation
        guard isModelEnabled(threadID), let thread = current.threads.first(where: { $0.id == threadID }) else { return }
        let messages = thread.requestMessages
        let key = key(for: threadID)
        let placeholder = ChatMessage(role: "assistant", content: "", round: current.round, pending: true)
        mutateCurrent { conversation in
            guard let index = conversation.threads.firstIndex(where: { $0.id == threadID }) else { return }
            conversation.threads[index].messages.append(placeholder)
        }
        busyModels.insert(threadID)
        let direct = ProviderClient(session: session)
        requests[threadID] = Task { [weak self] in
            do {
                let answer: String
                if self?.demo == true && ProcessInfo.processInfo.arguments.contains("--demo-next-round") {
                    try await Task.sleep(for: .milliseconds(600))
                    answer = ReadingPreview.long
                } else { answer = try await direct.chat(configuration: thread.configuration, key: key, messages: messages) }
                try Task.checkCancellation()
                self?.finish(conversationID, threadID: threadID, messageID: placeholder.id, text: answer, error: false)
            } catch {
                let text = Task.isCancelled ? "已停止生成，可以重试。" : error.localizedDescription
                self?.finish(conversationID, threadID: threadID, messageID: placeholder.id, text: text, error: true)
            }
        }
    }

    private func finish(_ conversationID: UUID, threadID: UUID, messageID: UUID, text: String, error: Bool) {
        guard let c = conversations.firstIndex(where: { $0.id == conversationID }),
              let t = conversations[c].threads.firstIndex(where: { $0.id == threadID }),
              let m = conversations[c].threads[t].messages.firstIndex(where: { $0.id == messageID }),
              conversations[c].threads[t].messages[m].pending else { return }
        conversations[c].threads[t].messages[m].content = text
        conversations[c].threads[t].messages[m].pending = false
        conversations[c].threads[t].messages[m].error = error
        let round = conversations[c].threads[t].messages[m].round
        pendingRoundStarts[threadID] = conversations[c].threads[t].messages.first(where: { $0.round == round && $0.role == "user" })?.id
        conversations[c].updated = Date()
        busyModels.remove(threadID); requests[threadID] = nil; save()
    }

    func cancelAll() {
        for (threadID, task) in Array(requests) {
            task.cancel()
            if let pending = current.threads.first(where: { $0.id == threadID })?.messages.last, pending.pending {
                finish(selectedConversation, threadID: threadID, messageID: pending.id, text: "已停止生成，可以重试。", error: true)
            }
        }
        requests.removeAll(); busyModels.removeAll(); save()
    }

    func highlight(threadID: UUID, messageID: UUID, range: NSRange, text: String) {
        guard range.length > 0, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        mutateCurrent { conversation in
            guard let t = conversation.threads.firstIndex(where: { $0.id == threadID }),
                  let m = conversation.threads[t].messages.firstIndex(where: { $0.id == messageID }) else { return }
            let rendered = AnswerRenderer.render(conversation.threads[t].messages[m].content).string
            conversation.threads[t].messages[m].highlights = conversation.threads[t].messages[m].highlights.compactMap { HighlightResolver.resolve($0, in: rendered) }
            let source = rendered as NSString
            guard range.location >= 0, NSMaxRange(range) <= source.length else { return }
            var combined = range
            var mergedIDs = Set<UUID>()
            // Repeat so filling a gap joins both neighboring groups, regardless of insertion order.
            var changed = true
            while changed {
                changed = false
                for mark in conversation.threads[t].messages[m].highlights where !mergedIDs.contains(mark.id) {
                    let gapStart = min(NSMaxRange(mark.range), NSMaxRange(combined))
                    let gapEnd = max(mark.location, combined.location)
                    let adjacent = gapEnd <= gapStart ||
                        source.substring(with: NSRange(location: gapStart, length: gapEnd - gapStart))
                            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if adjacent {
                        combined = NSUnionRange(combined, mark.range)
                        mergedIDs.insert(mark.id)
                        changed = true
                    }
                }
            }
            if mergedIDs.count == 1,
               conversation.threads[t].messages[m].highlights.contains(where: { mergedIDs.contains($0.id) && $0.range == combined }) { return }
            conversation.threads[t].messages[m].highlights.removeAll { mergedIDs.contains($0.id) }
            conversation.quotes.removeAll { mergedIDs.contains($0.id) }
            let combinedText = source.substring(with: combined)
            let highlight = Highlight(location: combined.location, length: combined.length, text: combinedText)
            conversation.threads[t].messages[m].highlights.append(highlight)
            let config = conversation.threads[t].configuration
            conversation.quotes.append(Quote(id: highlight.id, text: combinedText, modelName: config.name,
                                             model: config.model, round: conversation.threads[t].messages[m].round))
        }
        save()
    }

    func toggleHighlight(threadID: UUID, messageID: UUID, range: NSRange, text: String) {
        guard let message = current.threads.first(where: { $0.id == threadID })?.messages.first(where: { $0.id == messageID }) else { return }
        let rendered = AnswerRenderer.render(message.content).string
        if let existing = message.highlights.compactMap({ HighlightResolver.resolve($0, in: rendered) }).first(where: { NSIntersectionRange($0.range, range).length > 0 }) {
            removeQuote(existing.id)
        } else {
            highlight(threadID: threadID, messageID: messageID, range: range, text: text)
        }
    }

    func removeQuote(_ id: UUID) {
        mutateCurrent { conversation in
            conversation.quotes.removeAll { $0.id == id }
            for t in conversation.threads.indices {
                for m in conversation.threads[t].messages.indices {
                    conversation.threads[t].messages[m].highlights.removeAll { $0.id == id }
                }
            }
        }
        save()
    }
    func clearHighlights() {
        mutateCurrent { conversation in
            conversation.quotes = []
            for t in conversation.threads.indices {
                for m in conversation.threads[t].messages.indices { conversation.threads[t].messages[m].highlights = [] }
            }
        }
        save()
    }
    private func ensureSelection() {
        if !visibleThreads.contains(where: { $0.id == selectedModel }), let first = visibleThreads.first { selectedModel = first.id }
    }
    private func mutateCurrent(_ body: (inout Conversation) -> Void) {
        guard let index = conversations.firstIndex(where: { $0.id == selectedConversation }) else { return }
        body(&conversations[index]); conversations[index].updated = Date()
    }
    private var savedState: SavedState {
        SavedState(configurations: configurations, conversations: conversations, selectedConversation: selectedConversation,
                   relayURL: "", useRelay: false, singleTapHighlight: singleTapHighlight,
                   highlightGesture: singleTapHighlight ? "single" : "double")
    }

    func backup(includeKeys: Bool) throws -> Data {
        let configs = configurations + conversations.flatMap { $0.threads.map(\.configuration) }
        var keys: [String: String] = [:]
        if includeKeys {
            for config in configs {
                let key = keychain.read(config.id)
                if !key.isEmpty { keys[config.id.uuidString] = key }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(LoomBackup(state: savedState, keys: includeKeys ? keys : nil))
    }

    func restore(_ archive: LoomBackup) throws {
        try archive.validate()
        var state = archive.state
        for c in state.conversations.indices {
            for t in state.conversations[c].threads.indices {
                for m in state.conversations[c].threads[t].messages.indices {
                    state.conversations[c].threads[t].messages[m].recoverSentReferences()
                    if state.conversations[c].threads[t].messages[m].pending {
                        state.conversations[c].threads[t].messages[m].pending = false
                        state.conversations[c].threads[t].messages[m].error = true
                        state.conversations[c].threads[t].messages[m].content = "备份中的请求尚未完成，可以重试。"
                    }
                }
            }
        }
        let data = try JSONEncoder().encode(state)
        let folder = fileURL.deletingLastPathComponent()
        if !demo {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Preserve the exact previous file, including an unreadable local state.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let previous = try Data(contentsOf: fileURL)
                try previous.write(to: folder.appending(path: "before-import-\(UUID().uuidString).json"), options: [.atomic, .completeFileProtection])
            }
        }
        var previousKeys: [UUID: String] = [:]
        do {
            for (rawID, value) in archive.keys ?? [:] {
                guard let id = UUID(uuidString: rawID) else { continue }
                previousKeys[id] = keychain.read(id)
                try keychain.write(value, for: id)
            }
            if !demo { try data.write(to: fileURL, options: [.atomic, .completeFileProtection]) }
        } catch {
            for (id, key) in previousKeys { try? keychain.write(key, for: id) }
            throw error
        }
        // Do not save the outgoing state over the successfully imported file.
        for task in requests.values { task.cancel() }
        requests.removeAll(); busyModels.removeAll(); pendingRoundStarts.removeAll()
        configurations = state.configurations
        conversations = state.conversations
        selectedConversation = conversations.first(where: { $0.id == state.selectedConversation })?.id ?? conversations[0].id
        selectedModel = current.threads[0].id
        ensureSelection()
        singleTapHighlight = state.highlightGesture != "double"
        canSave = true
        notice = nil
    }

    func save() {
        guard !demo, canSave else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(SavedState(configurations: configurations, conversations: conversations,
                                                          selectedConversation: selectedConversation, relayURL: "", useRelay: false, singleTapHighlight: singleTapHighlight, highlightGesture: singleTapHighlight ? "single" : "double"))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch { notice = "本地保存失败：\(error.localizedDescription)" }
    }
    private func seedDemo() {
        mutateCurrent { conversation in
            conversation.title = "让不同的观点，在这里交织"
            conversation.round = 1
            for index in conversation.threads.indices {
                conversation.threads[index].configuration.model = index == 0 ? "示例模型 A" : "示例模型 B"
                conversation.threads[index].messages = [
                    ChatMessage(role: "user", content: "如何把一个模糊的想法，变成值得投入的产品？", round: 1),
                    ChatMessage(role: "assistant", content: index == 0 ? "**先找到值得解决的问题。**\n\n与其从功能清单开始，不如观察一个真实的时刻：谁在什么情境下，遇到了什么阻碍？\n\n1. 描述一个具体使用场景。\n2. 做出最小可用的体验。\n3. 看用户是否愿意再次使用。\n\n好的产品不是功能的总和，而是让一个重要的动作变得自然。\n\n选中你认同的句子，把它带进下一轮讨论。" : "**从最小的承诺开始。**\n\n一个想法是否值得投入，可以用三个问题来判断：\n\n• 问题是否反复出现？\n• 现有方案哪里令人不满意？\n• 新方案能否明显减少时间或精力？\n\n先让少数人用起来，再根据真实反馈调整。保持开放，让不同的观点帮助你发现盲点。", round: 1)
                ]
            }
        }
    }
}
