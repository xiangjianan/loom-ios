import UIKit
import WebKit

struct SVGDocument {
    let source: String
    let aspectRatio: CGFloat

    init?(_ source: String) {
        let metadata = SVGMetadata()
        let parser = XMLParser(data: Data(source.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = metadata
        guard parser.parse(), metadata.isSVG else { return nil }
        self.source = source
        aspectRatio = metadata.aspectRatio
    }
    func bounds(width: CGFloat) -> CGRect {
        let width = max(1, min(760, width))
        return CGRect(x: 0, y: 0, width: width, height: min(700, max(80, width / aspectRatio)))
    }
    var html: String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; base-uri 'none'; form-action 'none'">
        <style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}svg{display:block;width:100%;height:100%;max-width:100%}</style></head><body>\(source)</body></html>
        """
    }

    static func extract(from markdown: String) -> (markdown: String, documents: [(String, SVGDocument)]) {
        var value = markdown
        var documents: [(String, SVGDocument)] = []
        func replace(_ range: NSRange, document: SVGDocument) {
            let token = "LoomSVG" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            value = (value as NSString).replacingCharacters(in: range, with: "\n\n\(token)\n\n")
            documents.append((token, document))
        }
        // Fenced SVG, XML, and HTML answers should become images rather than source code.
        let fences = try! NSRegularExpression(pattern: #"(?is)```(?:svg|xml|html)?[^\S\r\n]*\r?\n([\s\S]*?)```"#)
        for match in fences.matches(in: value, range: NSRange(location: 0, length: (value as NSString).length)).reversed() {
            let code = (value as NSString).substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let document = SVGDocument(code) { replace(match.range, document: document) }
        }
        // Match balanced SVG roots, including nested SVG viewports.
        let tags = try! NSRegularExpression(pattern: #"(?is)<(/?)svg\b(?:"[^"]*"|'[^']*'|[^'">])*>"#)
        let text = value as NSString
        var depth = 0
        var start = 0
        var roots: [NSRange] = []
        for match in tags.matches(in: value, range: NSRange(location: 0, length: text.length)) {
            let closing = text.substring(with: match.range(at: 1)) == "/"
            let tag = text.substring(with: match.range)
            if !closing {
                if depth == 0 { start = match.range.location }
                if !tag.hasSuffix("/>") { depth += 1 }
                else if depth == 0 { roots.append(match.range) }
            } else if depth > 0 {
                depth -= 1
                if depth == 0 { roots.append(NSRange(location: start, length: NSMaxRange(match.range) - start)) }
            }
        }
        for range in roots.reversed() {
            if let document = SVGDocument(text.substring(with: range)) { replace(range, document: document) }
        }
        return (value, documents)
    }
}

private final class SVGMetadata: NSObject, XMLParserDelegate {
    var isSVG = false
    var aspectRatio: CGFloat = 1.5
    private var rootSeen = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        guard !rootSeen else { return }
        rootSeen = true
        isSVG = elementName.lowercased() == "svg"
        if let box = attributes["viewBox"]?.split(whereSeparator: { $0.isWhitespace || $0 == "," }).compactMap({ Double($0) }), box.count == 4, box[2] > 0, box[3] > 0 {
            aspectRatio = CGFloat(box[2] / box[3])
        } else if let width = number(attributes["width"]), let height = number(attributes["height"]), width > 0, height > 0 { aspectRatio = width / height }
        if !aspectRatio.isFinite || aspectRatio <= 0 { aspectRatio = 1.5 }
    }
    private func number(_ value: String?) -> CGFloat? {
        guard let value, !value.contains("%"), let number = Double(value.replacingOccurrences(of: "px", with: "")) else { return nil }
        return CGFloat(number)
    }
}

@MainActor final class SVGTextAttachment: NSTextAttachment {
    let document: SVGDocument
    init(document: SVGDocument) {
        self.document = document
        super.init(data: nil, ofType: nil)
        // The transparent glyph reserves native text layout space; ReadingTextView overlays
        // a vector WebKit view at that glyph. This also works with TextKit compatibility mode.
        image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }
        bounds = document.bounds(width: 300)
        allowsTextAttachmentView = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor final class SVGImageView: WKWebView, WKNavigationDelegate {
    let source: String
    init(document: SVGDocument) {
        source = document.source
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        super.init(frame: .zero, configuration: configuration)
        isOpaque = false
        backgroundColor = .clear
        scrollView.isScrollEnabled = false
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = "SVG 图像"
        accessibilityIdentifier = "svg-image-loading"
        navigationDelegate = self
        loadHTMLString(document.html, baseURL: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        accessibilityIdentifier = "svg-image"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension NSAttributedString.Key {
    static let loomCode = NSAttributedString.Key("LoomCode")
}
