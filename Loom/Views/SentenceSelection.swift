import Foundation

/// All offsets match TextKit's UTF-16 ranges, including emoji and CJK text.
enum SentenceSelection {
    static func range(in text: String, at offset: Int) -> NSRange? {
        let string = text as NSString
        guard offset >= 0, offset < string.length else { return nil }
        let paragraph = string.paragraphRange(for: NSRange(location: offset, length: 0))
        let value = string.substring(with: paragraph)
        let characters = Array(value)
        var start = paragraph.location
        var cursor = start
        var i = 0
        while i < characters.count {
            let character = characters[i]
            cursor += String(character).utf16.count
            var terminal = "。！？!?…".contains(character)
            if character == "." {
                let previous = i > 0 ? characters[i - 1] : " "
                let next = i + 1 < characters.count ? characters[i + 1] : " "
                // Decimal points and dots within URLs/identifiers are not sentence endings.
                terminal = !(previous.isNumber && next.isNumber) && (next.isWhitespace || next == "." || i + 1 == characters.count || "\"'”’」』）)]".contains(next))
            }
            if terminal {
                while i + 1 < characters.count, "。！？!?…．.\"'”’」』）)]".contains(characters[i + 1]) {
                    i += 1; cursor += String(characters[i]).utf16.count
                }
                let candidate = trimmed(NSRange(location: start, length: cursor - start), in: string)
                if let candidate, NSLocationInRange(offset, candidate) { return candidate }
                start = cursor
            }
            i += 1
        }
        return trimmed(NSRange(location: start, length: NSMaxRange(paragraph) - start), in: string)
            .flatMap { NSLocationInRange(offset, $0) ? $0 : nil }
    }

    private static func trimmed(_ original: NSRange, in text: NSString) -> NSRange? {
        var range = original
        let whitespace = CharacterSet.whitespacesAndNewlines
        while range.length > 0, let scalar = UnicodeScalar(text.character(at: range.location)), whitespace.contains(scalar) {
            range.location += 1; range.length -= 1
        }
        while range.length > 0, let scalar = UnicodeScalar(text.character(at: NSMaxRange(range) - 1)), whitespace.contains(scalar) { range.length -= 1 }
        return range.length > 0 ? range : nil
    }
}
