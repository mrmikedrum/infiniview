import AppKit
import InfiniviewCore

/// The Preview's view: an optional banner above a scrollable, selectable TextKit 2 text view,
/// with optional line numbers. Used for text, RTF and the Fallback Card alike.
public final class PreviewView: NSView {
    public let textView: NSTextView
    public let scrollView: NSScrollView
    private let banner = NSTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()
    private var ruler: LineNumberRuler?
    /// Called when the system appearance changes (light/dark).
    public var onAppearanceChange: (() -> Void)?

    public override init(frame: NSRect) {
        textView = NSTextView(usingTextLayoutManager: true)
        scrollView = NSScrollView(frame: frame)
        super.init(frame: frame)

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        setWraps(true)

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView

        banner.isHidden = true
        banner.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        banner.textColor = .secondaryLabelColor
        banner.setContentCompressionResistancePriority(.required, for: .vertical)

        stack.orientation = .vertical
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.alignment = .leading
        stack.addArrangedSubview(banner)
        stack.addArrangedSubview(scrollView)
        stack.setCustomSpacing(4, after: banner)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            banner.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 8),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: stack.trailingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Soft wrap (text) or horizontal scrolling (hex dump).
    public func setWraps(_ wraps: Bool) {
        textView.isHorizontallyResizable = !wraps
        textView.textContainer?.widthTracksTextView = wraps
        if !wraps { textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude) }
        scrollView.hasHorizontalScroller = !wraps
    }

    /// A one-line note above the text ("Showing the first 32 MB of 120 MB."), or nil for none.
    public func setBanner(_ text: String?) {
        banner.stringValue = text ?? ""
        banner.isHidden = text == nil
    }

    public func showLineNumbers(_ index: LineIndex?, color: NSColor, background: NSColor) {
        if let index {
            let r = ruler ?? LineNumberRuler(textView: textView)
            r.lineIndex = index
            r.numberColor = color
            r.backgroundColor = background
            ruler = r
            scrollView.verticalRulerView = r
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
        } else {
            scrollView.rulersVisible = false
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    public var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

/// Line numbers for a TextKit 2 text view: one number per paragraph (logical line), so wrapped
/// lines get one number. Reads layout only through NSTextLayoutManager, so the text view stays
/// on TextKit 2.
final class LineNumberRuler: NSRulerView {
    weak var textView: NSTextView?
    var lineIndex = LineIndex("") { didSet { updateThickness() } }
    var numberColor = NSColor.secondaryLabelColor
    var backgroundColor = NSColor.textBackgroundColor
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        // Redraw when the text scrolls or reflows.
        let clip = textView.enclosingScrollView?.contentView
        clip?.postsBoundsChangedNotifications = true
        textView.postsFrameChangedNotifications = true
        for (name, object) in [(NSView.boundsDidChangeNotification, clip), (NSView.frameDidChangeNotification, textView)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.needsDisplay = true }
            })
        }
    }

    required init(coder: NSCoder) { fatalError("not used") }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private var font: NSFont { .monospacedDigitSystemFont(ofSize: max(9, (textView?.font?.pointSize ?? 12) - 1), weight: .regular) }

    private func updateThickness() {
        let digits = max(3, String(lineIndex.count).count)
        let width = (String(repeating: "8", count: digits) as NSString).size(withAttributes: [.font: font]).width
        ruleThickness = ceil(width + 14)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        guard let textView, let layout = textView.textLayoutManager, let content = layout.textContentManager,
              let viewport = layout.textViewportLayoutController.viewportRange else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: numberColor]
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin
        layout.enumerateTextLayoutFragments(from: viewport.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY + origin.y > visible.maxY { return false }
            let offset = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
            let number = "\(lineIndex.line(at: offset))" as NSString
            let size = number.size(withAttributes: attributes)
            // Align with the first line's baseline.
            let firstLine = fragment.textLineFragments.first
            let baseline = (firstLine?.typographicBounds.minY ?? 0) + (firstLine?.glyphOrigin.y ?? font.ascender)
            let y = convert(NSPoint(x: 0, y: frame.minY + origin.y + baseline), from: textView).y - font.ascender
            number.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: y), withAttributes: attributes)
            return true
        }
    }
}
