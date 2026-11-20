import AppKit
import Foundation
import InfiniviewCore
import Testing
@testable import InfiniviewPreview

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../..").standardized
let assets = repo.appendingPathComponent("Vendor/highlighting")
let corpus = repo.appendingPathComponent("Tests/Fixtures/corpus")
let languages = try! LanguageIndex(json: Data(contentsOf: assets.appendingPathComponent("languages.json")))

@Suite struct PreviewContentTests {
    func load(_ name: String) throws -> PreviewContent {
        try PreviewContent.load(corpus.appendingPathComponent(name), languages: languages)
    }

    @Test func rtfInATxtFileRendersFormatted() throws {
        guard case .rtf(let s) = try load("rtf-in-txt.txt") else { Issue.record("not rtf"); return }
        #expect(s.string.contains("Hello bold world."))
    }

    @Test func binaryGetsAFallbackCard() throws {
        guard case .card(let card) = try load("archive.gz") else { Issue.record("not a card"); return }
        #expect(card.kind == "gzip compressed data")
        #expect(!card.hexDump.isEmpty)
    }

    @Test func textGetsItsLanguage() throws {
        guard case .text(let doc) = try load("styled.md") else { Issue.record("not text"); return }
        #expect(doc.isMarkdown)
        guard case .text(let script) = try load("tool") else { Issue.record("not text"); return }
        #expect(script.language?.id == "python")
    }

    @Test func utf16IsDecoded() throws {
        guard case .text(let doc) = try load("utf16le.txt") else { Issue.record("not text"); return }
        #expect(doc.text == "UTF-16 little endian café\n")
    }

    @Test func emptyFileIsEmptyText() throws {
        guard case .text(let doc) = try load("empty") else { Issue.record("not text"); return }
        #expect(doc.text.isEmpty && doc.totalBytes == 0)
    }

    @Test func largeFilesAreTruncatedCleanly() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("iv-large-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(String(repeating: "é", count: 50_000).utf8).write(to: url) // 100,000 bytes
        guard case .text(let doc) = try PreviewContent.load(url, languages: languages, maxShownBytes: 40_001) else {
            Issue.record("not text"); return
        }
        #expect(doc.isTruncated && doc.totalBytes == 100_000 && doc.shownBytes == 40_001)
        #expect(doc.text == String(repeating: "é", count: 20_000)) // the split "é" is dropped
    }
}

@Suite(.serialized) struct HighlightingTests {
    nonisolated(unsafe) static let highlighter = try! Highlighter(assets: assets, injections: languages.injections)
    static let dark = Theme.current(dark: true, assets: assets, settings: SharedSettings(defaults: UserDefaults(suiteName: "iv-tests")))

    @Test func tokenizesWithColours() throws {
        let h = Self.highlighter
        h.setTheme(Self.dark)
        #expect(h.loadGrammar("source.python"))
        let tokens = h.tokenize("def greet(name):\n    return 'hi'\n", scope: "source.python")
        #expect(tokens.pairs.count >= 8)
        #expect(tokens.stoppedAt == nil)
        let colours = Set(stride(from: 1, to: tokens.pairs.count, by: 2).map { TokenMetadata.foreground(tokens.pairs[$0]) })
        #expect(colours.count >= 3) // keyword, function name, string...
    }

    @Test func unknownGrammarIsRefused() {
        #expect(!Self.highlighter.loadGrammar("source.does-not-exist"))
        #expect(!Self.highlighter.loadGrammar("../themes/dark"))
    }

    @Test func styledSourceMakesHeadingsLargerAndKeepsMarkers() throws {
        let h = Self.highlighter
        h.setTheme(Self.dark)
        #expect(h.loadGrammar("text.html.markdown"))
        let md = "# Title\n\nSome **bold** text.\n"
        let styler = TextStyler(theme: Self.dark, fontSize: 12)
        let s = styler.plain(md)
        styler.apply(h.tokenize(md, scope: "text.html.markdown"), to: s, upTo: (md as NSString).length)
        styler.applyStyledSource(StyledSource.spans(in: md), to: s)
        #expect(s.string == md)
        let headingFont = try #require(s.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
        let bodyFont = try #require(s.attribute(.font, at: 10, effectiveRange: nil) as? NSFont)
        #expect(headingFont.pointSize > bodyFont.pointSize)
        let boldFont = try #require(s.attribute(.font, at: 16, effectiveRange: nil) as? NSFont)
        #expect(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
        let marker = try #require(s.attribute(.foregroundColor, at: 14, effectiveRange: nil) as? NSColor)
        #expect(marker.alphaComponent < 1) // "**" dimmed
    }
}

@Suite struct TextStylerTests {
    @Test func appliesOnlyFromTheGivenStart() throws {
        let theme = Theme.current(dark: false, assets: assets, settings: SharedSettings(defaults: UserDefaults(suiteName: "iv-tests")))
        theme.colorMap = ["", "#000000", "#FF0000", "#00FF00"]
        let styler = TextStyler(theme: theme, fontSize: 12)
        let s = styler.plain("aaaa bbbb cccc")
        // tokens: 0 red, 5 green, 10 red
        let red = UInt32(2 << 15), green = UInt32(3 << 15)
        let tokens = Highlighter.Tokens(pairs: [0, red, 5, green, 10, red], stoppedAt: nil)
        styler.apply(tokens, to: s, from: 7, upTo: 14)
        func color(_ i: Int) -> NSColor? { s.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor }
        #expect(color(2) == theme.foreground) // before start: untouched
        #expect(color(5) == theme.foreground)
        #expect(color(8)?.greenComponent == 1)
        #expect(color(12)?.redComponent == 1)
    }
}

@Suite struct PreviewControllerTests {
    @MainActor @Test func textStaysOnTextKit2WithLineNumbers() throws {
        let controller = try PreviewController(assets: assets)
        try controller.load(corpus.appendingPathComponent("styled.md"))
        controller.view.layoutSubtreeIfNeeded()
        controller.view.scrollView.verticalRulerView?.display()
        #expect(controller.view.textView.textLayoutManager != nil)
        #expect(controller.view.textView.string.hasPrefix("# Title"))
        #expect(controller.view.textView.frame.width > 100)
    }

    @MainActor @Test func narrowPreviewUsesSmallerText() throws {
        let controller = try PreviewController(assets: assets)
        let file = corpus.appendingPathComponent("tool")
        func bodySize() -> CGFloat? {
            (controller.view.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
        }
        controller.view.setFrameSize(NSSize(width: 900, height: 600))
        try controller.load(file)
        #expect(!controller.view.isCompact && bodySize() == 12)
        controller.view.setFrameSize(NSSize(width: 400, height: 600))
        try controller.load(file)
        #expect(controller.view.isCompact && bodySize() == 9)
    }

    @MainActor @Test func binaryShowsTheCard() throws {
        let controller = try PreviewController(assets: assets)
        try controller.load(corpus.appendingPathComponent("noext-binary"))
        #expect(controller.view.textView.string.contains("ELF 64-bit LSB file"))
        #expect(controller.view.textView.string.contains("00000000  7f 45 4c 46"))
    }
}
