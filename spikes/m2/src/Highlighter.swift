// TextMate highlighting through vscode-textmate + vscode-oniguruma running in JavaScriptCore.
import AppKit
import JavaScriptCore

final class Highlighter {
    struct Theme { let colors: [NSColor]; let background: NSColor; let foreground: NSColor }
    struct Result { let tokens: [UInt32]; let stoppedAt: Int }

    private let context: JSContext
    private let assets: URL
    private let iv: JSValue

    init(assets: URL) throws {
        self.assets = assets
        let context = JSContext()!
        var failure: String?
        context.exceptionHandler = { _, e in failure = e?.toString() }
        let grammarsDir = assets.appendingPathComponent("grammars")
        let read: @convention(block) (String) -> String? = { scope in
            try? String(contentsOf: grammarsDir.appendingPathComponent("\(scope).json"), encoding: .utf8)
        }
        context.setObject(read, forKeyedSubscript: "__readGrammar" as NSString)
        let js = try String(contentsOf: assets.appendingPathComponent("highlighter.js"), encoding: .utf8)
        context.evaluateScript(js)
        let wasm = try Data(contentsOf: assets.appendingPathComponent("onig.wasm"))
        let bytes = Highlighter.uint8Array(wasm, in: context)
        iv = context.objectForKeyedSubscript("IV")
        let index = try JSONSerialization.jsonObject(with: Data(contentsOf: assets.appendingPathComponent("languages.json"))) as? [String: Any]
        iv.invokeMethod("init", withArguments: [bytes, index?["injections"] ?? [:]])
        if let failure { throw NSError(domain: "Highlighter", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
        self.context = context
    }

    func setTheme(_ json: Data) -> Theme {
        let obj = try! JSONSerialization.jsonObject(with: json) as! [String: Any]
        // Index 0 of the colour map is unused (null).
        let map = iv.invokeMethod("setTheme", withArguments: [obj])!.toArray() ?? []
        let colors = map.map { ($0 as? String).flatMap { NSColor(hex: $0) } ?? .textColor }
        let c = obj["colors"] as? [String: String] ?? [:]
        return Theme(colors: colors,
                     background: NSColor(hex: c["editor.background"] ?? "") ?? .textBackgroundColor,
                     foreground: NSColor(hex: c["editor.foreground"] ?? "") ?? .textColor)
    }

    /// Loads a grammar (and, lazily, the grammars it embeds). Returns false if it isn't available.
    func loadGrammar(_ scope: String) -> Bool {
        let state = iv.invokeMethod("loadGrammar", withArguments: [scope])!
        return !(state.forProperty("grammar").isNull || state.forProperty("grammar").isUndefined)
    }

    func tokenize(_ text: String, scope: String, maxLineLength: Int = 20_000, maxMillis: Int = 10_000) -> Result {
        let r = iv.invokeMethod("tokenize", withArguments: [scope, text, maxLineLength, maxMillis])!
        guard let arr = r.forProperty("tokens"), arr.isObject else { return Result(tokens: [], stoppedAt: 0) } // JS threw: show plain
        let ctx = context.jsGlobalContextRef
        let obj = arr.jsValueRef!
        let count = JSObjectGetTypedArrayLength(ctx, obj, nil)
        let ptr = JSObjectGetTypedArrayBytesPtr(ctx, obj, nil)!.bindMemory(to: UInt32.self, capacity: count)
        let tokens = Array(UnsafeBufferPointer(start: ptr, count: count))
        return Result(tokens: tokens, stoppedAt: Int(r.forProperty("stoppedAt").toInt32()))
    }

    static func attributed(_ text: String, _ result: Result, theme: Theme, font: NSFont) -> NSAttributedString {
        let s = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: theme.foreground])
        let length = (text as NSString).length
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        let t = result.tokens
        s.beginEditing()
        var i = 0
        while i < t.count {
            let start = Int(t[i]), meta = t[i + 1]
            // Merge following tokens with the same look.
            var j = i + 2
            while j < t.count && t[j + 1] == meta { j += 2 }
            let end = j < t.count ? Int(t[j]) : (result.stoppedAt >= 0 ? result.stoppedAt : length)
            let fg = Int((meta & 0x00FF_8000) >> 15), style = (meta & 0x7800) >> 11
            let range = NSRange(location: start, length: max(0, min(end, length) - start))
            if range.length > 0 {
                if fg > 1, fg < theme.colors.count { s.addAttribute(.foregroundColor, value: theme.colors[fg], range: range) }
                if style & 2 != 0 { s.addAttribute(.font, value: bold, range: range) }
                else if style & 1 != 0 { s.addAttribute(.font, value: italic, range: range) }
                if style & 4 != 0 { s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            }
            i = j
        }
        s.endEditing()
        return s
    }

    private static func uint8Array(_ data: Data, in context: JSContext) -> JSValue {
        let ctx = context.jsGlobalContextRef
        let obj = JSObjectMakeTypedArray(ctx, kJSTypedArrayTypeUint8Array, data.count, nil)!
        let ptr = JSObjectGetTypedArrayBytesPtr(ctx, obj, nil)!
        data.copyBytes(to: ptr.bindMemory(to: UInt8.self, capacity: data.count), count: data.count)
        return JSValue(jsValueRef: obj, in: context)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if h.count == 3 || h.count == 4 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        let a = h.count == 8 ? CGFloat(v & 0xFF) / 255 : 1
        let rgb = h.count == 8 ? v >> 8 : v
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: a)
    }
}
