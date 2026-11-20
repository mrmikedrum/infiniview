import CBzip2
import Compression
import Foundation
import zlib

/// A source of bytes read front to back: a file, or the unpacked output of a compressed one.
protocol ByteStream: AnyObject {
    /// Up to `max` bytes; empty only at the end.
    func read(_ max: Int) throws -> Data
    /// Skips up to `count` bytes, returning how many were skipped.
    func skip(_ count: Int64) throws -> Int64
}

extension ByteStream {
    func skip(_ count: Int64) throws -> Int64 {
        var left = count
        while left > 0 {
            let chunk = try read(Int(min(left, 256 * 1024)))
            if chunk.isEmpty { break }
            left -= Int64(chunk.count)
        }
        return count - left
    }
}

/// A file, or part of one.
final class FileStream: ByteStream {
    private let handle: FileHandle
    private var left: Int64

    init(_ url: URL, from offset: Int64 = 0, length: Int64 = .max) throws {
        handle = try FileHandle(forReadingFrom: url)
        if offset > 0 { try handle.seek(toOffset: UInt64(offset)) }
        left = length
    }

    deinit { try? handle.close() }

    func read(_ max: Int) throws -> Data {
        guard left > 0 else { return Data() }
        let data = try handle.read(upToCount: Int(min(Int64(max), left))) ?? Data()
        left -= Int64(data.count)
        return data
    }

    func skip(_ count: Int64) throws -> Int64 {
        let here = try handle.offset()
        let end = try handle.seekToEnd()
        let n = min(count, Int64(end - here), left)
        try handle.seek(toOffset: here + UInt64(n))
        left -= n
        return n
    }
}

/// Exact-length reads over a stream, keeping track of the offset.
final class BlockReader {
    private let stream: ByteStream
    private var buffer = Data()
    private(set) var offset: Int64 = 0
    /// Checked between chunks of long reads and skips; when true they throw `ArchiveError.stopped`.
    /// Skipping through a compressed stream means unpacking it, which for a file deep inside a
    /// huge archive can take minutes.
    var shouldStop: () -> Bool = { false }
    private static let skipChunk: Int64 = 16 * 1024 * 1024

    init(_ stream: ByteStream, shouldStop: @escaping () -> Bool = { false }) {
        self.stream = stream
        self.shouldStop = shouldStop
    }

    /// `count` bytes, or fewer only at the end.
    func read(_ count: Int) throws -> Data {
        while buffer.count < count {
            if shouldStop() { throw ArchiveError.stopped }
            let more = try stream.read(max(count - buffer.count, 64 * 1024))
            if more.isEmpty { break }
            buffer += more
        }
        let out = buffer.prefix(count)
        buffer = Data(buffer.dropFirst(out.count))
        offset += Int64(out.count)
        return Data(out)
    }

    /// Skips `count` bytes; throws if the stream ends first.
    func skip(_ count: Int64) throws {
        let fromBuffer = min(Int64(buffer.count), count)
        buffer = Data(buffer.dropFirst(Int(fromBuffer)))
        offset += fromBuffer
        var rest = count - fromBuffer
        while rest > 0 {
            if shouldStop() { throw ArchiveError.stopped }
            let skipped = try stream.skip(min(rest, Self.skipChunk))
            offset += skipped
            rest -= skipped
            if skipped == 0 { throw ArchiveError.damaged }
        }
    }
}

/// Runs a C decompressor over another stream. Subclasses do one step of the C library's loop.
class CodecStream: ByteStream {
    private let source: ByteStream
    private static let chunk = 64 * 1024
    private let input = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
    private var inStart = 0, inEnd = 0
    private var sourceDone = false, done = false
    /// Set after a stream ends with input left over; anything unreadable after that is ignored.
    private var betweenMembers = false

    init(_ source: ByteStream) { self.source = source }
    deinit { input.deallocate() }

    struct Step { var consumed: Int; var produced: Int; var ended: Bool }

    /// One call into the decompressor.
    func step(_ input: UnsafeMutablePointer<UInt8>, _ inCount: Int, _ output: UnsafeMutablePointer<UInt8>, _ outCount: Int,
              final: Bool) throws -> Step { fatalError("subclass") }
    /// Prepares for another compressed stream following the last one (multi-member gzip and
    /// bzip2); false if the format has none.
    func restart() throws -> Bool { false }

    func read(_ max: Int) throws -> Data {
        guard !done, max > 0 else { return Data() }
        var out = [UInt8](repeating: 0, count: max)
        var produced = 0
        while produced == 0 && !done {
            if inStart == inEnd && !sourceDone {
                let data = try source.read(Self.chunk)
                if data.isEmpty { sourceDone = true } else {
                    data.copyBytes(to: input, count: data.count)
                    inStart = 0
                    inEnd = data.count
                }
            }
            if betweenMembers && inStart == inEnd && sourceDone { done = true; break }
            let r: Step
            do {
                r = try out.withUnsafeMutableBufferPointer { o in
                    try step(input + inStart, inEnd - inStart, o.baseAddress! + produced, max - produced, final: sourceDone)
                }
            } catch where betweenMembers {
                done = true // trailing padding or junk after the last member
                break
            }
            inStart += r.consumed
            produced += r.produced
            if r.produced > 0 { betweenMembers = false }
            if r.ended {
                if (inStart < inEnd || !sourceDone), try restart() { betweenMembers = true } else { done = true }
            } else if r.consumed == 0 && r.produced == 0 && (inStart < inEnd || sourceDone) {
                throw ArchiveError.damaged // stuck, or the input ends mid-stream
            }
        }
        return Data(out[0..<produced])
    }
}

/// gzip (and the raw deflate inside zip entries), through zlib.
final class InflateStream: CodecStream {
    private var z = z_stream()
    private let gzip: Bool

    init(_ source: ByteStream, gzip: Bool) throws {
        self.gzip = gzip
        super.init(source)
        guard inflateInit2_(&z, gzip ? 15 + 16 : -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ArchiveError.damaged
        }
    }

    deinit { inflateEnd(&z) }

    override func step(_ input: UnsafeMutablePointer<UInt8>, _ inCount: Int, _ output: UnsafeMutablePointer<UInt8>,
                       _ outCount: Int, final: Bool) throws -> Step {
        z.next_in = input
        z.avail_in = UInt32(inCount)
        z.next_out = output
        z.avail_out = UInt32(outCount)
        let status = inflate(&z, Z_NO_FLUSH)
        let step = Step(consumed: inCount - Int(z.avail_in), produced: outCount - Int(z.avail_out), ended: status == Z_STREAM_END)
        guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else { throw ArchiveError.damaged }
        return step
    }

    override func restart() throws -> Bool { gzip && inflateReset(&z) == Z_OK }
}

final class Bzip2Stream: CodecStream {
    private var bz = bz_stream()

    init(source: ByteStream) throws {
        super.init(source)
        guard BZ2_bzDecompressInit(&bz, 0, 0) == BZ_OK else { throw ArchiveError.damaged }
    }

    deinit { BZ2_bzDecompressEnd(&bz) }

    override func step(_ input: UnsafeMutablePointer<UInt8>, _ inCount: Int, _ output: UnsafeMutablePointer<UInt8>,
                       _ outCount: Int, final: Bool) throws -> Step {
        bz.next_in = UnsafeMutableRawPointer(input).assumingMemoryBound(to: CChar.self)
        bz.avail_in = UInt32(inCount)
        bz.next_out = UnsafeMutableRawPointer(output).assumingMemoryBound(to: CChar.self)
        bz.avail_out = UInt32(outCount)
        let status = BZ2_bzDecompress(&bz)
        guard status == BZ_OK || status == BZ_STREAM_END else { throw ArchiveError.damaged }
        return Step(consumed: inCount - Int(bz.avail_in), produced: outCount - Int(bz.avail_out), ended: status == BZ_STREAM_END)
    }

    override func restart() throws -> Bool {
        BZ2_bzDecompressEnd(&bz)
        return BZ2_bzDecompressInit(&bz, 0, 0) == BZ_OK
    }
}

/// xz, through the Compression framework (its LZMA decoder reads the xz format).
final class XZStream: CodecStream {
    private let s = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
    private var started = false

    init(source: ByteStream) throws {
        super.init(source)
        guard compression_stream_init(s, COMPRESSION_STREAM_DECODE, COMPRESSION_LZMA) == COMPRESSION_STATUS_OK else {
            throw ArchiveError.damaged
        }
        started = true
    }

    deinit {
        if started { compression_stream_destroy(s) }
        s.deallocate()
    }

    override func step(_ input: UnsafeMutablePointer<UInt8>, _ inCount: Int, _ output: UnsafeMutablePointer<UInt8>,
                       _ outCount: Int, final: Bool) throws -> Step {
        s.pointee.src_ptr = UnsafePointer(input)
        s.pointee.src_size = inCount
        s.pointee.dst_ptr = output
        s.pointee.dst_size = outCount
        let status = compression_stream_process(s, final ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
        guard status != COMPRESSION_STATUS_ERROR else { throw ArchiveError.damaged }
        return Step(consumed: inCount - s.pointee.src_size, produced: outCount - s.pointee.dst_size,
                    ended: status == COMPRESSION_STATUS_END)
    }
}
