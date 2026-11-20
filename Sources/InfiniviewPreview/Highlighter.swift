import Foundation
import InfiniviewCore
import JavaScriptCore

/// TextMate highlighting: vscode-textmate and vscode-oniguruma (bundled in highlighter.js and
/// onig.wasm) running in JavaScriptCore. Not thread-safe: use one instance from one queue.
/// The extension needs `com.apple.security.cs.allow-jit`, or this runs 20–30× slower.
public final class Highlighter {
    /// Token starts (UTF-16 offsets) and vscode-textmate's encoded metadata, as pairs.
    public struct Tokens: Sendable {
        public var pairs: [UInt32]
        /// UTF-16 offset where tokenizing stopped (time budget), or nil if it finished.
        public var stoppedAt: Int?
        public static let empty = Tokens(pairs: [], stoppedAt: nil)
    }

    public enum Failure: Error { case script(String) }

    private let context: JSContext
    private let api: JSValue
    private var loadedTheme: String?

    public init(assets: URL, injections: [String: [String]]) throws {
        let context = JSContext()!
        var failure: String?
        context.exceptionHandler = { _, e in failure = e?.toString() }
        let grammars = assets.appendingPathComponent("grammars")
        let read: @convention(block) (String) -> String? = { scope in
            // Scope names come from the grammars themselves; keep reads inside the folder.
            guard !scope.contains("/"), !scope.hasPrefix(".") else { return nil }
            return try? String(contentsOf: grammars.appendingPathComponent("\(scope).json"), encoding: .utf8)
        }
        context.setObject(read, forKeyedSubscript: "__readGrammar" as NSString)
        context.evaluateScript(try String(contentsOf: assets.appendingPathComponent("highlighter.js"), encoding: .utf8))
        let wasm = try Data(contentsOf: assets.appendingPathComponent("onig.wasm"))
        api = context.objectForKeyedSubscript("IV")
        api.invokeMethod("init", withArguments: [Self.uint8Array(wasm, in: context), injections])
        if let failure { throw Failure.script(failure) }
        self.context = context
    }

    /// Sets the theme the next tokenize call colours with. Returns its colour map
    /// (index → "#RRGGBB"; index 0 unused). Cheap if the theme is already set.
    @discardableResult
    public func setTheme(_ theme: Theme) -> [String] {
        // A new Theme object with the same key still needs its colour map filled in.
        if loadedTheme != theme.key || theme.colorMap.isEmpty {
            let map = api.invokeMethod("setTheme", withArguments: [theme.raw])?.toArray() ?? []
            theme.colorMap = map.map { $0 as? String ?? "" }
            loadedTheme = theme.key
        }
        return theme.colorMap
    }

    /// Loads a grammar and those it embeds. False if it isn't bundled.
    public func loadGrammar(_ scope: String) -> Bool {
        let state = api.invokeMethod("loadGrammar", withArguments: [scope])
        guard let grammar = state?.forProperty("grammar") else { return false }
        return !grammar.isNull && !grammar.isUndefined
    }

    public func tokenize(_ text: String, scope: String,
                         maxLineLength: Int = PreviewLimits.maxHighlightedLineLength,
                         budgetMillis: Int = PreviewLimits.highlightBudgetMillis) -> Tokens {
        guard let result = api.invokeMethod("tokenize", withArguments: [scope, text, maxLineLength, budgetMillis]),
              let array = result.forProperty("tokens"), array.isObject else { return .empty }
        let ctx = context.jsGlobalContextRef
        let ref = array.jsValueRef
        let count = JSObjectGetTypedArrayLength(ctx, ref, nil)
        guard count > 0, let raw = JSObjectGetTypedArrayBytesPtr(ctx, ref, nil) else { return .empty }
        let pairs = Array(UnsafeBufferPointer(start: raw.bindMemory(to: UInt32.self, capacity: count), count: count))
        let stopped = Int(result.forProperty("stoppedAt")?.toInt32() ?? -1)
        return Tokens(pairs: pairs, stoppedAt: stopped >= 0 ? stopped : nil)
    }

    private static func uint8Array(_ data: Data, in context: JSContext) -> JSValue {
        let ctx = context.jsGlobalContextRef
        let obj = JSObjectMakeTypedArray(ctx, kJSTypedArrayTypeUint8Array, data.count, nil)!
        let ptr = JSObjectGetTypedArrayBytesPtr(ctx, obj, nil)!
        data.copyBytes(to: ptr.bindMemory(to: UInt8.self, capacity: data.count), count: data.count)
        return JSValue(jsValueRef: obj, in: context)
    }
}

/// vscode-textmate's encoded token metadata.
public enum TokenMetadata {
    public static func foreground(_ m: UInt32) -> Int { Int((m & 0x00FF_8000) >> 15) }
    public static func isItalic(_ m: UInt32) -> Bool { m & (1 << 11) != 0 }
    public static func isBold(_ m: UInt32) -> Bool { m & (2 << 11) != 0 }
    public static func isUnderline(_ m: UInt32) -> Bool { m & (4 << 11) != 0 }
    public static func isStrikethrough(_ m: UInt32) -> Bool { m & (8 << 11) != 0 }
}
