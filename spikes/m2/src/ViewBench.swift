// View-based benchmark: the MVP's preview shape. Loads the file into a TextKit 2 NSTextView,
// highlights the first lines synchronously, hands the view to Quick Look, then highlights the
// rest in the background. Records when each stage finished, relative to the request.
import AppKit
import QuickLookUI

final class TimedTextView: NSTextView {
    var onFirstDraw: (() -> Void)?
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        onFirstDraw?(); onFirstDraw = nil
    }
}

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    static let syncLines = 300
    static let queue = DispatchQueue(label: "highlight")
    private var textView: TimedTextView!

    override func loadView() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.hasVerticalScroller = true
        let tv = TimedTextView(usingTextLayoutManager: true)
        tv.isEditable = false
        tv.isSelectable = true
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.frame = scroll.contentView.bounds
        scroll.documentView = tv
        textView = tv
        view = scroll
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let ms = { String(format: "%.1f", Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6) }
        var row = ["view", url.lastPathComponent]
        let assets = Bundle.main.resourceURL!.appendingPathComponent("assets")
        do {
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            row += ["\(data.count)", ms()] // read+decode
            try Bench.setUp(assets: assets)
            let h = Bench.highlighter!, theme = Bench.theme!
            var ext = url.pathExtension.lowercased()
            if ext.isEmpty { ext = String(url.lastPathComponent.split(separator: "-")[0]) }
            let scope = Bench.byExtension[ext]
            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            textView.backgroundColor = theme.background
            // First lines: highlighted before the view is handed over.
            let ns = text as NSString
            var firstEnd = 0, lines = 0
            while lines < Self.syncLines && firstEnd < ns.length {
                let r = ns.range(of: "\n", range: NSRange(location: firstEnd, length: ns.length - firstEnd))
                firstEnd = r.location == NSNotFound ? ns.length : r.location + 1
                lines += 1
            }
            let storage = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: theme.foreground])
            if let scope, h.loadGrammar(scope) {
                let head = ns.substring(to: firstEnd)
                let r = h.tokenize(head, scope: scope)
                storage.replaceCharacters(in: NSRange(location: 0, length: firstEnd), with: Highlighter.attributed(head, r, theme: theme, font: font))
            }
            textView.textStorage?.setAttributedString(storage)
            row.append(ms()) // ready to hand over
            var drawn = "nodraw" // main thread only
            textView.onFirstDraw = { drawn = ms() }
            handler(nil)
            // The rest, in the background. (Waits a moment so the first draw isn't competing.)
            Self.queue.asyncAfter(deadline: .now() + 1) {
                var tail = ["-", "-", "-"]
                if let scope {
                    let r = h.tokenize(text, scope: scope, maxMillis: 5_000)
                    let full = Highlighter.attributed(text, r, theme: theme, font: font)
                    let built = ms()
                    DispatchQueue.main.sync { self.textView.textStorage?.setAttributedString(full) }
                    tail = [built, ms(), "\(r.stoppedAt)"]
                }
                DispatchQueue.main.async { Self.log((row + [drawn] + tail).joined(separator: "\t")) }
            }
        } catch {
            handler(error)
            Self.log((row + ["error \(error)"]).joined(separator: "\t"))
        }
    }

    static func log(_ line: String) {
        let log = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bench.tsv")
        if let h = try? FileHandle(forWritingTo: log) { h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close() }
        else { try? Data((line + "\n").utf8).write(to: log) }
    }
}
