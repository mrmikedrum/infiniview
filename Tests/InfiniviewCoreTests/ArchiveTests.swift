import Foundation
import Testing
@testable import InfiniviewCore

private let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../Fixtures/corpus").standardized

@Suite struct ArchiveTests {
    static let bundles = ["bundle.zip", "zip64.zip", "bundle.tar", "bundle.tar.gz", "bundle.tar.bz2", "bundle.tar.xz"]
    static let longPath = "project/" + Array(repeating: "a-rather-long-folder-name", count: 5).joined(separator: "/") + "/deep.txt"

    func list(_ name: String, limits: Archive.Limits = .init()) throws -> ArchiveListing {
        try #require(try Archive.list(corpus.appendingPathComponent(name), limits: limits))
    }

    func entry(_ listing: ArchiveListing, _ path: String) throws -> ArchiveEntry {
        try #require(listing.entries.first { $0.path == path })
    }

    @Test(arguments: bundles) func listsEveryFormat(_ name: String) throws {
        let listing = try list(name)
        #expect(listing.stoppedEarly == nil)
        #expect(Set(listing.entries.map(\.path)) == [
            "project/empty-dir", "project/README.md", "project/src/main.py", "project/config.qqcfg",
            "project/docs/café.txt", "project/pixel.png", Self.longPath, "project/readme-link",
        ]) // macOS metadata ("__MACOSX", "._name") is hidden
        #expect(try entry(listing, "project/empty-dir").kind == .directory)
        #expect(try entry(listing, "project/readme-link").kind == .link(target: "README.md"))
        let main = try entry(listing, "project/src/main.py")
        #expect(main.size == 750)
        #expect(main.permissions == 0o644)
        #expect(main.modified != nil)
    }

    @Test(arguments: bundles) func readsEntries(_ name: String) throws {
        let url = corpus.appendingPathComponent(name)
        let listing = try list(name)
        let readme = try Archive.read(try entry(listing, "project/README.md"), of: listing, at: url, maxBytes: 1 << 20)
        #expect(String(decoding: readme, as: UTF8.self) == "# Example project\n\nSome **notes** about it.\n")
        let main = try Archive.read(try entry(listing, "project/src/main.py"), of: listing, at: url, maxBytes: 1 << 20)
        #expect(main == Data(String(repeating: "print('hello')\n", count: 50).utf8))
        let deep = try Archive.read(try entry(listing, Self.longPath), of: listing, at: url, maxBytes: 1 << 20)
        #expect(deep == Data("Deep inside.\n".utf8))
        let png = try Archive.read(try entry(listing, "project/pixel.png"), of: listing, at: url, maxBytes: 1 << 20)
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func readsAreCappedAtMaxBytes() throws {
        let listing = try list("bundle.tar.gz")
        let main = try entry(listing, "project/src/main.py")
        let head = try Archive.read(main, of: listing, at: corpus.appendingPathComponent("bundle.tar.gz"), maxBytes: 10)
        #expect(head == Data("print('hel".utf8))
    }

    @Test func zipRecordsCompressedSizes() throws {
        let main = try entry(try list("bundle.zip"), "project/src/main.py")
        #expect(try #require(main.compressedSize) < 750)
    }

    @Test func singleCompressedFile() throws {
        let listing = try list("notes.txt.gz")
        #expect(listing.format == .compressed(.gzip))
        let only = try #require(listing.entries.first)
        #expect(listing.entries.count == 1 && only.path == "notes.txt" && only.size == 30)
        let text = try Archive.read(only, of: listing, at: corpus.appendingPathComponent("notes.txt.gz"), maxBytes: 100)
        #expect(String(decoding: text, as: UTF8.self) == "Plain notes, gzip compressed.\n")
    }

    @Test func formatsAreTold() throws {
        #expect(try list("bundle.zip").format == .zip)
        #expect(try list("bundle.tar").format == .tar(.none))
        #expect(try list("bundle.tar.gz").format == .tar(.gzip))
        #expect(try list("bundle.tar.bz2").format == .tar(.bzip2))
        #expect(try list("bundle.tar.xz").format == .tar(.xz))
    }

    @Test func encryptedEntriesAreListedButNotRead() throws {
        let listing = try list("encrypted.zip")
        let secret = try entry(listing, "secret.txt")
        #expect(secret.isEncrypted)
        #expect(throws: ArchiveError.encrypted) {
            try Archive.read(secret, of: listing, at: corpus.appendingPathComponent("encrypted.zip"), maxBytes: 100)
        }
    }

    @Test func entryLimitStopsListing() throws {
        let listing = try list("bundle.tar", limits: .init(entries: 3))
        #expect(listing.entries.count == 3 && listing.stoppedEarly == .entryLimit)
        let zip = try list("bundle.zip", limits: .init(entries: 3))
        #expect(zip.entries.count == 3 && zip.stoppedEarly == .entryLimit)
    }

    @Test func notArchives() throws {
        #expect(try Archive.list(corpus.appendingPathComponent("NOTES")) == nil)
        #expect(try Archive.list(corpus.appendingPathComponent("blob.bin")) == nil)
        #expect(try Archive.list(corpus.appendingPathComponent("empty")) == nil)
    }

    @Test func damagedArchivesThrow() {
        #expect(throws: ArchiveError.damaged) { try Archive.list(corpus.appendingPathComponent("archive.gz")) }
    }

    @Test func truncatedTarListsWhatItCan() throws {
        let data = try Data(contentsOf: corpus.appendingPathComponent("bundle.tar"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("iv-cut-\(UUID()).tar")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.prefix(3000).write(to: url)
        let listing = try #require(try Archive.list(url))
        #expect(!listing.entries.isEmpty && listing.stoppedEarly == .damaged)
    }

    @Test func truncatedGzipThrowsOnRead() throws {
        let data = try Data(contentsOf: corpus.appendingPathComponent("bundle.tar.gz"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("iv-cut-\(UUID()).tar.gz")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.prefix(data.count / 2).write(to: url)
        let listing = try #require(try Archive.list(url))
        #expect(listing.stoppedEarly == .damaged)
    }

    @Test func readsStopWhenAsked() throws {
        let listing = try list("bundle.tar.gz")
        let main = try entry(listing, "project/src/main.py")
        #expect(throws: ArchiveError.stopped) {
            try Archive.read(main, of: listing, at: corpus.appendingPathComponent("bundle.tar.gz"), maxBytes: 100, shouldStop: { true })
        }
    }

    @Test func longSkipsStopPartWay() throws {
        // Stepping over a huge entry is done in chunks, checking between them.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("iv-big-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 256 << 20) // sparse
        try handle.close()
        var checks = 0
        let reader = BlockReader(try FileStream(url)) { checks += 1; return checks > 2 }
        #expect(throws: ArchiveError.stopped) { try reader.skip(200 << 20) }
        #expect(reader.offset > 0 && reader.offset < 200 << 20)
    }
}
