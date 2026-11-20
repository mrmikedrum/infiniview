import Foundation

/// tar archives (POSIX ustar and pax, GNU, and old V7), read front to back.
enum TarReader {
    /// A valid tar header: its checksum matches and it names something.
    static func isHeader(_ block: Data) -> Bool {
        let b = [UInt8](block)
        guard b.count >= 512, b[0] != 0, let stored = number(b[148..<156]) else { return false }
        return checksum(b) == stored
    }

    static func list(_ reader: BlockReader, format: ArchiveFormat, limits: Archive.Limits, deadline: Date) throws -> ArchiveListing {
        var entries = [ArchiveEntry]()
        var stop: ArchiveListing.Stop?
        var longName: String?, longLink: String?
        var pax = [String: String]()
        // Stepping over one huge entry in a compressed tar can take minutes: honour the deadline
        // inside skips too.
        reader.shouldStop = { Date() > deadline }
        func stopReason(_ error: Error) -> ArchiveListing.Stop { (error as? ArchiveError) == .stopped ? .timeLimit : .damaged }

        while true {
            if Date() > deadline { stop = .timeLimit; break }
            let block: Data
            do { block = try reader.read(512) } catch { stop = stopReason(error); break }
            let b = [UInt8](block)
            if b.count < 512 { if !entries.isEmpty || b.count > 0 { stop = b.isEmpty ? nil : .damaged }; break }
            if b.allSatisfy({ $0 == 0 }) { break } // end of archive
            guard isHeader(block) else {
                if entries.isEmpty { throw ArchiveError.damaged }
                stop = .damaged
                break
            }

            let type = b[156]
            var size = number(b[124..<136]) ?? 0
            if let s = pax["size"].flatMap(Int64.init) { size = s }
            let dataStart = reader.offset
            let padded = (size + 511) / 512 * 512

            // Records that describe the next entry.
            if type == UInt8(ascii: "L") || type == UInt8(ascii: "K") || type == UInt8(ascii: "x") || type == UInt8(ascii: "g") {
                guard size <= 1 << 20 else { stop = .damaged; break }
                let data: Data
                do {
                    data = try reader.read(Int(size))
                    try reader.skip(padded - size)
                } catch { stop = stopReason(error); break }
                switch type {
                case UInt8(ascii: "L"): longName = cString(Array(data))
                case UInt8(ascii: "K"): longLink = cString(Array(data))
                case UInt8(ascii: "x"): pax.merge(paxRecords(data)) { $1 }
                default: break // global pax records: nothing Infiniview shows
                }
                continue
            }

            var name = cString(Array(b[0..<100]))
            if b[257..<263].elementsEqual(Array("ustar\0".utf8)) {
                let prefix = cString(Array(b[345..<500]))
                if !prefix.isEmpty { name = prefix + "/" + name }
            }
            if let n = longName { name = n }
            if let n = pax["path"] { name = n }
            var link = cString(Array(b[157..<257]))
            if let l = longLink { link = l }
            if let l = pax["linkpath"] { link = l }
            var modified = number(b[136..<148]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            if let m = pax["mtime"].flatMap(Double.init) { modified = Date(timeIntervalSince1970: m) }
            let mode = number(b[100..<108]).map { UInt16(truncatingIfNeeded: $0) & 0o7777 }
            longName = nil
            longLink = nil
            pax = [:]

            let kind: ArchiveEntry.Kind = switch type {
            case UInt8(ascii: "5"), UInt8(ascii: "D"): .directory
            case UInt8(ascii: "1"), UInt8(ascii: "2"): .link(target: link)
            default: name.hasSuffix("/") ? .directory : .file
            }
            do { try reader.skip(padded) } catch {
                stop = stopReason(error) // still list the entry being skipped
            }
            let path = name.archivePath
            if !path.isEmpty, !path.isMacMetadataPath, type != UInt8(ascii: "V") {
                var entry = ArchiveEntry(path: path, kind: kind, size: kind == .file ? size : nil,
                                         modified: modified, permissions: mode)
                entry.location = dataStart
                entries.append(entry)
            }
            if stop != nil { break }
            if entries.count >= limits.entries { stop = .entryLimit; break }
        }
        return ArchiveListing(format: format, entries: entries, stoppedEarly: stop)
    }

    // MARK: -

    /// Octal, or GNU base-256 when the top bit of the first byte is set.
    static func number(_ field: ArraySlice<UInt8>) -> Int64? {
        guard let first = field.first else { return nil }
        if first & 0x80 != 0 {
            return field.dropFirst().reduce(Int64(first & 0x7F)) { $0 << 8 | Int64($1) }
        }
        let digits = field.prefix { $0 != 0 }.filter { $0 != 0x20 }
        if digits.isEmpty { return 0 }
        guard digits.allSatisfy({ (0x30...0x37).contains($0) }), digits.count <= 21 else { return nil }
        return digits.reduce(0) { $0 * 8 + Int64($1 - 0x30) }
    }

    /// Sum of the header's bytes with the checksum field counted as spaces.
    private static func checksum(_ b: [UInt8]) -> Int64 {
        var sum: Int64 = 0
        for i in 0..<512 { sum += (148..<156).contains(i) ? 0x20 : Int64(b[i]) }
        return sum
    }

    private static func cString(_ bytes: [UInt8]) -> String {
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// pax records: "<length> <key>=<value>\n".
    private static func paxRecords(_ data: Data) -> [String: String] {
        var out = [String: String]()
        let b = [UInt8](data)
        var i = 0
        while i < b.count {
            guard let space = b[i...].firstIndex(of: 0x20),
                  let length = Int(String(decoding: b[i..<space], as: UTF8.self)), length > 0, i + length <= b.count else { break }
            let record = String(decoding: b[(space + 1)..<(i + length - 1)], as: UTF8.self)
            if let eq = record.firstIndex(of: "=") {
                out[String(record[..<eq])] = String(record[record.index(after: eq)...])
            }
            i += length
        }
        return out
    }
}
