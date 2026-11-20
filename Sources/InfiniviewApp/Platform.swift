import AppKit
import CoreServices
import InfiniviewCore
import UniformTypeIdentifiers

/// Writes the Learned Type helper bundle and registers it with Launch Services (ADR-0001).
enum LearnedTypeRegistrar {
    static var helperURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Infiniview/\(LearnedTypeHelper.bundleName)")
    }

    /// Rewrites the declaration with these extensions and re-registers it. Takes effect for the
    /// next preview; nothing is rebuilt or re-signed.
    @discardableResult
    static func apply(_ extensions: [String]) -> Bool {
        let contents = helperURL.appendingPathComponent("Contents")
        do {
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let version = String(Int(Date().timeIntervalSince1970 * 1000))
            let plist = LearnedTypeHelper.infoPlist(extensions: extensions, version: version)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        } catch {
            NSLog("Infiniview: couldn't write the Learned Type helper: \(error)")
            return false
        }
        let status = LSRegisterURL(helperURL as CFURL, true)
        if status != noErr { NSLog("Infiniview: LSRegisterURL failed: \(status)") }
        return status == noErr
    }

    /// What macOS currently calls files with this extension, if it isn't Infiniview or unknown.
    static func otherOwner(of ext: String) -> String? {
        guard let type = UTType(filenameExtension: ext), !type.isDynamic,
              type.identifier != LearnedTypeHelper.typeIdentifier else { return nil }
        return type.localizedDescription ?? type.identifier
    }
}

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

/// The built-in Learned Extensions, shipped in the app's resources.
enum BuiltInList {
    static let extensions: [String] = {
        guard let url = Bundle.main.url(forResource: "builtin-extensions", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return ExtensionList.parse(text)
    }()
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
