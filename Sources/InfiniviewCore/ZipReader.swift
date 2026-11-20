import Foundation

/// Zip archives, from their central directory at the end of the file; nothing is unpacked to
/// list them.
enum ZipReader {
    /// Largest central directory read.
    static let maxDirectoryBytes = 64 * 1024 * 1024

    static func list(_ url: URL, limits: Archive.Limits) throws -> ArchiveListing {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = Int64(try handle.seekToEnd())

        // The end record is in the last 22 bytes plus a comment of up to 64 KiB.
        let tailLength = min(fileSize, 22 + 0xFFFF)
        try handle.seek(toOffset: UInt64(fileSize - tailLength))
        let tail = Bytes(try handle.read(upToCount: Int(tailLength)) ?? Data())
        guard let end = stride(from: tail.count - 22, through: 0, by: -1).first(where: { tail.u32($0) == 0x0605_4B50 }) else {
            throw ArchiveError.damaged
        }
        var count = Int64(tail.u16(end + 10))
        var directorySize = Int64(tail.u32(end + 12))
        var directoryOffset = Int64(tail.u32(end + 16))
        // Where the directory should end: at the end record, or at the zip64 one before it.
        var directoryEnd = fileSize - tailLength + Int64(end)

        // Zip64: a locator just before the end record points at a larger one. Writers add it
        // even when no field in the end record is full, so look for it either way.
        if end >= 20, tail.u32(end - 20) == 0x0706_4B50 {
            let record64 = tail.u64(end - 20 + 8)
            guard record64 < UInt64(fileSize) else { throw ArchiveError.damaged }
            directoryEnd = Int64(record64)
            try handle.seek(toOffset: record64)
            let record = Bytes(try handle.read(upToCount: 56) ?? Data())
            guard record.u32(0) == 0x0606_4B50 else { throw ArchiveError.damaged }
            count = Int64(record.u64(32))
            directorySize = Int64(record.u64(40))
            directoryOffset = Int64(record.u64(48))
        }

        // Data before the archive (a self-extracting stub) shifts every offset.
        let shift = max(0, directoryEnd - directorySize - directoryOffset)
        guard directoryOffset + shift + directorySize <= fileSize else { throw ArchiveError.damaged }
        // A directory too large to read whole (millions of entries) is listed as far as it's read.
        try handle.seek(toOffset: UInt64(directoryOffset + shift))
        let dir = Bytes(try handle.read(upToCount: Int(min(directorySize, Int64(maxDirectoryBytes)))) ?? Data())
        let cut = directorySize > Int64(maxDirectoryBytes)

        var entries = [ArchiveEntry]()
        var stop: ArchiveListing.Stop?
        var i = 0
        var seen: Int64 = 0
        while seen < count {
            guard dir.u32(i) == 0x0201_4B50, i + 46 <= dir.count else { stop = cut ? .entryLimit : .damaged; break }
            let madeBy = dir.u16(i + 4) >> 8
            let flags = dir.u16(i + 8)
            let method = dir.u16(i + 10)
            let dosTime = dir.u16(i + 12), dosDate = dir.u16(i + 14)
            var compressed = Int64(dir.u32(i + 20))
            var size = Int64(dir.u32(i + 24))
            let nameLength = Int(dir.u16(i + 28)), extraLength = Int(dir.u16(i + 30)), commentLength = Int(dir.u16(i + 32))
            let external = dir.u32(i + 38)
            var local = Int64(dir.u32(i + 42))
            let nameBytes = Array(dir[(i + 46)..<(i + 46 + nameLength)])
            let extra = Bytes(Array(dir[(i + 46 + nameLength)..<(i + 46 + nameLength + extraLength)]))
            i += 46 + nameLength + extraLength + commentLength
            seen += 1

            var modified = dosDateTime(date: dosDate, time: dosTime)
            forEachExtra(extra) { id, field in
                switch id {
                case 0x0001: // Zip64 sizes and offset, present only where the main field is full
                    var j = 0
                    if size == 0xFFFF_FFFF { size = Int64(field.u64(j)); j += 8 }
                    if compressed == 0xFFFF_FFFF { compressed = Int64(field.u64(j)); j += 8 }
                    if local == 0xFFFF_FFFF { local = Int64(field.u64(j)) }
                case 0x5455 where field.count >= 5 && field.b[0] & 1 != 0: // extended timestamp, UTC
                    modified = Date(timeIntervalSince1970: TimeInterval(Int32(bitPattern: field.u32(1))))
                default: break
                }
            }

            let rawName = decodeName(nameBytes, utf8: flags & 0x0800 != 0)
            let path = rawName.replacingOccurrences(of: "\\", with: "/").archivePath
            guard !path.isEmpty, !path.isMacMetadataPath else { continue }
            let unixMode: UInt16? = (madeBy == 3 || madeBy == 19) && external >> 16 != 0 ? UInt16(external >> 16) : nil
            let isDirectory = rawName.hasSuffix("/") || external & 0x10 != 0 || unixMode.map { $0 & 0o170000 == 0o040000 } == true
            let isLink = unixMode.map { $0 & 0o170000 == 0o120000 } == true

            var entry = ArchiveEntry(path: path, kind: isDirectory ? .directory : .file,
                                     size: isDirectory ? nil : size, compressedSize: isDirectory ? nil : compressed,
                                     modified: modified, permissions: unixMode.map { $0 & 0o7777 },
                                     isEncrypted: flags & 1 != 0 || method == 99)
            entry.location = local + shift
            entry.method = method
            if isLink, size < 4096 {
                // A link's target is its data.
                let target = (try? read(entry, at: url, maxBytes: Int(size))).map { String(decoding: $0, as: UTF8.self) }
                entry.kind = .link(target: target ?? "")
            }
            entries.append(entry)
            if entries.count >= limits.entries, seen < count { stop = .entryLimit; break }
        }
        if entries.isEmpty && stop == .damaged { throw ArchiveError.damaged }
        return ArchiveListing(format: .zip, entries: entries, stoppedEarly: stop)
    }

    static func read(_ entry: ArchiveEntry, at url: URL, maxBytes: Int, shouldStop: @escaping () -> Bool = { false }) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        try handle.seek(toOffset: UInt64(entry.location))
        let header = Bytes(try handle.read(upToCount: 30) ?? Data())
        try? handle.close()
        guard header.u32(0) == 0x0403_4B50 else { throw ArchiveError.damaged }
        let start = entry.location + 30 + Int64(header.u16(26)) + Int64(header.u16(28))
        let raw = try FileStream(url, from: start, length: entry.compressedSize ?? 0)
        let stream: ByteStream = switch entry.method {
        case 0: raw
        case 8: try InflateStream(raw, gzip: false)
        case 12: try Bzip2Stream(source: raw)
        default: throw ArchiveError.unsupportedMethod(entry.method)
        }
        return try BlockReader(stream, shouldStop: shouldStop).read(Int(min(Int64(maxBytes), entry.size ?? Int64(maxBytes))))
    }

    private static func forEachExtra(_ extra: Bytes, _ body: (UInt16, Bytes) -> Void) {
        var j = 0
        while j + 4 <= extra.count {
            let id = extra.u16(j), length = Int(extra.u16(j + 2))
            body(id, Bytes(Array(extra[(j + 4)..<(j + 4 + length)])))
            j += 4 + length
        }
    }

    /// Zip names are UTF-8 when flagged; otherwise often UTF-8 anyway, else the old DOS code page.
    private static func decodeName(_ bytes: [UInt8], utf8: Bool) -> String {
        if utf8 || bytes.allSatisfy({ $0 < 0x80 }) { return String(decoding: bytes, as: UTF8.self) }
        if let s = String(validating: bytes, as: UTF8.self) { return s }
        let dos = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)))
        return String(data: Data(bytes), encoding: dos) ?? String(decoding: bytes, as: UTF8.self)
    }

    /// DOS dates are local time. Worked out by hand: Calendar is slow over many thousands of entries.
    private static func dosDateTime(date: UInt16, time: UInt16) -> Date? {
        guard date != 0 else { return nil }
        var y = 1980 + Int(date >> 9)
        let m = Int(date >> 5 & 0xF), d = Int(date & 0x1F)
        guard (1...12).contains(m), (1...31).contains(d) else { return nil }
        // Days since 1970-01-01 (Howard Hinnant's days_from_civil).
        if m <= 2 { y -= 1 }
        let era = y / 400, yoe = y - era * 400
        let doy = (153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1
        let days = era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
        let seconds = days * 86_400 + Int(time >> 11) * 3_600 + Int(time >> 5 & 0x3F) * 60 + Int(time & 0x1F) * 2
        let asUTC = Date(timeIntervalSince1970: TimeInterval(seconds))
        return asUTC.addingTimeInterval(-TimeInterval(TimeZone.current.secondsFromGMT(for: asUTC)))
    }
}
