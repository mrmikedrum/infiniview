import AppKit
import InfiniviewCore

/// Turns text, highlighting tokens and Styled Source spans into attributes for one theme.
public struct TextStyler {
    public let theme: Theme
    public let font: NSFont
    private let bold: NSFont
    private let italic: NSFont
    private let boldItalic: NSFont

    public init(theme: Theme, fontSize: CGFloat) {
        self.theme = theme
        font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        bold = .monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let fm = NSFontManager.shared
        italic = fm.convert(font, toHaveTrait: .italicFontMask)
        boldItalic = fm.convert(bold, toHaveTrait: .italicFontMask)
    }

    public var baseAttributes: [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: theme.foreground] }

    public func plain(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: text, attributes: baseAttributes)
    }

    /// Colours `storage` from the tokens, for UTF-16 offsets below `limit`. Adjacent tokens
    /// that look the same are applied as one run.
    public func apply(_ tokens: Highlighter.Tokens, to storage: NSMutableAttributedString, from start: Int = 0, upTo limit: Int) {
        let t = tokens.pairs
        let end = min(limit, tokens.stoppedAt ?? limit, storage.length)
        storage.beginEditing()
        defer { storage.endEditing() }
        var i = 0
        while i + 1 < t.count {
            let from = Int(t[i]), meta = t[i + 1]
            var j = i + 2
            while j + 1 < t.count && t[j + 1] == meta { j += 2 }
            let to = min(j < t.count ? Int(t[j]) : end, end)
            i = j
            guard to > start, from < to else { if from >= end { break }; continue }
            let range = NSRange(location: max(from, start), length: to - max(from, start))
            storage.addAttribute(.foregroundColor, value: theme.color(at: TokenMetadata.foreground(meta)) ?? theme.foreground, range: range)
            let b = TokenMetadata.isBold(meta), it = TokenMetadata.isItalic(meta)
            if b || it { storage.addAttribute(.font, value: b && it ? boldItalic : b ? bold : italic, range: range) }
            if TokenMetadata.isUnderline(meta) { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            if TokenMetadata.isStrikethrough(meta) { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
        }
    }

    /// Styled Source on top of the highlighting: larger bold headings, bold and italic, tinted
    /// inline code, link text underlined, and every marker dimmed but kept.
    public func applyStyledSource(_ spans: [StyledSource.Span], to storage: NSMutableAttributedString) {
        storage.beginEditing()
        defer { storage.endEditing() }
        let tint = theme.foreground.withAlphaComponent(theme.isDark ? 0.12 : 0.07)
        for span in spans where NSMaxRange(span.range) <= storage.length {
            let r = span.range
            switch span.kind {
            case .heading(let level):
                let scale: CGFloat = [1.6, 1.4, 1.25, 1.1, 1.05, 1.0][min(level, 6) - 1]
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: font.pointSize * scale, weight: .bold), range: r)
            case .bold:
                storage.enumerateAttribute(.font, in: r) { value, sub, _ in
                    let isItalic = (value as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
                    storage.addAttribute(.font, value: isItalic ? boldItalic : bold, range: sub)
                }
            case .italic:
                storage.enumerateAttribute(.font, in: r) { value, sub, _ in
                    let isBold = (value as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
                    storage.addAttribute(.font, value: isBold ? boldItalic : italic, range: sub)
                }
            case .code:
                storage.addAttribute(.backgroundColor, value: tint, range: r)
            case .link:
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            case .marker, .url:
                storage.enumerateAttribute(.foregroundColor, in: r) { value, sub, _ in
                    let c = (value as? NSColor) ?? theme.foreground
                    storage.addAttribute(.foregroundColor, value: c.withAlphaComponent(c.alphaComponent * 0.45), range: sub)
                }
            }
        }
    }
}
