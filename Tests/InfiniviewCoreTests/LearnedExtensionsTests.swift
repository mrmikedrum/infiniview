import Foundation
import Testing
@testable import InfiniviewCore

@Suite struct LearnedExtensionsTests {
    @Test func parsesTheListFormat() {
        let text = """
        # comment
        conf     Configuration file
          .TOML  TOML

        jsonl
        conf     duplicate
        bad/ext  rejected
        """
        #expect(ExtensionList.parse(text) == ["conf", "toml", "jsonl"])
    }

    @Test func builtInListParsesAndIsClean() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/builtin-extensions.txt").standardized
        let list = ExtensionList.parse(try String(contentsOf: url, encoding: .utf8))
        #expect(list.count > 100)
        #expect(list.contains("toml"))
        #expect(!list.contains("ts"))
        #expect(Set(list).count == list.count)
        #expect(list.allSatisfy { ExtensionList.normalize($0) == $0 })
    }

    @Test func normalizes() {
        #expect(ExtensionList.normalize(".XYZ") == "xyz")
        #expect(ExtensionList.normalize("  conf ") == "conf")
        #expect(ExtensionList.normalize("code-workspace") == "code-workspace")
        #expect(ExtensionList.normalize("c++") == "c++")
        #expect(ExtensionList.normalize("") == nil)
        #expect(ExtensionList.normalize("a.b") == nil) // only the last part of a name is an extension
        #expect(ExtensionList.normalize("a b") == nil)
        #expect(ExtensionList.normalize(String(repeating: "x", count: 65)) == nil)
    }

    @Test func effectiveListIsBuiltInPlusAddedMinusRemoved() {
        var learned = LearnedExtensions(builtIn: ["conf", "toml"])
        learned.learn("xyz")
        learned.forget("toml")
        #expect(learned.effective == ["conf", "xyz"])
        #expect(learned.isLearned("XYZ"))
        #expect(!learned.isLearned("toml"))
    }

    @Test func learningARemovedBuiltInRestoresIt() {
        var learned = LearnedExtensions(builtIn: ["toml"])
        learned.forget("toml")
        learned.learn(".TOML")
        #expect(learned.effective == ["toml"])
        #expect(learned.removed.isEmpty && learned.added.isEmpty)
    }

    @Test func forgettingAnAddedExtensionDropsIt() {
        var learned = LearnedExtensions(builtIn: [])
        learned.learn("xyz")
        learned.forget("xyz")
        #expect(learned.effective.isEmpty && learned.removed.isEmpty)
    }

    @Test func helperDeclaresOneTypeWithTheExtensions() throws {
        let plist = LearnedTypeHelper.infoPlist(extensions: ["conf", "xyz"], version: "42")
        #expect(plist["CFBundleIdentifier"] as? String == LearnedTypeHelper.bundleIdentifier)
        #expect(plist["CFBundleVersion"] as? String == "42")
        let decls = try #require(plist["UTExportedTypeDeclarations"] as? [[String: Any]])
        #expect(decls.count == 1)
        #expect(decls[0]["UTTypeIdentifier"] as? String == LearnedTypeHelper.typeIdentifier)
        #expect(decls[0]["UTTypeConformsTo"] as? [String] == ["public.plain-text"])
        let tags = try #require(decls[0]["UTTypeTagSpecification"] as? [String: [String]])
        #expect(tags["public.filename-extension"] == ["conf", "xyz"])
        // The plist must serialize.
        _ = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
