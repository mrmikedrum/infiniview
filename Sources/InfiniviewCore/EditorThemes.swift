import Foundation

/// The theme option that borrows the light/dark themes of a VS Code-family editor installed on
/// this Mac. Everything is discovered at run time: editors are apps that carry VS Code's
/// `Contents/Resources/app/product.json` layout.
public enum EditorThemes {
    public struct Editor: Sendable, Equatable {
        public var name: String
        public var appURL: URL
        /// The user's `settings.json`.
        public var settingsURL: URL
        /// Folders holding extensions: the editor's built-in ones and the user's.
        public var extensionFolders: [URL]
    }

    /// A flattened theme in the bundled themes' shape: `{name, type, colors, settings}`.
    public typealias ThemeJSON = [String: Any]

    // MARK: Finding editors

    public static func editor(at appURL: URL, home: URL) -> Editor? {
        let app = appURL.appendingPathComponent("Contents/Resources/app")
        guard let product = JSONC.object(at: app.appendingPathComponent("product.json")),
              let short = product["nameShort"] as? String, !short.contains("/") else { return nil }
        var folders = [app.appendingPathComponent("extensions")]
        if let data = product["dataFolderName"] as? String, !data.contains("/") {
            folders.append(home.appendingPathComponent(data).appendingPathComponent("extensions"))
        }
        return Editor(name: product["nameLong"] as? String ?? short, appURL: appURL,
                      settingsURL: home.appendingPathComponent("Library/Application Support/\(short)/User/settings.json"),
                      extensionFolders: folders)
    }

    /// Editors among the apps directly inside the given folders.
    public static func findEditors(in folders: [URL], home: URL) -> [Editor] {
        folders.flatMap { folder -> [Editor] in
            let apps = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return apps.filter { $0.pathExtension == "app" }.sorted { $0.path < $1.path }.compactMap { editor(at: $0, home: home) }
        }
    }

    // MARK: Resolving the user's themes

    /// The editor's light and dark themes as the user set them: the preferred light/dark themes
    /// if set, otherwise the current theme for whichever of the two it is. Either can be nil.
    public static func themes(for editor: Editor) -> (light: ThemeJSON?, dark: ThemeJSON?) {
        let settings = JSONC.object(at: editor.settingsURL) ?? [:]
        let catalog = catalog(editor.extensionFolders)
        func load(_ name: String?) -> ThemeJSON? { name.flatMap { n in catalog.first { $0.names.contains(n) } }.flatMap(flatten) }
        let current = load(settings["workbench.colorTheme"] as? String)
        let currentIsDark = (current?["type"] as? String).map { $0 != "light" && $0 != "hcLight" } ?? false
        let light = load(settings["workbench.preferredLightColorTheme"] as? String) ?? (current != nil && !currentIsDark ? current : nil)
        let dark = load(settings["workbench.preferredDarkColorTheme"] as? String) ?? (current != nil && currentIsDark ? current : nil)
        return (light, dark)
    }

    struct Entry { var names: Set<String>; var file: URL; var uiTheme: String }

    /// Every theme the extensions contribute, findable by id or display label.
    static func catalog(_ folders: [URL]) -> [Entry] {
        var entries = [Entry]()
        for folder in folders {
            let dirs = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for dir in dirs.sorted(by: { $0.path < $1.path }) {
                guard let pkg = JSONC.object(at: dir.appendingPathComponent("package.json")),
                      let themes = (pkg["contributes"] as? [String: Any])?["themes"] as? [[String: Any]] else { continue }
                let nls = JSONC.object(at: dir.appendingPathComponent("package.nls.json")) ?? [:]
                for t in themes {
                    guard let path = t["path"] as? String else { continue }
                    var names = Set<String>()
                    if let id = t["id"] as? String { names.insert(id) }
                    if var label = t["label"] as? String {
                        if label.hasPrefix("%") && label.hasSuffix("%"), let s = nls[String(label.dropFirst().dropLast())] as? String { label = s }
                        names.insert(label)
                    }
                    entries.append(Entry(names: names, file: dir.appendingPathComponent(path).standardized, uiTheme: t["uiTheme"] as? String ?? "vs"))
                }
            }
        }
        return entries
    }

    static func flatten(_ entry: Entry) -> ThemeJSON? {
        guard var theme = flatten(file: entry.file, depth: 0) else { return nil }
        if theme["type"] == nil {
            theme["type"] = ["vs": "light", "hc-light": "hcLight", "hc-black": "hcDark"][entry.uiTheme] ?? "dark"
        }
        let colors = theme["colors"] as? [String: Any] ?? [:]
        // The first, scope-less rule sets the default colours, as in the bundled themes.
        var defaults = [String: Any]()
        if let fg = colors["editor.foreground"] { defaults["foreground"] = fg }
        if let bg = colors["editor.background"] { defaults["background"] = bg }
        theme["settings"] = [["settings": defaults]] + (theme["settings"] as? [[String: Any]] ?? [])
        return theme
    }

    /// Follows "include" and file-valued "tokenColors" (JSON or .tmTheme plist).
    static func flatten(file: URL, depth: Int) -> ThemeJSON? {
        guard depth < 8, let t = JSONC.object(at: file) else { return nil }
        let dir = file.deletingLastPathComponent()
        var base: ThemeJSON = ["colors": [String: Any](), "settings": [[String: Any]]()]
        if let include = t["include"] as? String, let parent = flatten(file: dir.appendingPathComponent(include).standardized, depth: depth + 1) {
            base = parent
        }
        var colors = base["colors"] as? [String: Any] ?? [:]
        for (k, v) in t["colors"] as? [String: Any] ?? [:] { colors[k] = v }
        var settings = base["settings"] as? [[String: Any]] ?? []
        if let rules = t["tokenColors"] as? [[String: Any]] {
            settings += rules
        } else if let path = t["tokenColors"] as? String {
            let url = dir.appendingPathComponent(path).standardized
            if url.pathExtension.lowercased() == "tmtheme" {
                let plist = (try? Data(contentsOf: url)).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
                settings += plist?["settings"] as? [[String: Any]] ?? []
            } else if let rules = JSONC.value(at: url) as? [[String: Any]] {
                settings += rules
            } else if let obj = JSONC.object(at: url) {
                settings += obj["tokenColors"] as? [[String: Any]] ?? obj["settings"] as? [[String: Any]] ?? []
            }
        }
        var out = base
        out["colors"] = colors
        out["settings"] = settings
        if let name = t["name"] { out["name"] = name }
        if let type = t["type"] { out["type"] = type }
        return out
    }
}

/// JSON with comments and trailing commas, as VS Code writes it.
public enum JSONC {
    public static func value(_ data: Data) -> Any? {
        let src = String(decoding: data, as: UTF8.self)
        var out = "", inString = false, escaped = false
        var i = src.startIndex
        while i < src.endIndex {
            let c = src[i]
            let next = src.index(after: i)
            if inString {
                out.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                i = next
                continue
            }
            if c == "\"" { inString = true; out.append(c); i = next; continue }
            if c == "/", next < src.endIndex, src[next] == "/" {
                i = src[i...].firstIndex(of: "\n") ?? src.endIndex
                continue
            }
            if c == "/", next < src.endIndex, src[next] == "*" {
                i = src.range(of: "*/", range: next..<src.endIndex)?.upperBound ?? src.endIndex
                continue
            }
            out.append(c)
            i = next
        }
        let cleaned = out.replacingOccurrences(of: #",(\s*[}\]])"#, with: "$1", options: .regularExpression)
        return try? JSONSerialization.jsonObject(with: Data(cleaned.utf8), options: [.fragmentsAllowed])
    }

    public static func value(at url: URL) -> Any? { (try? Data(contentsOf: url)).flatMap(value) }
    public static func object(at url: URL) -> [String: Any]? { value(at: url) as? [String: Any] }
}
