import Foundation

/**
 * The "simple Markdown" A2UI `Text` supports (a2ui/markdown.ts), parsed to
 * plain data the lowering turns into rich text: ATX headings, bullet and
 * numbered list items, paragraphs, and inline `**bold**`, `*italic*` /
 * `_italic_`, `~~strike~~`, `` `code` `` and `[links](https://…)`. Anything
 * else stays literal text.
 */
public struct MarkdownInline: Equatable {
    public var text: String
    public var bold = false
    public var italic = false
    public var strike = false
    public var code = false
    public var href: String?

    public init(text: String, bold: Bool = false, italic: Bool = false, strike: Bool = false, code: Bool = false, href: String? = nil) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.strike = strike
        self.code = code
        self.href = href
    }

    /** `{...inherited, text}`. */
    func with(text: String) -> MarkdownInline {
        var c = self
        c.text = text
        return c
    }
}

public enum MarkdownBlockType: String {
    case heading, paragraph, bullet, ordered
}

public struct MarkdownBlock {
    public var type: MarkdownBlockType
    /** Heading level (1–6). */
    public var level = 0
    /** Ordered-item number. */
    public var number = 0
    public var inlines: [MarkdownInline]
}

private let HEADING = JSRegex("^\\s{0,3}(#{1,6})\\s+(.*?)\\s*#*\\s*$")
private let BULLET = JSRegex("^\\s*[-*+]\\s+(.*)$")
private let ORDERED = JSRegex("^\\s*(\\d{1,9})[.)]\\s+(.*)$")
private let CRLF = JSRegex("\\r\\n?")

public func parseMarkdown(_ source: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    func flush() {
        if !paragraph.isEmpty { blocks.append(MarkdownBlock(type: .paragraph, inlines: parseInlines(paragraph.joined(separator: "\n")))) }
        paragraph = []
    }
    for line in CRLF.replace(source, with: "\n").components(separatedBy: "\n") {
        if jsTrim(line).isEmpty {
            flush()
        } else if let h = HEADING.exec(line) {
            flush()
            blocks.append(MarkdownBlock(type: .heading, level: (h[1] ?? "#").count, inlines: parseInlines(h[2] ?? "")))
        } else if let b = BULLET.exec(line) {
            flush()
            blocks.append(MarkdownBlock(type: .bullet, inlines: parseInlines(b[1] ?? "")))
        } else if let o = ORDERED.exec(line) {
            flush()
            blocks.append(MarkdownBlock(type: .ordered, number: Int(o[1] ?? "0") ?? 0, inlines: parseInlines(o[2] ?? "")))
        } else {
            paragraph.append(line)
        }
    }
    flush()
    return blocks
}

// swiftlint:disable:next force_try
private let INLINE = try! NSRegularExpression(
    pattern: "(\\*\\*|__)(.+?)\\1|(\\*|_)(?!\\s)(.+?)\\3|~~(.+?)~~|`([^`]+)`|\\[([^\\]]+)\\]\\(([^)\\s]+)\\)"
)

public func parseInlines(_ text: String, _ inherited: MarkdownInline = MarkdownInline(text: "")) -> [MarkdownInline] {
    var out: [MarkdownInline] = []
    var rest = text
    while !rest.isEmpty {
        let ns = rest as NSString
        guard let m = INLINE.firstMatch(in: rest, options: [], range: NSRange(location: 0, length: ns.length)) else {
            out.append(inherited.with(text: rest))
            break
        }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        if m.range.location > 0 { out.append(inherited.with(text: ns.substring(to: m.range.location))) }
        if let s = group(2) {
            var i = inherited
            i.bold = true
            out += parseInlines(s, i)
        } else if let s = group(4) {
            var i = inherited
            i.italic = true
            out += parseInlines(s, i)
        } else if let s = group(5) {
            var i = inherited
            i.strike = true
            out += parseInlines(s, i)
        } else if let s = group(6) {
            var i = inherited.with(text: s)
            i.code = true
            out.append(i)
        } else if let s = group(7) {
            var i = inherited
            i.href = group(8)
            out += parseInlines(s, i)
        }
        rest = ns.substring(from: m.range.location + m.range.length)
    }
    return out.filter { !$0.text.isEmpty }
}

/** Whether [blocks] is one paragraph of unformatted text. */
public func isPlainText(_ blocks: [MarkdownBlock]) -> Bool {
    blocks.count == 1 && blocks[0].type == .paragraph && blocks[0].inlines.allSatisfy { !$0.bold && !$0.italic && !$0.strike && !$0.code && $0.href == nil }
}

/** The text without Markdown markers (for accessibility labels and fallbacks). */
public func plainText(_ blocks: [MarkdownBlock]) -> String {
    blocks.map { $0.inlines.map { $0.text }.joined() }.joined(separator: "\n")
}
