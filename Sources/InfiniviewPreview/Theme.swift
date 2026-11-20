import AppKit
import InfiniviewCore

/// A VS Code colour theme, already flattened (no "include"), in the shape vscode-textmate takes:
/// `{ name, type, colors: {...}, settings: [...] }`.
public final class Theme: @unchecked Sendable {
    public let key: String
    public let raw: [String: Any]
    public let isDark: Bool
    public let background: NSColor
    public let foreground: NSColor
    public let lineNumber: NSColor
    public let selection: NSColor
    /// Filled in by the Highlighter when the theme is set.
    var colorMap: [String] = []
    private var colors: [Int: NSColor] = [:]

    public init(json: Data, key: String) throws {
        guard let raw = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        self.key = key
        self.raw = raw
        let c = raw["colors"] as? [String: String] ?? [:]
        isDark = (raw["type"] as? String)?.contains("dark") ?? false
        background = NSColor(hex: c["editor.background"]) ?? (isDark ? NSColor(white: 0.12, alpha: 1) : .white)
        foreground = NSColor(hex: c["editor.foreground"]) ?? (isDark ? NSColor(white: 0.85, alpha: 1) : .black)
        lineNumber = NSColor(hex: c["editorLineNumber.foreground"]) ?? foreground.withAlphaComponent(0.5)
        selection = NSColor(hex: c["editor.selectionBackground"]) ?? .selectedTextBackgroundColor
    }

    /// Colour for a token's foreground index, or nil for the default foreground.
    func color(at index: Int) -> NSColor? {
        guard index > 1, index < colorMap.count else { return nil }
        if let c = colors[index] { return c }
        let c = NSColor(hex: colorMap[index])
        colors[index] = c
        return c
    }

    /// The bundled light/dark pair, or the user's editor themes when chosen in settings and
    /// valid. Editor themes are resolved by the app and passed through shared settings.
    public static func current(dark: Bool, assets: URL, settings: SharedSettings) -> Theme {
        if settings.themeSource == .editor, let json = dark ? settings.editorThemeDark : settings.editorThemeLight,
           let theme = try? Theme(json: Data(json.utf8), key: "editor-\(dark ? "dark" : "light")-\(json.hashValue)") {
            return theme
        }
        let name = dark ? "dark" : "light"
        let url = assets.appendingPathComponent("themes/\(name).json")
        // The bundled themes are part of the app; failing to read them is a build error.
        return try! Theme(json: Data(contentsOf: url), key: "bundled-\(name)")
    }
}

extension NSColor {
    /// "#RGB", "#RGBA", "#RRGGBB" or "#RRGGBBAA".
    convenience init?(hex: String?) {
        guard var h = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 || h.count == 4 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        let rgb = h.count == 8 ? v >> 8 : v
        let alpha = h.count == 8 ? CGFloat(v & 0xFF) / 255 : 1
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}
