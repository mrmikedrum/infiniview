import Foundation
import Testing
@testable import InfiniviewCore

@Suite struct FolderCheckTests {
    /// A fresh folder with the given files (name → contents).
    private func folder(_ files: [String: Data]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FolderCheck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: dir.appendingPathComponent(name)) }
        return dir
    }

    private func text(_ s: String) -> Data { Data(s.utf8) }

    @Test func learnsTextExtensionsOnly() throws {
        let dir = try folder([
            "notes.qqtext": text("plain words\n"),
            "settings.qqcfg": text("key = value\n"),
            "blob.qqbin": Data([0x7F, 0x45, 0x4C, 0x46, 0, 0, 1, 2, 3]),
            "doc.qqrtf": text(#"{\rtf1\ansi hello}"#),
            "noext": text("no extension\n"),
        ])
        let found = FolderCheck.textExtensions(in: dir) { _ in true }
        #expect(Set(found) == ["qqtext", "qqcfg", "qqrtf"])
    }

    @Test func asksAboutEachExtensionOnce() throws {
        let dir = try folder(["a.qqone": text("a"), "b.qqone": text("b"), "c.QQONE": text("c"), "d.qqtwo": text("d")])
        var asked = [String]()
        _ = FolderCheck.textExtensions(in: dir) { asked.append($0); return $0 != "qqtwo" }
        #expect(asked.sorted() == ["qqone", "qqtwo"])
    }

    @Test func skipsRejectedCandidates() throws {
        let dir = try folder(["a.md": text("# hi"), "b.qqnew": text("hi")])
        #expect(FolderCheck.textExtensions(in: dir) { $0 != "md" } == ["qqnew"])
    }

    @Test func emptyFilesDontDecide() throws {
        let dir = try folder(["empty.qqlog": Data(), "full.qqlog": text("line\n"), "only-empty.qqnil": Data()])
        #expect(FolderCheck.textExtensions(in: dir) { _ in true } == ["qqlog"])
    }

    @Test func ignoresSubfolders() throws {
        let dir = try folder([:])
        let sub = dir.appendingPathComponent("inner.qqdir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try text("x").write(to: sub.appendingPathComponent("deep.qqdeep"))
        #expect(FolderCheck.textExtensions(in: dir) { _ in true }.isEmpty)
    }

    @Test func missingFolderFindsNothing() {
        let gone = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(FolderCheck.textExtensions(in: gone) { _ in true }.isEmpty)
    }
}

@Suite struct AutomaticLearningTests {
    @Test func learnsNewExtensions() {
        var learned = LearnedExtensions(builtIn: ["conf"])
        let first = learned.learnAutomatically("qqx")
        let again = learned.learnAutomatically("qqx")
        let builtIn = learned.learnAutomatically("conf")
        #expect(first && !again && !builtIn)
        #expect(learned.effective == ["conf", "qqx"])
    }

    @Test func neverRelearnsWhatTheUserRemoved() {
        var learned = LearnedExtensions(builtIn: ["conf"])
        learned.learn("qqx")
        learned.forget("qqx")
        learned.forget("conf")
        let added = learned.learnAutomatically("qqx")
        let builtIn = learned.learnAutomatically("conf")
        #expect(!added && !builtIn && learned.effective.isEmpty)
        learned.learn("qqx")
        #expect(learned.effective == ["qqx"] && learned.dismissed.isEmpty)
    }

    @Test func dismissedSurvivesSaving() throws {
        let defaults = try #require(UserDefaults(suiteName: "infiniview-tests-\(UUID().uuidString)"))
        let settings = SharedSettings(defaults: defaults)
        var learned = LearnedExtensions(builtIn: [])
        learned.learn("qqx")
        learned.forget("qqx")
        settings.save(learned)
        #expect(settings.learnedExtensions(builtIn: []).isDismissed("qqx"))
    }
}
