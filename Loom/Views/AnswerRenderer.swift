import Foundation
import UIKit

/// Foundation parses Markdown semantics; TextKit displays native selectable rich text.
@MainActor enum AnswerRenderer {
    private static let cache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>()
        cache.countLimit = 64
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func render(_ markdown: String) -> NSMutableAttributedString {
        // SVG attachments own mutable layout bounds; keep those outside the shared cache.
        let cacheable = !markdown.localizedCaseInsensitiveContains("<svg")
        let key = "\(UIFont.preferredFont(forTextStyle: .body).pointSize)|\(markdown)" as NSString
        if cacheable, let saved = cache.object(forKey: key) {
            return NSMutableAttributedString(attributedString: saved)
        }
        let rendered = parse(markdown)
        if cacheable {
            cache.setObject(NSAttributedString(attributedString: rendered), forKey: key,
                            cost: rendered.length * 16 + markdown.utf8.count)
        }
        return rendered
    }

    private static func parse(_ markdown: String) -> NSMutableAttributedString {
        let extracted = SVGDocument.extract(from: markdown)
        guard let parsed = try? AttributedString(markdown: extracted.markdown, options: .init(
            interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)) else {
            return NSMutableAttributedString(string: markdown, attributes: baseAttributes())
        }
        let output = NSMutableAttributedString(string: "")
        var lastBlock: Int?
        var seenItems: Set<Int> = []
        var tableID: Int?
        var table: [[NSMutableAttributedString]] = []
        var lastRow: Int?
        var lastCell: Int?

        func separator() {
            if output.length > 0, !output.string.hasSuffix("\n") {
                output.append(NSAttributedString(string: "\n", attributes: baseAttributes()))
            }
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            separator()
            let count = table.map(\.count).max() ?? 1
            let width = min(140, 300 / CGFloat(max(1, count)))
            for (rowIndex, row) in table.enumerated() {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 4
                style.paragraphSpacing = rowIndex == table.count - 1 ? 14 : 8
                style.defaultTabInterval = width
                style.tabStops = (1..<max(2, count)).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * width) }
                let line = NSMutableAttributedString(string: "")
                for (index, cell) in row.enumerated() {
                    if index > 0 { line.append(NSAttributedString(string: "\t")) }
                    line.append(cell)
                }
                let range = NSRange(location: 0, length: line.length)
                line.addAttributes([.paragraphStyle: style,
                                    .font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize - 1,
                                                                    weight: rowIndex == 0 ? .semibold : .regular)], range: range)
                if rowIndex == 0 { line.addAttribute(.backgroundColor, value: UIColor.secondarySystemFill, range: range) }
                output.append(line)
                output.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
            }
            table = []; tableID = nil; lastRow = nil; lastCell = nil; lastBlock = nil
        }

        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let value = String(parsed.characters[run.range])
            let attributes = attributes(for: components, inline: run.inlinePresentationIntent, link: run.link)
            if let component = components.first(where: { if case .table = $0.kind { true } else { false } }) {
                if tableID != component.identity { flushTable(); tableID = component.identity }
                let row = components.first(where: {
                    switch $0.kind { case .tableRow, .tableHeaderRow: true; default: false }
                })?.identity
                let cell = components.first(where: { if case .tableCell = $0.kind { true } else { false } })?.identity
                if lastRow != row { table.append([]); lastRow = row; lastCell = nil }
                if lastCell != cell { table[table.count - 1].append(NSMutableAttributedString(string: "")); lastCell = cell }
                table[table.count - 1][table[table.count - 1].count - 1].append(NSAttributedString(string: value, attributes: attributes))
                continue
            }
            flushTable()
            let identity = components.first?.identity
            if identity != lastBlock {
                separator()
                if let itemIndex = components.firstIndex(where: { if case .listItem = $0.kind { true } else { false } }),
                   case .listItem(let ordinal) = components[itemIndex].kind,
                   seenItems.insert(components[itemIndex].identity).inserted {
                    let ordered = components.dropFirst(itemIndex + 1).first?.kind == .orderedList
                    output.append(NSAttributedString(string: ordered ? "\(ordinal).\t" : "•\t", attributes: attributes))
                }
                if components.contains(where: { $0.kind == .blockQuote }) {
                    output.append(NSAttributedString(string: "▎ ", attributes: attributes))
                }
                lastBlock = identity
            }
            output.append(NSAttributedString(string: value, attributes: attributes))
        }
        flushTable()
        // Code fences have a trailing newline from the parser; do not leave a blank last line.
        while output.string.hasSuffix("\n") { output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1)) }
        for (token, document) in extracted.documents {
            let range = (output.string as NSString).range(of: token)
            guard range.location != NSNotFound else { continue }
            output.replaceCharacters(in: range, with: NSAttributedString(attachment: SVGTextAttachment(document: document), attributes: baseAttributes()))
        }
        return output
    }

    private static func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 12
        return [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
    }

    private static func attributes(for components: [PresentationIntent.IntentType], inline: InlinePresentationIntent?, link: URL?) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes()
        var font = UIFont.preferredFont(forTextStyle: .body)
        let paragraph = attributes[.paragraphStyle] as! NSMutableParagraphStyle
        let depth = components.filter { if case .listItem = $0.kind { true } else { false } }.count
        if depth > 0 {
            paragraph.firstLineHeadIndent = CGFloat(depth - 1) * 20
            paragraph.headIndent = CGFloat(depth) * 20
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
            paragraph.paragraphSpacing = 6
        }
        for component in components {
            switch component.kind {
            case .header(let level):
                let styles: [UIFont.TextStyle] = [.title1, .title2, .title3, .headline]
                font = UIFont.preferredFont(forTextStyle: styles[min(max(level - 1, 0), styles.count - 1)])
                if let descriptor = font.fontDescriptor.withSymbolicTraits(.traitBold) { font = UIFont(descriptor: descriptor, size: font.pointSize) }
                paragraph.paragraphSpacingBefore = 12
                paragraph.paragraphSpacing = 10
            case .blockQuote:
                paragraph.firstLineHeadIndent += 12; paragraph.headIndent += 12
                attributes[.foregroundColor] = UIColor.secondaryLabel
            case .codeBlock:
                attributes[.loomCode] = true
                font = UIFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
                paragraph.firstLineHeadIndent = 10; paragraph.headIndent = 10; paragraph.tailIndent = -10
                paragraph.paragraphSpacingBefore = 8; paragraph.paragraphSpacing = 12
                attributes[.backgroundColor] = UIColor.secondarySystemFill
            case .thematicBreak:
                attributes[.foregroundColor] = UIColor.separator
                paragraph.paragraphSpacingBefore = 8; paragraph.paragraphSpacing = 8
            default: break
            }
        }
        var traits = font.fontDescriptor.symbolicTraits
        if inline?.contains(.stronglyEmphasized) == true { traits.insert(.traitBold) }
        if inline?.contains(.emphasized) == true { traits.insert(.traitItalic) }
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { font = UIFont(descriptor: descriptor, size: font.pointSize) }
        if inline?.contains(.code) == true {
            attributes[.loomCode] = true
            font = UIFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            attributes[.backgroundColor] = UIColor.secondarySystemFill
        }
        if inline?.contains(.strikethrough) == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link, ["https", "http", "mailto"].contains(link.scheme?.lowercased() ?? "") { attributes[.link] = link }
        attributes[.font] = font
        return attributes
    }
}

/// Persisted selections from the earlier inline-only renderer are reanchored by text.
@MainActor enum HighlightResolver {
    static func resolve(_ highlight: Highlight, in text: String) -> Highlight? {
        let string = text as NSString
        if highlight.location >= 0, highlight.length > 0, NSMaxRange(highlight.range) <= string.length,
           string.substring(with: highlight.range) == highlight.text { return highlight }
        guard !highlight.text.isEmpty else { return nil }
        var remaining = NSRange(location: 0, length: string.length)
        var closest: NSRange?
        while remaining.length > 0 {
            let found = string.range(of: highlight.text, range: remaining)
            guard found.location != NSNotFound else { break }
            if closest == nil || abs(found.location - highlight.location) < abs(closest!.location - highlight.location) { closest = found }
            let next = NSMaxRange(found)
            remaining = NSRange(location: next, length: string.length - next)
        }
        if closest == nil {
            let normalized = AnswerRenderer.render(highlight.text).string
            if !normalized.isEmpty, normalized != highlight.text {
                var adapted = highlight
                adapted.text = normalized
                return resolve(adapted, in: text)
            }
        }
        guard let range = closest else { return nil }
        var resolved = highlight
        resolved.location = range.location; resolved.length = range.length
        return resolved
    }
}

// Local fixture used only with --demo --demo-markdown, never saved to real history.
enum MarkdownPreview {
    static let content = #"""
    # 从一个想法开始

    让 **重要观点** 更清晰，也让 *不同的视角* 得以交织。

    ## 三个小步骤

    - 找到真实的问题
    - 做出最小的体验
      - 先验证核心动作
    - 根据反馈继续调整

    > 好的产品，让一个重要的动作变得自然。

    ### 一个代码示例

    ```swift
    let idea = "Loom"
    print("Hello, \(idea)")
    ```

    | 模型 | 擅长 |
    | --- | --- |
    | A | 结构化分析 |
    | B | 发现新视角 |

    阅读 [项目文档](https://github.com/xiangjianan/loom-ios)，选中有用的文字继续追问。
    """#
}
