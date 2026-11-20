import Foundation
import Testing
@testable import InfiniviewCore

@Suite struct ClassifierTests {
    func classify(_ bytes: [UInt8], truncated: Bool = false) -> Classification {
        Classifier.classify(sample: Data(bytes), isTruncated: truncated)
    }

    func classify(_ text: String) -> Classification { classify(Array(text.utf8)) }

    @Test func plainASCIIIsUTF8Text() {
        #expect(classify("hello\nworld\n") == .text(.utf8))
    }

    @Test func multibyteUTF8IsText() {
        #expect(classify("café — 日本語 ✓\n") == .text(.utf8))
    }

    @Test func multibyteCharacterCutAtTheEndOfATruncatedSampleIsStillUTF8() {
        let bytes = Array("abc é".utf8).dropLast() // ends inside "é"
        #expect(classify(Array(bytes), truncated: true) == .text(.utf8))
    }

    @Test func invalidUTF8WithoutNULsIsLatin1() {
        #expect(classify(Array("caf".utf8) + [0xE9, 0x0A]) == .text(.latin1))
    }

    @Test func cutCharacterInAWholeFileIsNotUTF8() {
        #expect(classify(Array(Array("abc é".utf8).dropLast()), truncated: false) == .text(.latin1))
    }

    @Test func utf8BOM() {
        #expect(classify([0xEF, 0xBB, 0xBF] + Array("hi".utf8)) == .text(.utf8BOM))
    }

    @Test func utf16WithBOM() {
        let le: [UInt8] = [0xFF, 0xFE] + Array("hi\n".data(using: .utf16LittleEndian)!)
        let be: [UInt8] = [0xFE, 0xFF] + Array("hi\n".data(using: .utf16BigEndian)!)
        #expect(classify(le) == .text(.utf16LE))
        #expect(classify(be) == .text(.utf16BE))
    }

    @Test func utf16WithoutBOMIsNotText() {
        #expect(classify(Array("hello".data(using: .utf16LittleEndian)!)) == .binary)
    }

    @Test func utf32BOMIsNotMistakenForUTF16() {
        #expect(classify([0xFF, 0xFE, 0x00, 0x00, 0x68, 0x00, 0x00, 0x00]) == .binary)
    }

    @Test func rtfContentWinsWhateverTheBytesAfter() {
        #expect(classify(#"{\rtf1\ansi Hello}"#) == .rtf)
    }

    @Test func nulByteMeansBinary() {
        #expect(classify(Array("abc".utf8) + [0x00] + Array("def".utf8)) == .binary)
    }

    @Test func manyControlCharactersMeanBinary() {
        #expect(classify(Array(repeating: [0x01, 0x02, 0x41, 0x42], count: 50).flatMap { $0 }) == .binary)
    }

    @Test func tabsEscapesAndFormFeedsAreFine() {
        #expect(classify("a\tb\r\n\u{1B}[31mred\u{1B}[0m\u{0C}next\n") == .text(.utf8))
    }

    @Test func aFewStrayControlCharactersInLongTextAreTolerated() {
        let text = String(repeating: "ordinary line of text\n", count: 100) + "\u{01}"
        #expect(classify(text) == .text(.utf8))
    }

    @Test func emptyFileIsText() {
        #expect(classify([]) == .text(.utf8))
    }

    @Test func decodesEachEncoding() {
        #expect(Classifier.decode(Data([0xEF, 0xBB, 0xBF, 0x68, 0x69]), as: .utf8BOM) == "hi")
        #expect(Classifier.decode(Data([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00]), as: .utf16LE) == "hi")
        #expect(Classifier.decode(Data([0xFE, 0xFF, 0x00, 0x68, 0x00, 0x69]), as: .utf16BE) == "hi")
        #expect(Classifier.decode(Data([0x63, 0x61, 0x66, 0xE9]), as: .latin1) == "café")
        #expect(Classifier.decode(Data([0x61, 0xFF, 0x62]), as: .utf8) == "a\u{FFFD}b") // a bad byte past the sample
    }

    @Test func fixtureCorpusClassifiesAsExpected() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../Fixtures/corpus").standardized
        let manifest = try String(contentsOf: dir.appendingPathComponent("expected.tsv"), encoding: .utf8)
        var checked = 0
        for line in manifest.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "\t").map(String.init)
            let result = try Classifier.classify(fileAt: dir.appendingPathComponent(parts[0]))
            #expect(result.label == parts[1], "\(parts[0])")
            checked += 1
        }
        #expect(checked > 20)
    }
}
