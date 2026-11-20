import Foundation

/// What the Fallback Card shows for a file that isn't a Text File.
public struct FallbackCard: Sendable {
    /// Bytes of the file shown in the hex dump.
    public static let hexDumpBytes = 4096

    public let kind: String
    public let size: String
    public let created: Date?
    public let modified: Date?
    public let hexDump: String

    public init(head: Data, size: Int, created: Date?, modified: Date?) {
        kind = FileKind.describe(head)
        let exact = NumberFormatter.localizedString(from: NSNumber(value: size), number: .decimal)
        self.size = "\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) (\(exact) bytes)"
        self.created = created
        self.modified = modified
        hexDump = HexDump.format(head, limit: Self.hexDumpBytes)
    }
}

/// A short description of a binary file's format from its first bytes, in the style of `file(1)`.
public enum FileKind {
    public static func describe(_ data: Data) -> String {
        let b = [UInt8](data.prefix(1024))
        if b.isEmpty { return "empty" }
        func starts(_ p: [UInt8], at offset: Int = 0) -> Bool { b.count >= offset + p.count && Array(b[offset..<offset + p.count]) == p }
        func ascii(_ s: String, at offset: Int = 0) -> Bool { starts(Array(s.utf8), at: offset) }
        func u32le(_ o: Int) -> UInt32 { b.count >= o + 4 ? UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24 : 0 }
        func u32be(_ o: Int) -> UInt32 { b.count >= o + 4 ? UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3]) : 0 }

        if starts([0xCF, 0xFA, 0xED, 0xFE]) || starts([0xCE, 0xFA, 0xED, 0xFE]) {
            return machO(bits: b[0] == 0xCF ? 64 : 32, cpu: u32le(4), fileType: u32le(12))
        }
        if starts([0xCA, 0xFE, 0xBA, 0xBE]) {
            // Shared by fat Mach-O and Java classes: a fat binary has few architectures, a class
            // file's major version is 45 or more.
            let n = u32be(4)
            return n < 30 ? "Mach-O universal binary with \(n) architecture\(n == 1 ? "" : "s")"
                          : "compiled Java class data, version \(b.count >= 8 ? Int(b[6]) << 8 | Int(b[7]) : 0)"
        }
        if starts([0x7F, 0x45, 0x4C, 0x46]) {
            let bits = b.count > 4 && b[4] == 2 ? "64" : "32", order = b.count > 5 && b[5] == 2 ? "MSB" : "LSB"
            return "ELF \(bits)-bit \(order) file"
        }
        if ascii("MZ") { return "MS-DOS/Windows executable" }
        if starts([0x50, 0x4B, 0x03, 0x04]) || starts([0x50, 0x4B, 0x05, 0x06]) { return "Zip archive data" }
        if starts([0x1F, 0x8B]) { return "gzip compressed data" }
        if ascii("BZh") { return "bzip2 compressed data" }
        if starts([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return "XZ compressed data" }
        if starts([0x28, 0xB5, 0x2F, 0xFD]) { return "Zstandard compressed data" }
        if starts(Array("7z".utf8) + [0xBC, 0xAF, 0x27, 0x1C]) { return "7-zip archive data" }
        if ascii("Rar!") { return "RAR archive data" }
        if ascii("ustar", at: 257) { return "POSIX tar archive" }
        if ascii("%PDF-") {
            let version = String(decoding: b.dropFirst(5).prefix(while: { $0 == 0x2E || (0x30...0x39).contains($0) }), as: UTF8.self)
            return version.isEmpty ? "PDF document" : "PDF document, version \(version)"
        }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return ascii("IHDR", at: 12) ? "PNG image data, \(u32be(16)) x \(u32be(20))" : "PNG image data"
        }
        if starts([0xFF, 0xD8, 0xFF]) { return "JPEG image data" }
        if ascii("GIF87a") || ascii("GIF89a") { return "GIF image data" }
        if ascii("RIFF") && ascii("WEBP", at: 8) { return "WebP image data" }
        if ascii("RIFF") && ascii("WAVE", at: 8) { return "WAVE audio" }
        if ascii("ftyp", at: 4) { return "ISO media (MP4/QuickTime family)" }
        if ascii("SQLite format 3") { return "SQLite 3 database" }
        if ascii("bplist") { return "Apple binary property list" }
        if starts([0x00, 0x61, 0x73, 0x6D]) { return "WebAssembly binary module" }
        if ascii("!<arch>\n") { return "ar archive" }
        if starts([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) { return "Microsoft compound document (legacy Office)" }
        return "data"
    }

    private static func machO(bits: Int, cpu: UInt32, fileType: UInt32) -> String {
        let arch: String = switch cpu {
        case 0x0100_000C: "arm64"
        case 0x0100_0007: "x86_64"
        case 0x0000_000C: "arm"
        case 0x0000_0007: "i386"
        default: "unknown architecture"
        }
        let type: String = switch fileType {
        case 1: "object"
        case 2: "executable"
        case 6: "dynamically linked shared library"
        case 8: "bundle"
        case 0xA: "debug symbols"
        default: "file"
        }
        return "Mach-O \(bits)-bit \(type) \(arch)"
    }
}

/// `hexdump -C` style lines: offset, 16 bytes in two groups of 8, printable ASCII.
public enum HexDump {
    public static func format(_ data: Data, limit: Int = FallbackCard.hexDumpBytes) -> String {
        let bytes = [UInt8](data.prefix(limit))
        var lines = [String]()
        lines.reserveCapacity(bytes.count / 16 + 1)
        var offset = 0
        while offset < bytes.count {
            let row = bytes[offset..<min(offset + 16, bytes.count)]
            var hex = ""
            for (i, byte) in row.enumerated() {
                hex += String(format: "%02x ", byte)
                if i == 7 { hex += " " }
            }
            let ascii = String(row.map { (0x20...0x7E).contains($0) ? Character(Unicode.Scalar($0)) : "." })
            let padded = hex.padding(toLength: 49, withPad: " ", startingAt: 0)
            lines.append(String(format: "%08x  ", offset) + padded + " |" + ascii + "|")
            offset += 16
        }
        return lines.joined(separator: "\n")
    }
}
