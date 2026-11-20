import Foundation

/// Where each line starts, in UTF-16 offsets, for line numbers and line-based limits.
public struct LineIndex: Sendable {
    /// UTF-16 offset of the start of each line; the first is 0.
    public let starts: [Int]
    public let length: Int

    public init(_ text: String) {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 0x0A { starts.append(offset) }
        }
        // A final newline ends the last line rather than starting an empty one.
        if starts.count > 1 && starts.last == offset { starts.removeLast() }
        self.starts = starts
        length = offset
    }

    public var count: Int { starts.count }

    /// 1-based line number containing the UTF-16 offset.
    public func line(at offset: Int) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    public func start(ofLine line: Int) -> Int { starts[max(0, min(line - 1, starts.count - 1))] }

    /// UTF-16 offset just after the first `lines` lines (or the end of the text).
    public func utf16Offset(afterLines lines: Int) -> Int {
        lines < starts.count ? starts[lines] : length
    }
}
