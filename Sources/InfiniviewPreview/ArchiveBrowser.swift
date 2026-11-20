import AppKit
import InfiniviewCore
import PDFKit
import UniformTypeIdentifiers

/// An archive's Preview (ADR-0006): a tree of what's inside and, when there's room (the Quick
/// Look Panel), a Preview of the selected entry beside it. Narrower than
/// `PreviewView.compactWidth` (Finder's Preview Pane), only the tree.
@MainActor
final class ArchiveBrowser: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    final class Node {
        let name: String
        let path: String
        var entry: ArchiveEntry?
        private var unsorted = [Node]()
        private var sorted: [Node]?
        /// Sorted when first asked for (folders first, then Finder's name order): sorting a large
        /// archive's every folder up front is slow, and most are never opened.
        var children: [Node] {
            if let sorted { return sorted }
            let s = unsorted.sorted {
                $0.isFolder != $1.isFolder ? $0.isFolder : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            sorted = s
            return s
        }
        func add(_ child: Node) {
            unsorted.append(child)
            sorted = nil
        }
        var isFolder: Bool { entry?.kind == .directory || !unsorted.isEmpty || entry == nil }
        init(name: String, path: String) {
            self.name = name
            self.path = path
        }
    }

    /// Most of an image or PDF unpacked for its Preview; larger ones aren't shown.
    nonisolated static let maxUnpackedBytes = 64 * 1024 * 1024
    /// Most of anything else unpacked: the start of a huge text file, as much as a Preview shows.
    nonisolated static let maxUnpackedText = PreviewLimits.maxShownBytes

    /// Tells a background unpack its result is no longer wanted.
    final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        func cancel() { lock.withLock { cancelled = true } }
        var isCancelled: Bool { lock.withLock { cancelled } }
    }
    private var unpacking: Cancellation?

    private let listing: ArchiveListing
    private let archive: URL
    private let assets: URL
    private let root = Node(name: "", path: "")
    private let header = NSTextField(wrappingLabelWithString: "")
    private let outline = NSOutlineView()
    private let outlineScroll = NSScrollView()
    private let split = NSSplitView()
    private let detail = NSView()
    private let detailTitle = NSTextField(labelWithString: "")
    private let detailBody = NSView()
    private var inner: PreviewController?
    private var isCompact: Bool?
    private var placedDivider = false
    /// Bumped on every selection; unpacking for an older one is dropped.
    private var generation = 0
    /// Unpacked entries, removed with the browser.
    private let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("Infiniview-\(UUID().uuidString)")
    private var icons = [String: NSImage]()
    private var folderCount = 0

    init(listing: ArchiveListing, archive: URL, assets: URL) {
        self.listing = listing
        self.archive = archive
        self.assets = assets
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        buildTree()
        buildViews()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        unpacking?.cancel()
        try? FileManager.default.removeItem(at: scratch)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
    }

    // MARK: - Tree

    private func buildTree() {
        var folders = ["": root]
        func folder(_ path: String) -> Node {
            if let node = folders[path] { return node }
            let parentPath = (path as NSString).deletingLastPathComponent
            let node = Node(name: (path as NSString).lastPathComponent, path: path)
            folder(parentPath).add(node)
            folders[path] = node
            return node
        }
        for entry in listing.entries {
            if entry.kind == .directory {
                folder(entry.path).entry = entry
            } else {
                let node = Node(name: entry.name, path: entry.path)
                node.entry = entry
                folder((entry.path as NSString).deletingLastPathComponent).add(node)
            }
        }
        folderCount = folders.count - 1
    }

    // MARK: - Views

    private func buildViews() {
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        header.stringValue = summary()

        let name = NSTableColumn(identifier: .init("name"))
        name.resizingMask = .autoresizingMask
        let size = NSTableColumn(identifier: .init("size"))
        size.width = 64
        size.resizingMask = []
        outline.addTableColumn(name)
        outline.addTableColumn(size)
        outline.outlineTableColumn = name
        outline.headerView = nil
        outline.style = .plain
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.usesAlternatingRowBackgroundColors = false
        outline.intercellSpacing = NSSize(width: 4, height: 0)
        outline.indentationPerLevel = 12
        outline.autosaveExpandedItems = false
        outline.dataSource = self
        outline.delegate = self

        outlineScroll.documentView = outline
        outlineScroll.hasVerticalScroller = true
        outlineScroll.autohidesScrollers = true
        outlineScroll.borderType = .noBorder
        outlineScroll.drawsBackground = false

        detailTitle.textColor = .secondaryLabelColor
        detailTitle.lineBreakMode = .byTruncatingMiddle
        detailTitle.translatesAutoresizingMaskIntoConstraints = false
        detailBody.translatesAutoresizingMaskIntoConstraints = false
        detailBody.clipsToBounds = true
        detail.addSubview(detailTitle)
        detail.addSubview(detailBody)
        NSLayoutConstraint.activate([
            detailTitle.topAnchor.constraint(equalTo: detail.topAnchor, constant: 4),
            detailTitle.leadingAnchor.constraint(equalTo: detail.leadingAnchor, constant: 8),
            detailTitle.trailingAnchor.constraint(lessThanOrEqualTo: detail.trailingAnchor, constant: -8),
            detailBody.topAnchor.constraint(equalTo: detailTitle.bottomAnchor, constant: 4),
            detailBody.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            detailBody.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            detailBody.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
        ])

        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(outlineScroll)
        addSubview(header)
        addSubview(split)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            header.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            split.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            split.leadingAnchor.constraint(equalTo: leadingAnchor),
            split.trailingAnchor.constraint(equalTo: trailingAnchor),
            split.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        outline.reloadData()
        // Open a lone top folder (most archives hold one) so its contents show at once.
        var node = root
        while node.children.count == 1, let only = node.children.first, only.isFolder {
            outline.expandItem(only)
            node = only
        }
        showMessage(nil)
    }

    /// Decided on every layout pass, not only on size changes: Quick Look can show the browser at
    /// exactly the size it was created with, and then no size change ever arrives.
    override func layout() {
        super.layout()
        guard bounds.width > 0 else { return }
        let compact = bounds.width < PreviewView.compactWidth
        guard compact != isCompact else { return }
        isCompact = compact
        // Not during layout: this adds and removes subviews.
        DispatchQueue.main.async { [weak self] in self?.applyLayout() }
    }

    private var fontSize: CGFloat { isCompact == false ? 12 : 10 }

    private func applyLayout() {
        let compact = isCompact ?? true
        PreviewController.debugLog("\(archive.lastPathComponent)\tarchive layout\t\(compact ? "tree" : "browser")\t\(Int(bounds.width))x\(Int(bounds.height))")
        header.font = .systemFont(ofSize: fontSize - 1)
        detailTitle.font = .systemFont(ofSize: fontSize - 1)
        outline.rowHeight = ceil(fontSize * 1.6)
        outline.reloadData()
        if compact {
            if detail.superview != nil { detail.removeFromSuperview() }
        } else {
            if detail.superview == nil { split.addArrangedSubview(detail) }
            try? innerPreview()?.warmUp()
            if !placedDivider {
                split.layoutSubtreeIfNeeded()
                split.setPosition(min(320, (bounds.width * 0.38).rounded()), ofDividerAt: 0)
                placedDivider = true
                if outline.selectedRow < 0, let readme = findReadme() { select(node: readme) }
            }
        }
    }

    /// A README at the top, or in the lone top folder.
    private func findReadme() -> Node? {
        var node = root
        while true {
            if let readme = node.children.first(where: { $0.entry?.kind == .file && $0.name.lowercased().hasPrefix("readme") }) {
                return readme
            }
            guard node.children.count == 1, let only = node.children.first, only.isFolder else { return nil }
            node = only
        }
    }

    private func summary() -> String {
        let files = listing.entries.filter { $0.kind != .directory }
        var text = listing.format.description
        if case .compressed = listing.format {} else {
            text += " · \(count(files.count, "file")), \(count(folderCount, "folder"))"
        }
        let regular = files.filter { $0.kind == .file }
        let sizes = regular.compactMap(\.size)
        if !sizes.isEmpty, sizes.count == regular.count {
            text += " · \(Self.bytes(sizes.reduce(0, +))) unpacked"
        }
        switch listing.stoppedEarly {
        case .entryLimit: text += " · Showing the first \(listing.entries.count) entries."
        case .timeLimit: text += " · Listing stopped after a few seconds; showing the first \(listing.entries.count) entries."
        case .damaged: text += " · The archive is damaged or cut short after the entries shown."
        case nil: break
        }
        return text
    }

    private func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    // MARK: - Outline

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        ((item as? Node) ?? root).children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? Node) ?? root).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.children.isEmpty == false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? Node, let column = tableColumn?.identifier.rawValue else { return nil }
        let cell = outlineView.makeView(withIdentifier: .init(column), owner: nil) as? NSTableCellView ?? makeCell(column)
        let font = NSFont.systemFont(ofSize: fontSize)
        if column == "name" {
            cell.textField?.stringValue = node.name
            cell.textField?.font = font
            cell.imageView?.image = icon(for: node)
        } else {
            let size = node.entry.flatMap { $0.kind == .file ? $0.size : nil }
            cell.textField?.stringValue = size.map(Self.bytes) ?? ""
            cell.textField?.font = .monospacedDigitSystemFont(ofSize: fontSize - 1, weight: .regular)
        }
        return cell
    }

    private func makeCell(_ column: String) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = .init(column)
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        if column == "name" {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            image.imageScaling = .scaleProportionallyDown
            cell.addSubview(image)
            cell.imageView = image
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalTo: cell.heightAnchor, multiplier: 0.8),
                image.heightAnchor.constraint(equalTo: image.widthAnchor),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
                text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
            ])
        } else {
            text.alignment = .right
            text.textColor = .secondaryLabelColor
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(greaterThanOrEqualTo: cell.leadingAnchor),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            ])
        }
        text.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
        return cell
    }

    private func icon(for node: Node) -> NSImage {
        let key = node.isFolder ? "/" : (node.name as NSString).pathExtension.lowercased()
        if let cached = icons[key] { return cached }
        let type: UTType = node.isFolder ? .folder : UTType(filenameExtension: key) ?? .data
        let image = NSWorkspace.shared.icon(for: type)
        icons[key] = image
        return image
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        showDetail(outline.item(atRow: outline.selectedRow) as? Node)
    }

    func select(path: String) {
        var node = root
        for part in path.split(separator: "/") {
            guard let next = node.children.first(where: { $0.name == part }) else { return }
            node = next
        }
        select(node: node)
    }

    private func select(node: Node) {
        // Expand its folders first so it has a row.
        var ancestors = [Node]()
        var path = (node.path as NSString).deletingLastPathComponent
        while !path.isEmpty {
            if let folder = find(path) { ancestors.insert(folder, at: 0) }
            path = (path as NSString).deletingLastPathComponent
        }
        ancestors.forEach { outline.expandItem($0) }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        outline.selectRowIndexes([row], byExtendingSelection: false)
        outline.scrollRowToVisible(row)
    }

    private func find(_ path: String) -> Node? {
        var node = root
        for part in path.split(separator: "/") {
            guard let next = node.children.first(where: { $0.name == part }) else { return nil }
            node = next
        }
        return node
    }

    // MARK: - Detail

    /// When the current selection was made, for the debug log.
    private var selectedAt = DispatchTime.now()
    private func ms(since t: DispatchTime) -> String {
        String(format: "%.1fms", Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e6)
    }

    private func showDetail(_ node: Node?) {
        selectedAt = DispatchTime.now()
        generation += 1
        unpacking?.cancel()
        unpacking = nil
        try? FileManager.default.removeItem(at: scratch)
        guard !(isCompact ?? true), let node else { showMessage(nil); return }
        let entry = node.entry
        var title = node.path
        if let size = entry?.size, entry?.kind == .file { title += " · " + Self.bytes(size) }
        if let modified = entry?.modified {
            title += " · " + DateFormatter.localizedString(from: modified, dateStyle: .medium, timeStyle: .short)
        }
        detailTitle.stringValue = title

        switch entry?.kind {
        case .link(let target):
            showMessage("Link to \(target)")
        case .directory?, nil:
            let inside = listing.entries.filter { $0.path.hasPrefix(node.path + "/") && $0.kind != .directory }
            showMessage("Folder · \(count(inside.count, "file"))")
        case .file?:
            guard let entry else { return }
            if entry.isEncrypted { showMessage("This file is encrypted."); return }
            if let size = entry.size, size > Self.maxUnpackedBytes, !(isText(entry)) {
                showMessage("Too large to preview from inside the archive.")
                return
            }
            unpack(entry)
        }
    }

    private func isText(_ entry: ArchiveEntry) -> Bool {
        UTType(filenameExtension: (entry.name as NSString).pathExtension).map { !$0.conforms(to: .image) && !$0.conforms(to: .pdf) } ?? true
    }

    private func unpack(_ entry: ArchiveEntry) {
        let generation = self.generation
        let listing = self.listing, archive = self.archive
        let cap = isText(entry) ? Self.maxUnpackedText : Self.maxUnpackedBytes
        let cancellation = Cancellation()
        unpacking = cancellation
        // Only show a note if unpacking takes a moment. In a compressed tar everything before the
        // entry has to be unpacked first, which for one deep in a huge archive takes a while.
        var note = "Unpacking…"
        if case .tar(let compression) = listing.format, compression != .none, entry.location > 1 << 30 {
            note += "\nThis file starts \(Self.bytes(entry.location)) into the archive, so it may take a while."
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation, self.detailBody.subviews.isEmpty else { return }
                self.showMessage(note)
            }
        }
        showContent(nil)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try Archive.read(entry, of: listing, at: archive, maxBytes: cap, shouldStop: { cancellation.isCancelled })
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == generation else { return }
                    switch result {
                    case .success(let data):
                        PreviewController.debugLog("\(entry.name)\tunpacked\t\(data.count) bytes\t\(self.ms(since: self.selectedAt))")
                        if data.count == cap, (entry.size ?? .max) > Int64(cap) {
                            self.detailTitle.stringValue += " · showing the first \(Self.bytes(Int64(cap)))"
                        }
                        self.show(data, of: entry)
                    case .failure(ArchiveError.stopped): break
                    case .failure(ArchiveError.unsupportedMethod(let m)): self.showMessage("Compressed with a method Infiniview can't unpack (\(m)).")
                    case .failure: self.showMessage("This file couldn't be unpacked; the archive may be damaged.")
                    }
                }
            }
        }
    }

    private func show(_ data: Data, of entry: ArchiveEntry) {
        let type = UTType(filenameExtension: (entry.name as NSString).pathExtension)
        if type?.conforms(to: .pdf) == true, let pdf = PDFDocument(data: data) {
            let view = PDFView()
            view.document = pdf
            view.autoScales = true
            view.backgroundColor = .textBackgroundColor
            showContent(view)
            return
        }
        if type?.conforms(to: .image) == true, let image = NSImage(data: data) {
            let view = NSImageView(image: image)
            view.imageScaling = .scaleProportionallyDown
            view.imageAlignment = .alignCenter
            showContent(view)
            return
        }
        // Everything else goes through the Preview itself: text, RTF, the Fallback Card, or a
        // nested archive's own tree.
        do {
            let dir = scratch.appendingPathComponent("\(generation)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(entry.name)
            try data.write(to: file)
            guard let preview = try innerPreview() else { throw ArchiveError.damaged }
            showContent(preview.view)
            try preview.load(file)
            PreviewController.debugLog("\(entry.name)\tshown\t\(ms(since: selectedAt))")
        } catch {
            showMessage("This file couldn't be shown.")
        }
    }

    /// The Preview for selected entries, made once and reused.
    private func innerPreview() throws -> PreviewController? {
        if inner == nil {
            let preview = try PreviewController(assets: assets)
            preview.view.compactWidth = 0
            preview.highlightsBeforeShowing = false
            inner = preview
        }
        return inner
    }

    private func showContent(_ view: NSView?) {
        detailBody.subviews.forEach { $0.removeFromSuperview() }
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        detailBody.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: detailBody.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: detailBody.trailingAnchor),
            view.topAnchor.constraint(equalTo: detailBody.topAnchor),
            view.bottomAnchor.constraint(equalTo: detailBody.bottomAnchor),
        ])
    }

    /// A centred note in place of a Preview; nil for "Select a file to preview it."
    private func showMessage(_ text: String?) {
        if text == nil { detailTitle.stringValue = "" }
        let label = NSTextField(wrappingLabelWithString: text ?? "Select a file to preview it.")
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.font = .systemFont(ofSize: fontSize)
        let holder = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: holder.widthAnchor, constant: -32),
        ])
        showContent(holder)
    }
}
