import Foundation

/// How a Text File's bytes are encoded.
public enum TextEncoding: String, Sendable, Equatable {
    case utf8, utf8BOM, utf16LE, utf16BE, latin1
}

/// What Infiniview decided a file is, from the start of its bytes.
public enum Classification: Sendable, Equatable {
    case rtf
    case text(TextEncoding)
    case binary

    /// Short form used in the fixture manifest (`text:utf8`, `rtf`, `binary`).
    public var label: String {
        switch self {
        case .rtf: "rtf"
        case .binary: "binary"
        case .text(let e): "text:\(e.rawValue)"
        }
    }
}

/// Decides whether a file is RTF, a Text File, or something else (Fallback Card), by content alone.
public enum Classifier {
    /// Bytes read from the start of the file to decide.
    public static let sampleSize = 32 * 1024
    /// Most control characters a Text File's sample may have, as a share of its characters.
    public static let maxControlRatio = 0.01

    public static func classify(fileAt url: URL) throws -> Classification {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let sample = try handle.read(upToCount: sampleSize) ?? Data()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? sample.count
        return classify(sample: sample, isTruncated: size > sample.count)
    }

    /// - Parameter isTruncated: the sample is shorter than the file, so its last character may be cut.
    public static func classify(sample: Data, isTruncated: Bool) -> Classification {
        let bytes = [UInt8](sample)
        if bytes.starts(with: Array(#"{\rtf"#.utf8)) { return .rtf }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return looksLikeText(String(decoding: bytes.dropFirst(3), as: UTF8.self).unicodeScalars) ? .text(.utf8BOM) : .binary
        }
        if bytes.starts(with: [0xFF, 0xFE]) && !bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return utf16(bytes, little: true)
        }
        if bytes.starts(with: [0xFE, 0xFF]) { return utf16(bytes, little: false) }
        if bytes.contains(0) { return .binary }
        if let text = validUTF8(bytes, allowCutEnding: isTruncated) {
            return looksLikeText(text.unicodeScalars) ? .text(.utf8) : .binary
        }
        let latin1 = bytes.lazy.map { Unicode.Scalar($0) }
        return looksLikeText(latin1) ? .text(.latin1) : .binary
    }

    /// Decodes a whole file. Bytes that don't decode become U+FFFD rather than failing.
    public static func decode(_ data: Data, as encoding: TextEncoding) -> String {
        switch encoding {
        case .utf8: return String(decoding: data, as: UTF8.self)
        case .utf8BOM: return String(decoding: data.dropFirst(3), as: UTF8.self)
        case .latin1: return String(data.map { Character(Unicode.Scalar($0)) })
        case .utf16LE, .utf16BE:
            let body = data.dropFirst(2)
            var units = [UInt16]()
            units.reserveCapacity(body.count / 2)
            var i = body.startIndex
            while i + 1 < body.endIndex {
                let a = UInt16(body[i]), b = UInt16(body[i + 1])
                units.append(encoding == .utf16LE ? a | b << 8 : a << 8 | b)
                i += 2
            }
            return String(decoding: units, as: UTF16.self)
        }
    }

    private static func utf16(_ bytes: [UInt8], little: Bool) -> Classification {
        let text = decode(Data(bytes), as: little ? .utf16LE : .utf16BE)
        return looksLikeText(text.unicodeScalars) ? .text(little ? .utf16LE : .utf16BE) : .binary
    }

    private static func validUTF8(_ bytes: [UInt8], allowCutEnding: Bool) -> String? {
        if let s = String(validating: bytes, as: UTF8.self) { return s }
        guard allowCutEnding else { return nil }
        // A sample can end inside a multi-byte character: drop up to 3 trailing bytes and retry.
        for cut in 1...3 where bytes.count > cut {
            if let s = String(validating: bytes.dropLast(cut), as: UTF8.self) { return s }
        }
        return nil
    }

    /// Almost no control characters. Tab, newline, carriage return, vertical tab, form feed,
    /// backspace and escape (terminal colours) are normal in text files.
    private static func looksLikeText<S: Sequence>(_ scalars: S) -> Bool where S.Element == Unicode.Scalar {
        var total = 0, control = 0
        for s in scalars {
            total += 1
            let v = s.value
            if v == 0 { return false }
            if (v < 0x20 && ![0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1B].contains(v)) || v == 0x7F { control += 1 }
        }
        return total == 0 || Double(control) / Double(total) <= maxControlRatio
    }
}
