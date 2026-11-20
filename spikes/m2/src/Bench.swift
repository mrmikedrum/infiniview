// Highlighting benchmark shared by the command-line runner and the sandboxed extension.
import AppKit

enum Bench {
    static let header = "where\tfile\tbytes\tlines\tscope\tinit_ms\tgrammar_ms\tfirst500_ms\ttokenize_ms\tattr_ms\ttokens\tstopped"

    static var highlighter: Highlighter?
    static var theme: Highlighter.Theme?
    static var initMillis = 0.0
    static var byExtension: [String: String] = [:]

    static func ms(_ f: () throws -> Void) rethrows -> Double {
        let t = DispatchTime.now().uptimeNanoseconds
        try f()
        return Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6
    }

    static func setUp(assets: URL) throws {
        guard highlighter == nil else { return }
        initMillis = try ms {
            let h = try Highlighter(assets: assets)
            theme = h.setTheme(try Data(contentsOf: assets.appendingPathComponent("themes/dark.json")))
            highlighter = h
        }
        let index = try JSONSerialization.jsonObject(with: Data(contentsOf: assets.appendingPathComponent("languages.json"))) as! [String: Any]
        for l in index["languages"] as! [[String: Any]] {
            for e in l["extensions"] as! [String] where byExtension[e] == nil { byExtension[e] = l["scopeName"] as? String }
        }
    }

    /// One row of results for one file. `firstInit` is reported once per process.
    static func run(_ url: URL, where place: String, assets: URL) throws -> String {
        let fresh = highlighter == nil
        try setUp(assets: assets)
        let h = highlighter!
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        // Extensionless corpus copies ("py-100k") name their language before the dash.
        var ext = url.pathExtension.lowercased()
        if ext.isEmpty { ext = String(url.lastPathComponent.split(separator: "-")[0]) }
        if ext == "jsonmin" { ext = "json" }
        let scope = byExtension[ext] ?? "text.plain"
        var ok = false
        let grammarMs = ms { ok = h.loadGrammar(scope) }
        guard ok else { return "\(place)\t\(url.lastPathComponent)\tno grammar for \(scope)" }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let first = lines.prefix(500).joined(separator: "\n")
        let firstMs = ms { _ = h.tokenize(first, scope: scope) }
        var result: Highlighter.Result!
        let tokMs = ms { result = h.tokenize(text, scope: scope) }
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attrMs = ms { _ = Highlighter.attributed(text, result, theme: theme!, font: font) }
        let f = { (d: Double) in String(format: "%.1f", d) }
        return [place, url.lastPathComponent, "\(data.count)", "\(lines.count)", scope, fresh ? f(initMillis) : "-",
                f(grammarMs), f(firstMs), f(tokMs), f(attrMs), "\(result.tokens.count / 2)", "\(result.stoppedAt)"].joined(separator: "\t")
    }
}
