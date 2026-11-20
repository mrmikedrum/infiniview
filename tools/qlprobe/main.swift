// Probe: opens a QLPreviewView for each path given (in a hidden-ish window), waits, then exits.
// Used by scripts/check.sh with the extensions' opt-in debug log.
import AppKit
import QuickLookUI

let paths = CommandLine.arguments.dropFirst()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
let view = QLPreviewView(frame: window.contentView!.bounds, style: .normal)!
window.contentView = view
window.orderFrontRegardless()

// With no arguments, read paths from stdin one per line and keep running (a long-lived host, like Finder).
if paths.isEmpty {
    Thread.detachNewThread {
        while let line = readLine() {
            DispatchQueue.main.async {
                // "@light" / "@dark" switch the probe's appearance live, as the system setting would.
                if line == "@light" || line == "@dark" {
                    NSApp.appearance = NSAppearance(named: line == "@light" ? .aqua : .darkAqua)
                    return
                }
                print("probe: \(line)")
                // Clear first: assigning the same item again is a no-op.
                view.previewItem = nil
                view.previewItem = URL(fileURLWithPath: line) as NSURL
                view.refreshPreviewItem()
            }
        }
        DispatchQueue.main.async { exit(0) }
    }
}
var queue = Array(paths)
func next() {
    guard !paths.isEmpty else { return }
    guard !queue.isEmpty else { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }; return }
    let p = queue.removeFirst()
    print("probe: \(p)")
    view.previewItem = URL(fileURLWithPath: p) as NSURL
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { next() }
}
DispatchQueue.main.async { next() }
app.run()
