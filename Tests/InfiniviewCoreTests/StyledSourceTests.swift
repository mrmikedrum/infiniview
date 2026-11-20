import Foundation
import Testing
@testable import InfiniviewCore

@Suite struct StyledSourceTests {
    /// Spans as "kind:text" for easy comparison.
    func spans(_ markdown: String) -> [String] {
        let ns = markdown as NSString
        return StyledSource.spans(in: markdown).map { "\($0.kind):\(ns.substring(with: $0.range))" }
    }

    @Test func headingsAreStyledWithTheirMarkersDimmed() {
        #expect(spans("# Title\n") == ["heading(1):# Title", "marker:# "])
        #expect(spans("### Third ###\n") == ["heading(3):### Third ###", "marker:### ", "marker: ###"])
        #expect(spans("#nospace\n").isEmpty)
    }

    @Test func boldAndItalicKeepTheirMarkers() {
        #expect(spans("a **b** c") == ["marker:**", "bold:b", "marker:**"])
        #expect(spans("a *b* c") == ["marker:*", "italic:b", "marker:*"])
        #expect(spans("__b__ and _i_") == ["marker:__", "bold:b", "marker:__", "marker:_", "italic:i", "marker:_"])
    }

    @Test func underscoresInsideWordsAreNotItalic() {
        #expect(spans("snake_case_name").isEmpty)
    }

    @Test func inlineCode() {
        #expect(spans("use `x * y` here") == ["marker:`", "code:x * y", "marker:`"])
    }

    @Test func noEmphasisInsideInlineCode() {
        #expect(spans("`**not bold**`") == ["marker:`", "code:**not bold**", "marker:`"])
    }

    @Test func links() {
        #expect(spans("see [docs](https://example.com) now") == [
            "marker:[", "link:docs", "marker:](", "url:https://example.com", "marker:)",
        ])
    }

    @Test func listAndQuoteMarkers() {
        #expect(spans("- one\n* two\n12. three\n> quoted\n") == [
            "marker:- ", "marker:* ", "marker:12. ", "marker:> ",
        ])
    }

    @Test func fencedCodeIsLeftToItsGrammar() {
        let md = "```python\nx = **1**\n```\nafter **b**\n"
        #expect(spans(md) == ["marker:```python", "marker:```", "marker:**", "bold:b", "marker:**"])
    }

    @Test func tablesAreLeftAlone() {
        #expect(spans("| a | b |\n|---|---|\n| 1 | 2 |\n").isEmpty)
    }

    @Test func rangesAreUTF16() {
        let md = "日本 **語**"
        let s = StyledSource.spans(in: md)
        #expect((md as NSString).substring(with: s[1].range) == "語")
    }
}
