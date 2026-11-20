import AppKit
import InfiniviewCore
import InfiniviewSystem
import UniformTypeIdentifiers

/// Switches the Takeover extension with pluginkit.
enum TakeoverSwitch {
    static func isOn() -> Bool? { Takeover.isOn(pluginkitOutput: run(["-m", "-i", Takeover.extensionIdentifier])) }

    static func set(_ on: Bool) { _ = run(Takeover.arguments(on: on)) }

    private static func run(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: out, as: UTF8.self)
    }
}

/// Finds VS Code-family editors and copies their resolved themes into shared settings.
enum EditorThemeStore {
    static func editors() -> [EditorThemes.Editor] {
        let fm = FileManager.default
        let folders = fm.urls(for: .applicationDirectory, in: .localDomainMask) + fm.urls(for: .applicationDirectory, in: .userDomainMask)
        return EditorThemes.findEditors(in: folders, home: fm.homeDirectoryForCurrentUser)
    }

    /// Uses the editor's themes, or the bundled pair when `editor` is nil.
    static func use(_ editor: EditorThemes.Editor?, settings: SharedSettings = SharedSettings()) {
        guard let editor else {
            settings.themeSource = .bundled
            return
        }
        let (light, dark) = EditorThemes.themes(for: editor)
        func json(_ t: EditorThemes.ThemeJSON?) -> String? {
            t.flatMap { try? JSONSerialization.data(withJSONObject: $0) }.map { String(decoding: $0, as: UTF8.self) }
        }
        settings.editorName = editor.name
        settings.editorThemeLight = json(light)
        settings.editorThemeDark = json(dark)
        settings.themeSource = .editor
    }

    /// Picks up changes made in the editor since the themes were last copied.
    static func refresh(settings: SharedSettings = SharedSettings()) {
        guard settings.themeSource == .editor, let name = settings.editorName,
              let editor = editors().first(where: { $0.name == name }) else { return }
        use(editor, settings: settings)
    }
}
