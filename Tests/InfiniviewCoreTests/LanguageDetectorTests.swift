import Foundation
import Testing
@testable import InfiniviewCore

@Suite struct LanguageDetectorTests {
    static let vendored: LanguageIndex = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Vendor/highlighting/languages.json").standardized
        return try! LanguageIndex(json: Data(contentsOf: url))
    }()

    func id(_ name: String, _ text: String = "") -> String? {
        Self.vendored.detect(fileName: name, text: text)?.id
    }

    @Test func byExtension() {
        #expect(id("main.py") == "python")
        #expect(id("App.SWIFT") == "swift") // case-insensitive
        #expect(id("config.yml") == "yaml")
    }

    @Test func longestSuffixWins() {
        let index = LanguageIndex(languages: [
            .init(id: "map", scopeName: "s.map", extensions: ["map"]),
            .init(id: "jsmap", scopeName: "s.jsmap", extensions: ["js.map"]),
        ])
        #expect(index.detect(fileName: "bundle.js.map", text: "")?.id == "jsmap")
        #expect(index.detect(fileName: "other.map", text: "")?.id == "map")
    }

    @Test func dotfilesMatchTheirWholeName() {
        #expect(id(".gitignore") == "ignore")
        #expect(id(".bashrc") == "shellscript")
        #expect(id(".editorconfig") == "properties")
    }

    @Test func wellKnownFileNames() {
        #expect(id("Dockerfile") == "dockerfile")
        #expect(id("Makefile") == "makefile")
        #expect(id("Gemfile") == "ruby") // listed in lower case upstream
        #expect(id(".env") == "dotenv")
    }

    @Test func fileNamePatterns() {
        #expect(id("Dockerfile.dev") == "dockerfile")
        #expect(id(".env.local") == "dotenv")
    }

    @Test func shebangs() {
        #expect(id("tool", "#!/usr/bin/env python3\nprint(1)\n") == "python")
        #expect(id("run", "#!/bin/sh\necho hi\n") == "shellscript")
        #expect(id("serve", "#!/usr/bin/env node\nconsole.log(1)\n") == "javascript")
        #expect(id("task", "#!/usr/bin/env -S ruby -w\nputs 1\n") == "ruby")
        #expect(id("x", "#!/usr/local/bin/zsh -f\n") == "shellscript")
    }

    @Test func xmlProlog() {
        #expect(id("feed", "<?xml version=\"1.0\"?>\n<a/>") == "xml")
    }

    @Test func validJSON() {
        #expect(id("settings", "  {\"a\": [1, 2]}\n") == "json")
        #expect(id("list", "[1, 2, 3]") == "json")
        #expect(id("almost", "{ not json") == nil)
    }

    @Test func noLanguage() {
        #expect(id("NOTES", "Just some words.\n") == nil)
        #expect(id("data.zqx", "key = value\n") == nil)
    }

    @Test func nameBeatsContent() {
        #expect(id("script.rb", "#!/usr/bin/env python3\n") == "ruby")
    }
}
