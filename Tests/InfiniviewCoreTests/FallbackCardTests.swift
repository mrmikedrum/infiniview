import Foundation
import Testing
@testable import InfiniviewCore

@Suite struct FallbackCardTests {
    func kind(_ bytes: [UInt8]) -> String { FileKind.describe(Data(bytes)) }

    @Test func recognisesCommonFormats() {
        #expect(kind([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0x02, 0, 0, 0]) == "Mach-O 64-bit executable arm64")
        #expect(kind([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0x06, 0, 0, 0]) == "Mach-O 64-bit dynamically linked shared library x86_64")
        #expect(kind([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2]) == "Mach-O universal binary with 2 architectures")
        #expect(kind([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 61]) == "compiled Java class data, version 61")
        #expect(kind([0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0]) == "ELF 64-bit LSB file")
        #expect(kind(Array("MZ".utf8) + [0x90, 0]) == "MS-DOS/Windows executable")
        #expect(kind([0x50, 0x4B, 0x03, 0x04]) == "Zip archive data")
        #expect(kind([0x1F, 0x8B, 0x08]) == "gzip compressed data")
        #expect(kind(Array("BZh9".utf8)) == "bzip2 compressed data")
        #expect(kind([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) == "XZ compressed data")
        #expect(kind([0x28, 0xB5, 0x2F, 0xFD]) == "Zstandard compressed data")
        #expect(kind(Array("%PDF-1.7\n".utf8)) == "PDF document, version 1.7")
        #expect(kind([0x89] + Array("PNG\r\n".utf8) + [0x1A, 0x0A, 0, 0, 0, 13] + Array("IHDR".utf8) + [0, 0, 1, 0, 0, 0, 0, 0x80]) == "PNG image data, 256 x 128")
        #expect(kind([0xFF, 0xD8, 0xFF, 0xE0]) == "JPEG image data")
        #expect(kind(Array("GIF89a".utf8)) == "GIF image data")
        #expect(kind(Array("SQLite format 3\0".utf8)) == "SQLite 3 database")
        #expect(kind(Array("bplist00".utf8)) == "Apple binary property list")
        #expect(kind([0x00, 0x61, 0x73, 0x6D, 1, 0, 0, 0]) == "WebAssembly binary module")
        #expect(kind(Array("7z".utf8) + [0xBC, 0xAF, 0x27, 0x1C]) == "7-zip archive data")
        #expect(kind(Array("Rar!".utf8) + [0x1A, 0x07]) == "RAR archive data")
    }

    @Test func recognisesTarByItsHeader() {
        var header = [UInt8](repeating: 0, count: 512)
        header.replaceSubrange(257..<262, with: Array("ustar".utf8))
        #expect(kind(header) == "POSIX tar archive")
    }

    @Test func unknownIsData() {
        #expect(kind([0x00, 0x01, 0x02, 0x03]) == "data")
        #expect(kind([]) == "empty")
    }

    @Test func hexDumpLooksLikeHexdumpC() {
        let dump = HexDump.format(Data(Array("Hello, world!\n".utf8) + [0x00, 0xFF, 0x41]))
        #expect(dump == """
        00000000  48 65 6c 6c 6f 2c 20 77  6f 72 6c 64 21 0a 00 ff  |Hello, world!...|
        00000010  41                                                |A|
        """)
    }

    @Test func hexDumpStopsAtTheLimit() {
        let dump = HexDump.format(Data(repeating: 0x41, count: 100), limit: 32)
        #expect(dump.split(separator: "\n").count == 2)
    }

    @Test func cardSummarisesTheFile() {
        let created = Date(timeIntervalSince1970: 0), modified = Date(timeIntervalSince1970: 86_400)
        let card = FallbackCard(head: Data([0x1F, 0x8B, 0x08, 0x00]), size: 2_500_000, created: created, modified: modified)
        #expect(card.kind == "gzip compressed data")
        #expect(card.size.contains(NumberFormatter.localizedString(from: 2_500_000, number: .decimal) + " bytes"))
        #expect(card.created == created && card.modified == modified)
        #expect(card.hexDump.hasPrefix("00000000  1f 8b 08 00"))
        #expect(FallbackCard(head: Data([1]), size: 130, created: nil, modified: nil).size == "130 bytes")
    }
}
