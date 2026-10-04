import Foundation

extension ChatMessage {
    /// Recover structured references from prompts saved before reference snapshots existed.
    mutating func recoverSentReferences() {
        guard role == "user", references == nil, let display else { return }
        let prefix = display + "\n\n请结合以下高亮参考内容继续思考：\n"
        guard content.hasPrefix(prefix) else { return }
        let source = String(content.dropFirst(prefix.count)) as NSString
        guard let expression = try? NSRegularExpression(pattern: #"(?m)^【(.+) / (.+) · 第 ([0-9]+) 轮】\n"#) else { return }
        let headers = expression.matches(in: source as String, range: NSRange(location: 0, length: source.length))
        let recovered = headers.enumerated().compactMap { index, header -> Quote? in
            guard let round = Int(source.substring(with: header.range(at: 3))) else { return nil }
            let start = NSMaxRange(header.range)
            let end = index + 1 < headers.count ? headers[index + 1].range.location : source.length
            let text = source.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Quote(id: UUID(), text: text, modelName: source.substring(with: header.range(at: 1)),
                         model: source.substring(with: header.range(at: 2)), round: round)
        }
        if !recovered.isEmpty { references = recovered }
    }
}
