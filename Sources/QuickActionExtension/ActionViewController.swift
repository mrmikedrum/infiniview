import AppKit
import InfiniviewCore
import UniformTypeIdentifiers

/// Finder's Quick Action "Always Preview as Text". Asks the app (which isn't sandboxed) to learn
/// the file's extension through an `infiniview://learn` URL, and says what happened.
@objc(ActionViewController)
final class ActionViewController: NSViewController {
    private let message = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.keyEquivalent = "\r"
        let stack = NSStackView(views: [message, done])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        message.preferredMaxLayoutWidth = 320
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 120)
        view = stack
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        message.stringValue = "…"
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        guard let provider = providers.first else {
            message.stringValue = "Choose a file first."
            return
        }
        // Finder offers the file under its own type (often a dynamic one) and names it; only the
        // name is needed.
        if let name = provider.suggestedName, !name.isEmpty {
            learn(URL(fileURLWithPath: name))
            return
        }
        guard let type = provider.registeredTypeIdentifiers.first else {
            message.stringValue = "Choose a file first."
            return
        }
        provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
            let url = item as? URL
            DispatchQueue.main.async { MainActor.assumeIsolated { self.learn(url) } }
        }
    }

    private func learn(_ url: URL?) {
        guard let url else { message.stringValue = "Infiniview couldn't read that file's name."; return }
        let ext = url.pathExtension
        guard let e = ExtensionList.normalize(ext) else {
            message.stringValue = "“\(url.lastPathComponent)” has no extension. Infiniview already previews files without one."
            return
        }
        if let type = UTType(filenameExtension: e), !type.isDynamic {
            message.stringValue = type.identifier == LearnedTypeHelper.typeIdentifier
                ? "Infiniview already previews .\(e) files as text."
                : "macOS already treats .\(e) as “\(type.localizedDescription ?? type.identifier)”, so Infiniview can't take it over."
            return
        }
        var components = URLComponents()
        components.scheme = "infiniview"
        components.host = "learn"
        components.queryItems = [URLQueryItem(name: "ext", value: e)]
        guard let learnURL = components.url, NSWorkspace.shared.open(learnURL) else {
            message.stringValue = "Couldn't reach the Infiniview app. Open it once, then try again."
            return
        }
        message.stringValue = "Files ending in .\(e) will now preview as text."
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
