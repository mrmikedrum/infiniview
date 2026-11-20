import Foundation

/// Styled Source: which parts of a Markdown file to style, while every character stays visible.
/// A line-based approximation of common Markdown, not a full CommonMark parser. Fenced code
/// blocks are skipped: the Markdown grammar highlights them in their own language.
public enum StyledSource {
    public enum Kind: Sendable, Equatable, CustomStringConvertible {
        case heading(Int), marker, bold, italic, code, link, url
        public var description: String {
            switch self {
            case .heading(let level): "heading(\(level))"
            case .marker: "marker"
            case .bold: "bold"
            case .italic: "italic"
            case .code: "code"
            case .link: "link"
            case .url: "url"
            }
        }
    }

    public struct Span: Sendable, Equatable {
        public let kind: Kind
        /// UTF-16 range, ready for NSAttributedString.
        public let range: NSRange
    }

    public static func spans(in text: String) -> [Span] {
        let ns = text as NSString
        var out = [(Span, Int)]() // with emission order, for a stable sort
        func add(_ kind: Kind, _ range: NSRange) {
            if range.length > 0 { out.append((Span(kind: kind, range: range), out.count)) }
        }
        var fence: (char: unichar, length: Int)?
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            if let m = fenceLine.firstMatch(in: text, range: line) {
                let run = m.range(at: 1)
                let char = ns.character(at: run.location)
                if let open = fence {
                    // A closing fence: same character, at least as long, nothing after it.
                    if char == open.char && run.length >= open.length && isBlank(ns, m.range(at: 2)) {
                        fence = nil
                        add(.marker, NSRange(location: run.location, length: NSMaxRange(line) - run.location))
                    }
                } else {
                    fence = (char, run.length)
                    add(.marker, NSRange(location: run.location, length: NSMaxRange(line) - run.location))
                }
                return
            }
            if fence != nil { return }
            if let m = heading.firstMatch(in: text, range: line) {
                let level = m.range(at: 1).length
                let end = trimmedEnd(ns, line)
                add(.heading(level), NSRange(location: m.range(at: 1).location, length: end - m.range(at: 1).location))
                add(.marker, NSRange(location: m.range(at: 1).location, length: NSMaxRange(m.range(at: 2)) - m.range(at: 1).location))
                if m.range(at: 4).location != NSNotFound { add(.marker, m.range(at: 4)) }
                inline(ns, m.range(at: 3), add)
                return
            }
            var rest = line
            if let m = quote.firstMatch(in: text, range: rest) {
                add(.marker, NSRange(location: m.range(at: 1).location, length: NSMaxRange(m.range) - m.range(at: 1).location))
                rest = NSRange(location: NSMaxRange(m.range), length: NSMaxRange(rest) - NSMaxRange(m.range))
            }
            if let m = listItem.firstMatch(in: text, range: rest) {
                add(.marker, m.range(at: 1))
                rest = NSRange(location: NSMaxRange(m.range), length: NSMaxRange(rest) - NSMaxRange(m.range))
            }
            inline(ns, rest, add)
        }
        return out.sorted { ($0.0.range.location, $0.1) < ($1.0.range.location, $1.1) }.map(\.0)
    }

    // MARK: - Inline

    private static func inline(_ ns: NSString, _ range: NSRange, _ add: (Kind, NSRange) -> Void) {
        guard range.length > 0 else { return }
        let text = ns as String
        var protected = [NSRange]()
        func free(_ r: NSRange) -> Bool { !protected.contains { NSIntersectionRange($0, r).length > 0 } }

        for m in codeSpan.matches(in: text, range: range) {
            let tick = m.range(at: 1)
            let body = m.range(at: 2)
            add(.marker, tick)
            add(.code, body)
            add(.marker, NSRange(location: NSMaxRange(body), length: tick.length))
            protected.append(m.range)
        }
        for m in link.matches(in: text, range: range) where free(m.range) {
            let label = m.range(at: 1), url = m.range(at: 2)
            add(.marker, NSRange(location: m.range.location, length: label.location - m.range.location))
            add(.link, label)
            add(.marker, NSRange(location: NSMaxRange(label), length: url.location - NSMaxRange(label)))
            add(.url, url)
            add(.marker, NSRange(location: NSMaxRange(url), length: NSMaxRange(m.range) - NSMaxRange(url)))
            protected.append(NSRange(location: NSMaxRange(label), length: NSMaxRange(m.range) - NSMaxRange(label)))
        }
        for (re, kind) in [(boldStars, Kind.bold), (boldUnderscores, .bold), (italicStar, .italic), (italicUnderscore, .italic)] {
            for m in re.matches(in: text, range: range) where free(m.range) {
                let body = m.range(at: 2), marker = m.range(at: 1).length
                add(.marker, NSRange(location: m.range.location, length: marker))
                add(kind, body)
                add(.marker, NSRange(location: NSMaxRange(body), length: marker))
                // Markers can't open or close another emphasis.
                protected.append(NSRange(location: m.range.location, length: marker))
                protected.append(NSRange(location: NSMaxRange(body), length: marker))
            }
        }
    }

    // MARK: - Helpers

    private static func isBlank(_ ns: NSString, _ r: NSRange) -> Bool {
        r.location == NSNotFound || ns.substring(with: r).allSatisfy(\.isWhitespace)
    }

    private static func trimmedEnd(_ ns: NSString, _ line: NSRange) -> Int {
        var end = NSMaxRange(line)
        while end > line.location, let s = Unicode.Scalar(ns.character(at: end - 1)), CharacterSet.whitespaces.contains(s) { end -= 1 }
        return end
    }

    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    nonisolated(unsafe) private static let fenceLine = re(#"^ {0,3}(`{3,}|~{3,})(.*)$"#)
    nonisolated(unsafe) private static let heading = re(#"^ {0,3}(#{1,6})( +|$)(.*?)( +#+)? *$"#)
    nonisolated(unsafe) private static let quote = re(#"^ {0,3}(>)(?: ?>)* ?"#)
    nonisolated(unsafe) private static let listItem = re(#"^\s*((?:[-*+]|\d{1,9}[.)]) +)"#)
    nonisolated(unsafe) private static let codeSpan = re(#"(`+)(.+?)(?<!`)\1(?!`)"#)
    nonisolated(unsafe) private static let link = re(#"!?\[([^\]\n]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)
    nonisolated(unsafe) private static let boldStars = re(#"(\*\*)(?=\S)(.+?)(?<=\S)\*\*"#)
    nonisolated(unsafe) private static let boldUnderscores = re(#"(?<![\p{L}\p{N}_])(__)(?=\S)(.+?)(?<=\S)__(?![\p{L}\p{N}_])"#)
    nonisolated(unsafe) private static let italicStar = re(#"(?<![*\p{L}\p{N}])(\*)(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)"#)
    nonisolated(unsafe) private static let italicUnderscore = re(#"(?<![\p{L}\p{N}_])(_)(?=[^\s_])(.+?)(?<=[^\s_])_(?![\p{L}\p{N}_])"#)
}
