import Foundation
import Testing
@testable import InfiniviewCore

@Suite struct LineIndexTests {
    @Test func findsLineNumbersByUTF16Offset() {
        let index = LineIndex("ab\ncd\n\nefg")
        #expect(index.count == 4)
        #expect(index.line(at: 0) == 1)
        #expect(index.line(at: 2) == 1) // the newline belongs to its line
        #expect(index.line(at: 3) == 2)
        #expect(index.line(at: 6) == 3)
        #expect(index.line(at: 7) == 4)
        #expect(index.line(at: 99) == 4)
        #expect(index.start(ofLine: 4) == 7)
    }

    @Test func trailingNewlineDoesNotAddALine() {
        #expect(LineIndex("a\nb\n").count == 2)
        #expect(LineIndex("").count == 1)
    }

    @Test func crlfAndUnicode() {
        let index = LineIndex("日本\r\nx")
        #expect(index.count == 2)
        #expect(index.start(ofLine: 2) == 4)
    }

    @Test func lineRangesStopAtALimit() {
        let text = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let index = LineIndex(text)
        #expect(index.utf16Offset(afterLines: 3) == ("line 1\nline 2\nline 3\n" as NSString).length)
        #expect(index.utf16Offset(afterLines: 99) == (text as NSString).length)
    }
}
