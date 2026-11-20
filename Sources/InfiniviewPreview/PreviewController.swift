import AppKit
import InfiniviewCore

/// Shows one file in a PreviewView: text with highlighting and Styled Source, RTF, or the
/// Fallback Card. Highlighting runs in two stages (limits in PreviewLimits): the first lines
/// before the view is handed to Quick Look, the rest in the background, applied in chunks.
@MainActor
public final class PreviewController {
    public let view = PreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    public static let fontSize: CGFloat = 12

    private let assets: URL
    private let languages: LanguageIndex
    private var content: PreviewContent?
    private var fileName = ""
    private var lineIndex = LineIndex("")
    /// Bumped on every render; background work for an older render stops.
    private var generation = 0

    public init(assets: URL) throws {
        self.assets = assets
        languages = try LanguageIndex(json: Data(contentsOf: assets.appendingPathComponent("languages.json")))
        view.onAppearanceChange = { [weak self] in self?.render() }
    }

    public func load(_ url: URL) throws {
        fileName = url.lastPathComponent
        content = try PreviewContent.load(url, languages: languages)
        if case .text(let doc) = content { lineIndex = LineIndex(doc.text) }
        render()
    }

    func render() {
        generation += 1
        switch content {
        case .text(let doc): renderText(doc)
        case .rtf(let rtf): renderRTF(rtf)
        case .card(let card): renderCard(card)
        case nil: break
        }
    }

    // MARK: - Text

    private func renderText(_ doc: PreviewContent.TextDocument) {
        let theme = Theme.current(dark: view.isDark, assets: assets, settings: SharedSettings())
        let styler = TextStyler(theme: theme, fontSize: Self.fontSize)
        let text = doc.text
        let storage = styler.plain(text)
        let length = storage.length
        let syncEnd = lineIndex.utf16Offset(afterLines: PreviewLimits.syncHighlightLines)
        let highlightEnd = min(length, PreviewLimits.maxHighlightedUTF16)

        var notes = [String]()
        if doc.totalBytes == 0 { notes.append("Empty file.") }
        if doc.isTruncated {
            notes.append("Showing the first \(Self.bytes(doc.shownBytes)) of \(Self.bytes(doc.totalBytes)).")
        }
        let scope = doc.language?.scopeName
        if scope != nil, highlightEnd < length {
            notes.append("Highlighting covers the first \(Self.bytes(PreviewLimits.maxHighlightedUTF16)).")
        }

        if let scope {
            let head = (text as NSString).substring(to: min(syncEnd, highlightEnd))
            let tokens = Self.onHighlighter(assets: assets, languages: languages) { h -> Highlighter.Tokens in
                h.setTheme(theme)
                return h.loadGrammar(scope) ? h.tokenize(head, scope: scope) : .empty
            }
            styler.apply(tokens, to: storage, upTo: min(syncEnd, highlightEnd))
            if doc.isMarkdown { styler.applyStyledSource(StyledSource.spans(in: head), to: storage) }
        }

        view.setWraps(true)
        view.textView.usesAdaptiveColorMappingForDarkAppearance = false
        view.textView.backgroundColor = theme.background
        view.textView.drawsBackground = true
        view.scrollView.backgroundColor = theme.background
        view.textView.insertionPointColor = theme.foreground
        view.textView.selectedTextAttributes = [.backgroundColor: theme.selection]
        view.textView.textStorage?.setAttributedString(storage)
        view.showLineNumbers(lineIndex, color: theme.lineNumber, background: theme.background)
        view.setBanner(notes.isEmpty ? nil : notes.joined(separator: " "))

        if let scope, highlightEnd > syncEnd {
            highlightRest(text: text, scope: scope, from: syncEnd, to: highlightEnd, styler: styler, markdown: doc.isMarkdown, notes: notes)
        }
    }

    /// Tokenizes up to `end` in the background, then applies everything after `start` in chunks.
    private func highlightRest(text: String, scope: String, from start: Int, to end: Int,
                               styler: TextStyler, markdown: Bool, notes: [String]) {
        let generation = self.generation
        let prefix = (text as NSString).substring(to: end)
        let theme = styler.theme
        Self.queue.async { [assets, languages] in
            let tokens = Self.highlighter(assets: assets, languages: languages).map { h -> Highlighter.Tokens in
                h.setTheme(theme)
                return h.loadGrammar(scope) ? h.tokenize(prefix, scope: scope) : .empty
            } ?? .empty
            let spans = markdown ? StyledSource.spans(in: prefix) : []
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.applyChunks(tokens: tokens, spans: spans, from: start, to: tokens.stoppedAt ?? end,
                                     styler: styler, generation: generation, notes: notes)
                }
            }
        }
    }

    private func applyChunks(tokens: Highlighter.Tokens, spans: [StyledSource.Span], from start: Int, to end: Int,
                             styler: TextStyler, generation: Int, notes: [String]) {
        guard generation == self.generation, let storage = view.textView.textStorage else { return }
        guard start < end else {
            if tokens.stoppedAt != nil {
                view.setBanner((notes + ["Highlighting stopped after \(PreviewLimits.highlightBudgetMillis / 1000) seconds."]).joined(separator: " "))
            }
            return
        }
        let chunkEnd = min(end, lineIndex.utf16Offset(afterLines: lineIndex.line(at: start) - 1 + PreviewLimits.applyChunkLines))
        let stop = max(chunkEnd, start + 1)
        styler.apply(tokens, to: storage, from: start, upTo: stop)
        styler.applyStyledSource(spans.filter { $0.range.location >= start && $0.range.location < stop }, to: storage)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.applyChunks(tokens: tokens, spans: spans, from: stop, to: end, styler: styler, generation: generation, notes: notes)
            }
        }
    }

    // MARK: - RTF and Fallback Card

    private func renderRTF(_ rtf: NSAttributedString) {
        view.setWraps(true)
        view.showLineNumbers(nil, color: .secondaryLabelColor, background: .textBackgroundColor)
        view.setBanner(nil)
        view.textView.usesAdaptiveColorMappingForDarkAppearance = true
        view.textView.backgroundColor = .textBackgroundColor
        view.scrollView.backgroundColor = .textBackgroundColor
        view.textView.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
        view.textView.textStorage?.setAttributedString(rtf)
    }

    private func renderCard(_ card: FallbackCard) {
        let s = NSMutableAttributedString()
        let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        let value: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
        s.append(NSAttributedString(string: fileName + "\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 15), .foregroundColor: NSColor.labelColor]))
        s.append(NSAttributedString(string: card.kind + "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]))
        let dates = DateFormatter()
        dates.dateStyle = .medium
        dates.timeStyle = .short
        for (name, text) in [("Size", card.size), ("Created", card.created.map(dates.string)), ("Modified", card.modified.map(dates.string))] {
            guard let text else { continue }
            s.append(NSAttributedString(string: name + "  ", attributes: label))
            s.append(NSAttributedString(string: text + "\n", attributes: value))
        }
        s.append(NSAttributedString(string: "\n" + card.hexDump + "\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.labelColor,
        ]))
        view.setWraps(false)
        view.showLineNumbers(nil, color: .secondaryLabelColor, background: .textBackgroundColor)
        view.setBanner(nil)
        view.textView.usesAdaptiveColorMappingForDarkAppearance = false
        view.textView.backgroundColor = .textBackgroundColor
        view.scrollView.backgroundColor = .textBackgroundColor
        view.textView.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
        view.textView.textStorage?.setAttributedString(s)
    }

    // MARK: - Highlighter (one per process, used only on `queue`)

    nonisolated static let queue = DispatchQueue(label: "com.mdrum.infiniview.highlighting", qos: .userInitiated)
    nonisolated(unsafe) private static var shared: Highlighter?
    nonisolated(unsafe) private static var sharedFailed = false

    /// Call on `queue` only. Nil if the engine couldn't start (the Preview then stays plain).
    nonisolated private static func highlighter(assets: URL, languages: LanguageIndex) -> Highlighter? {
        if shared == nil && !sharedFailed {
            shared = try? Highlighter(assets: assets, injections: languages.injections)
            sharedFailed = shared == nil
        }
        return shared
    }

    nonisolated private static func onHighlighter<T>(assets: URL, languages: LanguageIndex, _ body: (Highlighter) -> T) -> T where T: Sendable, T: Defaultable {
        queue.sync { highlighter(assets: assets, languages: languages).map(body) ?? T.defaultValue }
    }

    static func bytes(_ n: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }
}

protocol Defaultable { static var defaultValue: Self { get } }
extension Highlighter.Tokens: Defaultable { static var defaultValue: Self { .empty } }
