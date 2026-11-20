import Foundation

/// One file, folder or link inside an archive.
public struct ArchiveEntry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case file
        case directory
        case link(target: String)
    }

    /// Slash-separated, without a leading "./" or "/" or a trailing "/".
    public var path: String
    public var kind: Kind
    /// Unpacked size, when the archive records it.
    public var size: Int64?
    /// Size inside a zip, when it differs from `size`.
    public var compressedSize: Int64?
    public var modified: Date?
    /// Unix permission bits, when the archive records them.
    public var permissions: UInt16?
    public var isEncrypted = false

    /// Where the entry's data starts: a zip's local header, or the offset in an unpacked tar stream.
    public internal(set) var location: Int64 = 0
    /// Zip compression method (0 stored, 8 deflate, 12 bzip2).
    var method: UInt16 = 0

    public var name: String { path.split(separator: "/").last.map(String.init) ?? path }
}

public enum ArchiveCompression: String, Sendable, Equatable {
    case none, gzip, bzip2, xz
}

public enum ArchiveFormat: Sendable, Equatable {
    case zip
    case tar(ArchiveCompression)
    /// One compressed file that isn't a tar archive.
    case compressed(ArchiveCompression)

    public var description: String {
        switch self {
        case .zip: "ZIP archive"
        case .tar(.none): "tar archive"
        case .tar(let c): "tar archive, \(c.rawValue) compressed"
        case .compressed(let c): "\(c.rawValue) compressed file"
        }
    }
}

/// Everything listed in one archive.
public struct ArchiveListing: Sendable {
    public enum Stop: Sendable, Equatable {
        /// More entries than `Archive.Limits.entries`.
        case entryLimit
        /// Listing took longer than `Archive.Limits.seconds`.
        case timeLimit
        /// The archive ends early or is damaged after the entries listed.
        case damaged
    }

    public var format: ArchiveFormat
    public var entries: [ArchiveEntry]
    /// Why the listing is incomplete, or nil if it lists everything.
    public var stoppedEarly: Stop?
}

public enum ArchiveError: Error, Equatable {
    case damaged
    case encrypted
    /// A zip compression method Infiniview can't unpack.
    case unsupportedMethod(UInt16)
    case notAFile
    /// Stopped by a time limit or because the result is no longer wanted.
    case stopped
}

/// Reads zip, tar (plain, gzip, bzip2, xz) and single gzip, bzip2 or xz files (ADR-0006).
public enum Archive {
    public struct Limits: Sendable {
        public var entries: Int
        public var seconds: Double
        public init(entries: Int = 20_000, seconds: Double = 2) {
            self.entries = entries
            self.seconds = seconds
        }
    }

    /// Whether the start of a file is one of the formats Infiniview reads.
    public static func recognizes(_ head: Data) -> Bool { detect(head) != nil }

    /// Lists an archive, or returns nil if the file isn't one Infiniview reads.
    /// Throws when the file starts like an archive but can't be read as one.
    public static func list(_ url: URL, limits: Limits = Limits()) throws -> ArchiveListing? {
        let head = try FileStream(url).read(512)
        guard let kind = detect(head) else { return nil }
        let deadline = Date().addingTimeInterval(limits.seconds)
        switch kind {
        case .zip:
            return try ZipReader.list(url, limits: limits)
        case .compressed(let compression):
            // Peek inside: a tar archive, or a single compressed file?
            let peek = try BlockReader(stream(url, compression)).read(512)
            if TarReader.isHeader(peek) {
                return try TarReader.list(BlockReader(stream(url, compression)), format: .tar(compression),
                                          limits: limits, deadline: deadline)
            }
            return ArchiveListing(format: .compressed(compression),
                                  entries: [singleEntry(url, compression: compression, head: head)], stoppedEarly: nil)
        case .tar:
            return try TarReader.list(BlockReader(FileStream(url)), format: .tar(.none), limits: limits, deadline: deadline)
        }
    }

    /// Unpacks up to `maxBytes` of an entry's data. `shouldStop` is checked as it goes, and makes
    /// it throw `ArchiveError.stopped`.
    public static func read(_ entry: ArchiveEntry, of listing: ArchiveListing, at url: URL, maxBytes: Int,
                            shouldStop: @escaping () -> Bool = { false }) throws -> Data {
        guard case .file = entry.kind else { throw ArchiveError.notAFile }
        if entry.isEncrypted { throw ArchiveError.encrypted }
        switch listing.format {
        case .zip:
            return try ZipReader.read(entry, at: url, maxBytes: maxBytes, shouldStop: shouldStop)
        case .tar(let compression):
            let reader = BlockReader(try stream(url, compression), shouldStop: shouldStop)
            try reader.skip(entry.location)
            return try reader.read(Int(min(Int64(maxBytes), entry.size ?? 0)))
        case .compressed(let compression):
            return try BlockReader(stream(url, compression), shouldStop: shouldStop).read(maxBytes)
        }
    }

    // MARK: -

    private enum Detected { case zip, tar, compressed(ArchiveCompression) }

    private static func detect(_ head: Data) -> Detected? {
        let b = [UInt8](head.prefix(512))
        if b.starts(with: [0x50, 0x4B, 0x03, 0x04]) || b.starts(with: [0x50, 0x4B, 0x05, 0x06]) { return .zip }
        if b.starts(with: [0x1F, 0x8B]) { return .compressed(.gzip) }
        if b.starts(with: Array("BZh".utf8)), b.count > 3, (0x31...0x39).contains(b[3]) { return .compressed(.bzip2) }
        if b.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return .compressed(.xz) }
        if TarReader.isHeader(Data(b)) { return .tar }
        return nil
    }

    static func stream(_ url: URL, _ compression: ArchiveCompression) throws -> ByteStream {
        let file = try FileStream(url)
        switch compression {
        case .none: return file
        case .gzip: return try InflateStream(file, gzip: true)
        case .bzip2: return try Bzip2Stream(source: file)
        case .xz: return try XZStream(source: file)
        }
    }

    /// The one entry of a single compressed file: named as gzip recorded it, or after the file
    /// without its last extension.
    private static func singleEntry(_ url: URL, compression: ArchiveCompression, head: Data) -> ArchiveEntry {
        var name = url.deletingPathExtension().lastPathComponent
        var size: Int64?
        if compression == .gzip {
            if let original = gzipName(head) { name = original }
            // The last four bytes hold the unpacked size, but only modulo 4 GiB: trusted only for a
            // file small enough that it can't have unpacked past that.
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if fileSize >= 18, fileSize < 64 << 20, let h = try? FileHandle(forReadingFrom: url) {
                defer { try? h.close() }
                try? h.seek(toOffset: UInt64(fileSize - 4))
                if let tail = try? h.read(upToCount: 4), tail.count == 4 {
                    size = Int64(Bytes(tail).u32(0))
                }
            }
        }
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return ArchiveEntry(path: name, kind: .file, size: size, modified: modified)
    }

    /// The original file name in a gzip header (FNAME), if recorded.
    private static func gzipName(_ head: Data) -> String? {
        let b = [UInt8](head)
        guard b.count > 10, b[3] & 0x08 != 0 else { return nil }
        var i = 10
        if b[3] & 0x04 != 0 { // FEXTRA
            guard b.count > 12 else { return nil }
            i += 2 + (Int(b[10]) | Int(b[11]) << 8)
        }
        guard i < b.count, let end = b[i...].firstIndex(of: 0) else { return nil }
        let name = String(decoding: b[i..<end], as: UTF8.self)
        let base = (name as NSString).lastPathComponent
        return base.isEmpty ? nil : base
    }
}

/// Little-endian reads from a byte array.
struct Bytes {
    let b: [UInt8]
    init(_ data: Data) { b = [UInt8](data) }
    init(_ bytes: [UInt8]) { b = bytes }
    var count: Int { b.count }
    func u16(_ i: Int) -> UInt16 { i + 2 <= b.count ? UInt16(b[i]) | UInt16(b[i + 1]) << 8 : 0 }
    func u32(_ i: Int) -> UInt32 { i + 4 <= b.count ? UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 : 0 }
    func u64(_ i: Int) -> UInt64 { i + 8 <= b.count ? UInt64(u32(i)) | UInt64(u32(i + 4)) << 32 : 0 }
    subscript(_ r: Range<Int>) -> ArraySlice<UInt8> { b[max(0, r.lowerBound)..<min(b.count, r.upperBound)] }
}

extension String {
    /// An archive path made consistent: no leading "./" or "/", no trailing "/".
    var archivePath: String {
        var parts = split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        while parts.first == "." { parts.removeFirst() }
        return parts.filter { $0 != "." }.joined(separator: "/")
    }

    /// macOS metadata that archivers add and Finder's Archive Utility hides: "__MACOSX/" and "._name".
    var isMacMetadataPath: Bool {
        hasPrefix("__MACOSX/") || self == "__MACOSX" || split(separator: "/").last?.hasPrefix("._") == true
    }
}
