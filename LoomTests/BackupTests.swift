import XCTest
@testable import Loom

@MainActor final class BackupTests: XCTestCase {
    private func file() -> URL { .temporaryDirectory.appending(path: "backup-tests-\(UUID())/state.json") }

    func testBackupRoundTripPreservesHighlightsReferencesAndPreferences() throws {
        let source = LoomStore(fileURL: file(), demo: true)
        let thread = source.current.threads[0]
        let message = thread.messages[1]
        source.highlight(threadID: thread.id, messageID: message.id, range: NSRange(location: 0, length: 4), text: "先找到")
        source.draft = "下一轮问题"
        source.singleTapHighlight = false
        let data = try source.backup(includeKeys: false)
        let archive = try JSONDecoder().decode(LoomBackup.self, from: data)
        XCTAssertNil(archive.keys)
        let path = file()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let target = LoomStore(fileURL: path)
        try target.restore(archive)
        let reloaded = LoomStore(fileURL: path)
        XCTAssertEqual(reloaded.conversations, source.conversations)
        XCTAssertEqual(reloaded.configurations, source.configurations)
        XCTAssertFalse(reloaded.singleTapHighlight)
        XCTAssertEqual(reloaded.current.quotes.count, 1)
    }

    func testInvalidBackupDoesNotReplaceDataAndImportKeepsPreviousFile() throws {
        let path = file()
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let target = LoomStore(fileURL: path)
        target.draft = "原始内容"
        let previous = try Data(contentsOf: path)
        let source = LoomStore(fileURL: file(), demo: true)
        var archive = try JSONDecoder().decode(LoomBackup.self, from: source.backup(includeKeys: false))
        archive.version = 99
        XCTAssertThrowsError(try target.restore(archive))
        XCTAssertEqual(try Data(contentsOf: path), previous)
        XCTAssertEqual(target.draft, "原始内容")
        archive.version = 1
        try target.restore(archive)
        let copies = try FileManager.default.contentsOfDirectory(at: path.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("before-import-") }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(try Data(contentsOf: copies[0]), previous)
    }

    func testKeysAreOptionalAndUnknownKeyIDsRejected() throws {
        let source = LoomStore(fileURL: file(), demo: true)
        let id = source.configurations[0].id
        let chain = KeychainStore()
        defer { try? chain.write("", for: id) }
        try chain.write("backup-test-secret", for: id)
        var archive = try JSONDecoder().decode(LoomBackup.self, from: source.backup(includeKeys: true))
        XCTAssertEqual(archive.keys?[id.uuidString], "backup-test-secret")
        try chain.write("", for: id)
        let target = LoomStore(fileURL: file(), demo: true)
        try target.restore(archive)
        XCTAssertEqual(chain.read(id), "backup-test-secret")
        archive.keys?[UUID().uuidString] = "invalid"
        XCTAssertThrowsError(try target.restore(archive))
    }

    func testDuplicateConversationAndOverflowingHighlightRejected() throws {
        let source = LoomStore(fileURL: file(), demo: true)
        var archive = try JSONDecoder().decode(LoomBackup.self, from: source.backup(includeKeys: false))
        archive.state.conversations.append(archive.state.conversations[0])
        XCTAssertThrowsError(try archive.validate())
        archive.state.conversations.removeLast()
        archive.state.conversations[0].threads[0].messages[1].highlights = [Highlight(location: Int.max, length: 10, text: "无效")]
        XCTAssertThrowsError(try archive.validate())
    }
}
