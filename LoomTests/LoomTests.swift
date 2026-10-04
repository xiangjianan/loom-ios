import XCTest
import UIKit
@testable import Loom

@MainActor final class LoomTests: XCTestCase {
    private func temporaryFile() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + "/state.json") }
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testSentenceRangesUseTerminalPunctuationAndPreserveUnicode() throws {
        let text = "第一句，包含逗号、顿号：分号前；分号后。第二句！第三句？\nEmoji 👨‍👩‍👧‍👦 和数字 3.14，同一句。 One sentence, with a colon: yes; after. Next!"
        let string = text as NSString
        for (word, expected) in [("包含", "包含逗号、顿号："), ("顿号", "包含逗号、顿号："), ("分号前", "分号前；"), ("分号后", "分号后。"), ("第二", "第二句！"), ("第三", "第三句？"), ("数字", "Emoji 👨‍👩‍👧‍👦 和数字 3.14，"), ("sentence", "One sentence,"), ("colon", "with a colon:"), ("yes", "yes;"), ("after", "after."), ("Next", "Next!")] {
            let range = try XCTUnwrap(SentenceSelection.range(in: text, at: string.range(of: word).location))
            XCTAssertEqual(string.substring(with: range), expected)
        }
        let quoted = "他说：‘这样很好！’下一句。"
        let range = try XCTUnwrap(SentenceSelection.range(in: quoted, at: 3))
        XCTAssertEqual((quoted as NSString).substring(with: range), "‘这样很好！’")
    }
    func testSentenceHighlightToggleDoesNotAffectOtherSentences() {
        let store = LoomStore(fileURL: temporaryFile(), demo: true)
        XCTAssertTrue(store.singleTapHighlight)
        let thread = store.current.threads[0]
        let message = thread.messages.first(where: { $0.role == "assistant" })!
        let text = AnswerRenderer.render(message.content).string as NSString
        let first = SentenceSelection.range(in: text as String, at: 0)!
        let second = SentenceSelection.range(in: text as String, at: NSMaxRange(first) + 1)!
        store.toggleHighlight(threadID: thread.id, messageID: message.id, range: first, text: text.substring(with: first))
        store.toggleHighlight(threadID: thread.id, messageID: message.id, range: second, text: text.substring(with: second))
        store.toggleHighlight(threadID: thread.id, messageID: message.id, range: first, text: text.substring(with: first))
        XCTAssertEqual(store.current.quotes.map(\.text), [text.substring(with: second)])
        XCTAssertEqual(store.current.threads[0].messages.first(where: { $0.id == message.id })!.highlights.map(\.range), [second])
    }
    func testSVGIsAnInlineAttachmentAndSurroundingTextRemainsSelectable() throws {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 200"><rect width="400" height="200" fill="blue"/><text x="10" y="40">SVG 图像</text></svg>"#
        let rendered = AnswerRenderer.render("前面的文字。\n\n```svg\n" + svg + "\n```\n\n后面的文字。")
        XCTAssertEqual(rendered.string, "前面的文字。\n\n￼\n后面的文字。".replacingOccurrences(of: "\n\n", with: "\n"))
        let range = (rendered.string as NSString).range(of: "￼")
        let attachment = try XCTUnwrap(rendered.attribute(.attachment, at: range.location, effectiveRange: nil) as? SVGTextAttachment)
        XCTAssertEqual(attachment.document.aspectRatio, 2)
        XCTAssertNotNil(attachment.image)
        XCTAssertFalse(attachment.document.html.contains("default-src *"))
        XCTAssertTrue(attachment.document.html.contains("default-src 'none'"))
        XCTAssertEqual(attachment.document.bounds(width: 300).height, 150)
        let raw = AnswerRenderer.render(svg)
        XCTAssertEqual(raw.string, "￼")
        let nested = svg.replacingOccurrences(of: "</svg>", with: "<svg viewBox='0 0 1 1'><circle r='1'/></svg></svg>")
        XCTAssertEqual(AnswerRenderer.render(nested).string, "￼")
        XCTAssertNil(SVGDocument("<svg><broken></svg>"))
    }

    func testSelectionAutoScrollContinuesAtEdgeAndStopsOnRelease() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 400, height: 820)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 100, width: 400, height: 500))
        controller.view.addSubview(scroll)
        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 400, height: 3000))
        textView.isEditable = false; textView.isSelectable = true; textView.isScrollEnabled = false
        textView.text = ReadingPreview.long
        scroll.addSubview(textView)
        scroll.contentSize = CGSize(width: 400, height: 3000)
        controller.view.layoutIfNeeded(); textView.layoutIfNeeded()
        textView.selectedRange = NSRange(location: 0, length: 3)
        let driver = SelectionAutoScroller(textView: textView)
        driver.attach()
        let end = try XCTUnwrap(textView.selectedTextRange).end
        let caret = textView.caretRect(for: end)
        let handle = textView.convert(CGPoint(x: caret.midX, y: caret.maxY), to: window)
        driver.touch(.began, point: handle)
        let edge = scroll.convert(CGPoint(x: 160, y: scroll.bounds.maxY - 2), to: window)
        driver.touch(.moved, point: edge)
        driver.step()
        let firstOffset = scroll.contentOffset.y
        for _ in 0..<25 { driver.step() }
        XCTAssertGreaterThan(firstOffset, 0)
        XCTAssertGreaterThan(scroll.contentOffset.y, firstOffset + 100)
        XCTAssertGreaterThan(textView.selectedRange.length, 3)
        driver.touch(.ended, point: edge)
        let stoppedOffset = scroll.contentOffset.y
        driver.step()
        XCTAssertEqual(scroll.contentOffset.y, stoppedOffset)
        driver.stop()
    }

    func testRemovingQuoteRemovesOnlyItsOriginalHighlight() {
        let store = LoomStore(fileURL: temporaryFile(), demo: true)
        let thread = store.current.threads[0]
        let message = thread.messages.first(where: { $0.role == "assistant" })!
        let text = AnswerRenderer.render(message.content).string as NSString
        let first = NSRange(location: 0, length: 2)
        let second = NSRange(location: 3, length: 2)
        store.highlight(threadID: thread.id, messageID: message.id, range: first, text: text.substring(with: first))
        store.highlight(threadID: thread.id, messageID: message.id, range: second, text: text.substring(with: second))
        let quotes = store.current.quotes
        XCTAssertEqual(quotes.count, 2)
        store.removeQuote(quotes[0].id)
        let marks = store.current.threads[0].messages.first(where: { $0.id == message.id })!.highlights
        XCTAssertEqual(marks.map(\.id), [quotes[1].id])
        XCTAssertEqual(store.current.quotes.map(\.id), [quotes[1].id])
    }

    func testChangingProviderPreservesArchivedCredentials() throws {
        let store = LoomStore(fileURL: temporaryFile(), demo: true)
        let originalID = store.configurations[0].id
        defer {
            for id in Set(store.configurations.map(\.id) + [originalID]) { try? KeychainStore().write("", for: id) }
        }
        var configuration = store.configurations[0]
        configuration.model = "old-model"
        try store.saveConfiguration(configuration, key: "old-provider-key")
        ProviderPreset.all.first(where: { $0.id == "deepseek" })!.apply(to: &configuration)
        configuration.model = "new-model"
        try store.saveConfiguration(configuration, key: "new-provider-key")
        let newID = store.configurations[0].id
        XCTAssertNotEqual(newID, originalID)
        XCTAssertEqual(store.key(for: originalID), "old-provider-key")
        XCTAssertEqual(store.key(for: newID), "new-provider-key")
        XCTAssertEqual(store.current.threads[0].id, originalID)
        store.newConversation()
        XCTAssertEqual(store.current.threads[0].id, newID)
    }

    func testProviderPresetsFillEndpointAndProtocol() {
        for preset in ProviderPreset.all {
            var configuration = ModelConfiguration(name: "Old", endpoint: "https://old.example", model: "old-model")
            let id = configuration.id
            preset.apply(to: &configuration)
            XCTAssertEqual(configuration.id, id)
            XCTAssertEqual(configuration.endpoint, preset.endpoint)
            XCTAssertEqual(configuration.protocolKind, preset.protocolKind)
            XCTAssertEqual(configuration.model, "")
            XCTAssertEqual(ProviderPreset.matching(configuration)?.id, preset.id)
        }
        XCTAssertFalse(ModelDiscoveryInput(endpoint: "http://example.com", protocolKind: "openai", key: "key", relay: nil).valid)
        XCTAssertFalse(ModelDiscoveryInput(endpoint: "https://example.com", protocolKind: "openai", key: "   ", relay: nil).valid)
    }

    func testReferencesIncludeSourceAndRound() {
        let quote = Quote(id: UUID(), text: "一个重要的观点", modelName: "Claude", model: "model-b", round: 2)
        let prompt = Conversation.prompt("继续", quotes: [quote])
        XCTAssertTrue(prompt.contains("【Claude / model-b · 第 2 轮】"))
        XCTAssertTrue(prompt.contains(quote.text))
        XCTAssertEqual(Conversation.prompt("问题", quotes: []), "问题")
    }

    func testFullMarkdownStructureAndStyling() throws {
        let rendered = AnswerRenderer.render(MarkdownPreview.content)
        XCTAssertTrue(rendered.string.contains("从一个想法开始\n"))
        XCTAssertFalse(rendered.string.contains("# 从"))
        XCTAssertFalse(rendered.string.contains("```"))
        XCTAssertFalse(rendered.string.contains("| --- |"))
        XCTAssertTrue(rendered.string.contains("•\t找到真实的问题"))
        XCTAssertTrue(rendered.string.contains("模型\t擅长"))
        let title = (rendered.string as NSString).range(of: "从一个想法开始")
        let body = (rendered.string as NSString).range(of: "让 ")
        let titleFont = try XCTUnwrap(rendered.attribute(.font, at: title.location, effectiveRange: nil) as? UIFont)
        let bodyFont = try XCTUnwrap(rendered.attribute(.font, at: body.location, effectiveRange: nil) as? UIFont)
        XCTAssertGreaterThan(titleFont.pointSize, bodyFont.pointSize)
        let code = (rendered.string as NSString).range(of: "let idea")
        let codeFont = try XCTUnwrap(rendered.attribute(.font, at: code.location, effectiveRange: nil) as? UIFont)
        XCTAssertTrue(codeFont.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        let link = (rendered.string as NSString).range(of: "项目文档")
        XCTAssertNotNil(rendered.attribute(.link, at: link.location, effectiveRange: nil))
    }

    func testListsCodeAndInlineFormattingStaySeparate() {
        let rendered = AnswerRenderer.render("1. 第一项\n2. 第二项\n\n```text\n# 保留代码\n**不是粗体**\n```\n\n~~删除~~")
        XCTAssertTrue(rendered.string.contains("1.\t第一项\n2.\t第二项"))
        XCTAssertTrue(rendered.string.contains("# 保留代码\n**不是粗体**"))
        let range = (rendered.string as NSString).range(of: "删除")
        XCTAssertNotNil(rendered.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil))
    }

    func testOldHighlightReanchorsAfterMarkdownRendering() throws {
        let text = AnswerRenderer.render("# 标题\n\n**观点** 和后续内容").string
        let old = Highlight(location: 8, length: 2, text: "观点")
        let resolved = try XCTUnwrap(HighlightResolver.resolve(old, in: text))
        XCTAssertEqual((text as NSString).substring(with: resolved.range), old.text)
        XCTAssertEqual(resolved.id, old.id)
        let oldHeading = Highlight(location: 0, length: 4, text: "# 标题")
        XCTAssertEqual(HighlightResolver.resolve(oldHeading, in: text)?.text, "标题")
    }

    func testSelectionRangesMatchRenderedUnicode() {
        let rendered = AnswerRenderer.render("**你好** 👩🏽‍💻，继续思考。")
        XCTAssertEqual(rendered.string, "你好 👩🏽‍💻，继续思考。")
        let range = (rendered.string as NSString).range(of: "👩🏽‍💻")
        XCTAssertEqual((rendered.string as NSString).substring(with: range), "👩🏽‍💻")
        let mark = Highlight(location: range.location, length: range.length, text: "👩🏽‍💻")
        XCTAssertTrue(mark.overlaps(NSRange(location: range.location + 1, length: 1)))
        XCTAssertFalse(mark.overlaps(NSRange(location: 0, length: 2)))
    }

    func testHighlightReplacesExpandedSelectionWithoutDuplicateQuotes() {
        let store = LoomStore(fileURL: temporaryFile(), demo: true)
        let thread = store.current.threads[0]
        let message = thread.messages[1]
        store.highlight(threadID: thread.id, messageID: message.id, range: NSRange(location: 0, length: 2), text: "先找")
        store.highlight(threadID: thread.id, messageID: message.id, range: NSRange(location: 0, length: 2), text: "先找")
        XCTAssertEqual(store.current.quotes.count, 1)
        store.highlight(threadID: thread.id, messageID: message.id, range: NSRange(location: 0, length: 5), text: "先找到值得")
        XCTAssertEqual(store.current.quotes.count, 1)
        XCTAssertEqual(store.current.threads[0].messages[1].highlights.count, 1)
        XCTAssertEqual(store.current.quotes[0].text, "先找到值得")
        store.clearHighlights()
        XCTAssertTrue(store.current.quotes.isEmpty)
        XCTAssertTrue(store.current.threads[0].messages[1].highlights.isEmpty)
    }

    func testDraftAndHistoryPersistWithoutCredentials() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = LoomStore(fileURL: file)
        let first = store.current.id
        store.draft = "留到下一次的问题"
        store.newConversation()
        store.draft = "新草稿"
        let restored = LoomStore(fileURL: file)
        XCTAssertEqual(restored.conversations.count, 2)
        XCTAssertEqual(restored.draft, "新草稿")
        restored.selectConversation(first)
        XCTAssertEqual(restored.draft, "留到下一次的问题")
        let json = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(json.contains("apiKey"))
        XCTAssertFalse(json.contains("Bearer"))
    }

    func testCorruptFileIsPreserved() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let broken = Data("not JSON".utf8)
        try broken.write(to: file)
        let store = LoomStore(fileURL: file)
        XCTAssertNotNil(store.notice)
        store.draft = "不覆盖原文件"
        XCTAssertEqual(try Data(contentsOf: file), broken)
    }

    func testInterruptedRequestRestoresAsRetryableError() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        var thread = ModelThread(configuration: ModelConfiguration.defaults[0])
        thread.messages = [ChatMessage(role: "user", content: "问题", round: 1), ChatMessage(role: "assistant", content: "", round: 1, pending: true)]
        let conversation = Conversation(threads: [thread], round: 1)
        let state = SavedState(configurations: [thread.configuration], conversations: [conversation], selectedConversation: conversation.id, relayURL: RelayClient.defaultURL)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: file)
        let store = LoomStore(fileURL: file)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.current.threads[0].messages.last?.error, true)
        XCTAssertEqual(store.current.threads[0].messages.last?.pending, false)
    }

    func testFailedRoundsDoNotProduceAdjacentUserRoles() {
        var thread = ModelThread(configuration: ModelConfiguration.defaults[0])
        thread.messages = [ChatMessage(role: "user", content: "第一问", round: 1),
                           ChatMessage(role: "assistant", content: "失败", round: 1, error: true),
                           ChatMessage(role: "user", content: "第二问", round: 2)]
        XCTAssertEqual(thread.requestMessages, [APIMessage(role: "user", content: "第一问\n\n第二问")])
    }

    func testRelayPayloadAndAnswer() async throws {
        let client = RelayClient(baseURL: "https://relay.example/loom", session: makeSession())
        let config = ModelConfiguration(name: "Test", endpoint: "https://provider.example/v1", model: "success")
        let answer = try await client.chat(configuration: config, key: "test-secret", messages: [APIMessage(role: "user", content: "你好")])
        XCTAssertEqual(answer, "模拟回答")
        let models = try await client.models(configuration: config, key: "test-secret")
        XCTAssertEqual(models.map(\.id), ["success", "failure"])
    }

    func testDirectOpenAIAndAnthropicRequests() async throws {
        let client = ProviderClient(session: makeSession())
        var config = ModelConfiguration(name: "Test", endpoint: "https://provider.example/v1", model: "success")
        let first = try await client.chat(configuration: config, key: "test-secret", messages: [APIMessage(role: "user", content: "问题")])
        XCTAssertEqual(first, "模拟回答")
        config.protocolKind = .anthropic
        let second = try await client.chat(configuration: config, key: "test-secret", messages: [APIMessage(role: "user", content: "问题")])
        XCTAssertEqual(second, "Anthropic 回答")
        let models = try await client.models(configuration: config, key: "test-secret")
        XCTAssertEqual(models.map(\.id), ["failure", "success"])
        config.model = "failure"
        do { _ = try await client.chat(configuration: config, key: "test-secret", messages: [])
            XCTFail("Expected direct error")
        } catch { XCTAssertFalse(error.localizedDescription.contains("test-secret")) }
    }

    func testProviderErrorRedactsKey() async throws {
        let client = RelayClient(baseURL: "https://relay.example/loom", session: makeSession())
        let config = ModelConfiguration(name: "Test", endpoint: "https://provider.example/v1", model: "failure")
        do {
            _ = try await client.chat(configuration: config, key: "test-secret", messages: [])
            XCTFail("Expected error")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("test-secret"))
            XCTAssertTrue(error.localizedDescription.contains("[REDACTED]"))
        }
    }

    func testParallelFailureIsolationAndRetry() async throws {
        let file = temporaryFile()
        let store = LoomStore(fileURL: file, session: makeSession())
        store.useRelay = true
        let ids = store.configurations.map(\.id)
        defer {
            store.cancelAll()
            for id in ids { try? KeychainStore().write("", for: id) }
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
        for (index, var config) in store.configurations.enumerated() {
            config.model = index == 0 ? "success" : "failure"
            try store.saveConfiguration(config, key: "test-secret")
        }
        for viaRelay in [true, false] {
            store.useRelay = viaRelay
            store.newConversation()
            store.draft = "你好"
            store.send()
            XCTAssertEqual(store.busyModels.count, 2)
            for _ in 0..<100 where store.isWorking { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertFalse(store.isWorking)
            XCTAssertEqual(store.current.threads[0].messages.last?.content, "模拟回答")
            XCTAssertEqual(store.current.threads[1].messages.last?.error, true)
            store.retry(ids[1])
            for _ in 0..<100 where store.isWorking { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertEqual(store.current.threads[1].messages.count, 2)
            XCTAssertEqual(store.current.threads[0].messages.count, 2)
        }
        let json = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(json.contains("test-secret"))
    }

    func testCancelAndSwitchCannotWriteIntoNewConversation() async throws {
        let file = temporaryFile()
        let store = LoomStore(fileURL: file, session: makeSession())
        store.useRelay = true
        let ids = store.configurations.map(\.id)
        defer {
            store.cancelAll()
            for id in ids { try? KeychainStore().write("", for: id) }
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }
        for var config in store.configurations { config.model = "success"; try store.saveConfiguration(config, key: "test-secret") }
        store.draft = "问题"
        store.send()
        let oldID = store.current.id
        store.newConversation()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(store.isWorking)
        XCTAssertTrue(store.current.threads.allSatisfy { $0.messages.isEmpty })
        let old = try XCTUnwrap(store.conversations.first(where: { $0.id == oldID }))
        XCTAssertTrue(old.threads.allSatisfy { $0.messages.last?.error == true && $0.messages.last?.pending == false })
    }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var data = request.httpBody
            if data == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                var body = Data()
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(buffer, count: count)
                }
                data = body
            }
            let payload = try data.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let isRelay = request.url?.path.contains("/api/") == true
            if !isRelay {
                if request.value(forHTTPHeaderField: "x-api-key") != nil {
                    guard request.value(forHTTPHeaderField: "x-api-key") == "test-secret", request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01" else { throw URLError(.userAuthenticationRequired) }
                } else {
                    guard request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret" else { throw URLError(.userAuthenticationRequired) }
                }
            }
            let failure = payload?["model"] as? String == "failure"
            let response = HTTPURLResponse(url: request.url!, statusCode: failure ? 401 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            let body: String
            if request.url?.lastPathComponent == "models" {
                body = isRelay ? #"{"models":[{"id":"success"},{"id":"failure"}]}"# : #"{"data":[{"id":"success"},{"id":"failure"}]}"#
            } else if failure { body = isRelay ? #"{"error":"Invalid test-secret"}"# : #"{"error":{"message":"Invalid test-secret"}}"# }
            else if request.url?.lastPathComponent == "messages" { body = #"{"content":[{"type":"text","text":"Anthropic 回答"}]}"# }
            else { body = #"{"choices":[{"message":{"content":"模拟回答"}}]}"# }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
