import Foundation
import Testing
@testable import InfiniviewCore

/// Builds a made-up VS Code-family editor and home folder in a temporary directory.
struct FakeEditor {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("iv-editor-\(UUID())")
    var home: URL { root.appendingPathComponent("home") }
    var apps: URL { root.appendingPathComponent("Apps") }
    var app: URL { apps.appendingPathComponent("Example Editor.app") }

    func write(_ path: URL, _ text: String) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: path, atomically: true, encoding: .utf8)
    }

    init(settings: String) throws {
        let res = app.appendingPathComponent("Contents/Resources/app")
        try write(res.appendingPathComponent("product.json"), ##"{"nameShort": "ExampleEdit", "nameLong": "Example Editor", "dataFolderName": ".example-edit"}"##)
        let themes = res.appendingPathComponent("extensions/theme-defaults")
        try write(themes.appendingPathComponent("package.json"), """
        { "contributes": { "themes": [
          { "id": "Base Light", "label": "%light%", "uiTheme": "vs", "path": "./themes/light.json" },
          { "id": "Base Dark", "label": "Base Dark", "uiTheme": "vs-dark", "path": "./themes/dark.json" }
        ] } }
        """)
        try write(themes.appendingPathComponent("package.nls.json"), ##"{"light": "Base Light Label"}"##)
        try write(themes.appendingPathComponent("themes/base.json"), """
        { // comment
          "colors": { "editor.background": "#ffffff", "editor.foreground": "#000000", },
          "tokenColors": [ { "scope": "comment", "settings": { "foreground": "#008000" } } ]
        }
        """)
        try write(themes.appendingPathComponent("themes/light.json"), ##"{"name": "Base Light", "include": "./base.json", "tokenColors": [{"scope": "string", "settings": {"foreground": "#a31515"}}]}"##)
        try write(themes.appendingPathComponent("themes/dark.json"), ##"{"name": "Base Dark", "type": "dark", "colors": {"editor.background": "#1e1e1e", "editor.foreground": "#d4d4d4"}, "tokenColors": "./dark-tokens.json"}"##)
        try write(themes.appendingPathComponent("themes/dark-tokens.json"), ##"[{"scope": "keyword", "settings": {"foreground": "#569cd6"}}]"##)
        // A user-installed theme extension.
        let user = home.appendingPathComponent(".example-edit/extensions/someone.night-theme-1.0.0")
        try write(user.appendingPathComponent("package.json"), ##"{"contributes": {"themes": [{"label": "Night", "uiTheme": "vs-dark", "path": "./night.json"}]}}"##)
        try write(user.appendingPathComponent("night.json"), ##"{"name": "Night", "colors": {"editor.background": "#000010"}, "tokenColors": []}"##)
        try write(home.appendingPathComponent("Library/Application Support/ExampleEdit/User/settings.json"), settings)
        try FileManager.default.createDirectory(at: apps.appendingPathComponent("Not An Editor.app"), withIntermediateDirectories: true)
    }

    func editor() throws -> EditorThemes.Editor {
        let found = EditorThemes.findEditors(in: [apps], home: home)
        #expect(found.count == 1)
        return try #require(found.first)
    }
}

@Suite struct EditorThemesTests {
    @Test func findsTheEditorAndItsFolders() throws {
        let fake = try FakeEditor(settings: "{}")
        defer { try? FileManager.default.removeItem(at: fake.root) }
        let editor = try fake.editor()
        #expect(editor.name == "Example Editor")
        #expect(editor.settingsURL.path.hasSuffix("Application Support/ExampleEdit/User/settings.json"))
    }

    @Test func usesPreferredLightAndDarkThemes() throws {
        let fake = try FakeEditor(settings: """
        { "workbench.preferredLightColorTheme": "Base Light Label", // by label
          "workbench.preferredDarkColorTheme": "Night", }
        """)
        defer { try? FileManager.default.removeItem(at: fake.root) }
        let (light, dark) = EditorThemes.themes(for: try fake.editor())
        let l = try #require(light), d = try #require(dark)
        #expect(l["name"] as? String == "Base Light")
        #expect(l["type"] as? String == "light") // from uiTheme
        #expect((l["colors"] as? [String: String])?["editor.background"] == "#ffffff") // from the include
        let rules = try #require(l["settings"] as? [[String: Any]])
        #expect(rules.count == 3) // defaults + included comment rule + own string rule
        #expect((rules[0]["settings"] as? [String: String])?["foreground"] == "#000000")
        #expect(d["name"] as? String == "Night")
    }

    @Test func fallsBackToTheCurrentThemeForItsKind() throws {
        let fake = try FakeEditor(settings: ##"{"workbench.colorTheme": "Base Dark"}"##)
        defer { try? FileManager.default.removeItem(at: fake.root) }
        let (light, dark) = EditorThemes.themes(for: try fake.editor())
        #expect(light == nil)
        let d = try #require(dark)
        #expect((d["settings"] as? [[String: Any]])?.count == 2) // defaults + keyword rule from file
    }

    @Test func parsesJSONWithCommentsAndTrailingCommas() {
        let v = JSONC.value(Data(##"{"a": "// not a comment", /* gone */ "b": [1, 2,], }"##.utf8)) as? [String: Any]
        #expect(v?["a"] as? String == "// not a comment")
        #expect((v?["b"] as? [Int]) == [1, 2])
    }
}
