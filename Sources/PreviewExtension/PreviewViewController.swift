import AppKit
import InfiniviewCore
import InfiniviewPreview
import QuickLookUI

/// Quick Look's entry point. The same binary runs as both preview extensions: the main one
/// (public.data, public.unix-executable, the Learned Type) and Takeover (system text types).
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
    private var controller: PreviewController?
    private var failure: Error?

    override func loadView() {
        do {
            let c = try PreviewController(assets: Bundle.main.resourceURL!.appendingPathComponent("highlighting"))
            controller = c
            view = c.view
        } catch {
            failure = error
            view = NSView()
        }
    }

    nonisolated func preparePreviewOfFile(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        // Quick Look calls this on the main thread for view-based previews; hop there if not.
        // Learn the text extensions of this file's neighbours before they're previewed (ADR-0005).
        FolderCheckClient.request(folder: url.deletingLastPathComponent())
        nonisolated(unsafe) let handler = completionHandler
        let work = { @MainActor in
            do {
                if let failure = self.failure { throw failure }
                try self.controller?.load(url)
                handler(nil)
            } catch {
                handler(error)
            }
        }
        if Thread.isMainThread { MainActor.assumeIsolated { work() } } else { DispatchQueue.main.async { work() } }
    }
}
