import AppKit

/// The strip below the editor and the preview: the document's length and the section being
/// read on the left; on the right, the link toggle while the editor is shown, and the zoom
/// control.
@MainActor
final class StatusBarView: NSView {
    private let statsLabel = NSTextField(labelWithString: "")
    private let sectionLabel = NSTextField(labelWithString: "")
    private let linkButton = LinkButton()
    private let zoomGroup = ZoomGroup()

    var onZoom: ((Zoom.Step) -> Void)? {
        get { zoomGroup.onZoom }
        set { zoomGroup.onZoom = newValue }
    }
    var onToggleLinked: (() -> Void)?

    /// Whether a document is shown; the bar shows only the zoom control otherwise.
    var isActive = false {
        didSet {
            if !isActive {
                statsLabel.stringValue = ""
                sectionLabel.stringValue = ""
            }
        }
    }

    /// Whether the editor and the preview are linked, or nil while the editor is hidden, which
    /// hides the toggle.
    var linkState: Bool? {
        didSet {
            linkButton.isHidden = linkState == nil
            linkButton.isLinked = linkState ?? false
        }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        for label in [statsLabel, sectionLabel] {
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        linkButton.target = self
        linkButton.action = #selector(linkClicked)
        linkButton.isHidden = true

        let separator = NSBox()
        separator.boxType = .separator
        let leading = NSStackView(views: [statsLabel, sectionLabel])
        leading.spacing = 14
        let trailing = NSStackView(views: [linkButton, zoomGroup])
        trailing.spacing = 8
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [separator, leading, trailing] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            leading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            leading.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: leading.trailingAnchor, constant: 14),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),
        ])
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setWordCount(_ words: Int) {
        guard words > 0 else {
            statsLabel.stringValue = ""
            return
        }
        let minutes = max(1, Int((Double(words) / 220).rounded()))
        let count = words.formatted(.number)
        statsLabel.stringValue = "\(count) \(words == 1 ? "word" : "words") · \(minutes) min read"
    }

    func setSection(_ text: String?) {
        sectionLabel.stringValue = text ?? ""
    }

    func setZoom(_ zoom: CGFloat) {
        zoomGroup.setZoom(zoom)
    }

    @objc private func linkClicked() {
        onToggleLinked?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        layer?.backgroundColor = resolvedCGColor(Palette.pageBackground)
    }
}

/// The chain-link toggle, pressed and labeled "Linked" while the editor and the preview scroll
/// and zoom together.
@MainActor
private final class LinkButton: NSButton {
    var isLinked = false {
        didSet { update() }
    }

    init() {
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        imagePosition = .imageLeading
        imageHugsTitle = true
        setContentHuggingPriority(.required, for: .horizontal)
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: super.intrinsicContentSize.width + 16, height: 22)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func update() {
        let color: NSColor = isLinked ? Palette.inkText : .secondaryLabelColor
        attributedTitle = NSAttributedString(
            string: isLinked ? "Linked" : "Unlinked",
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: color])
        contentTintColor = color
        toolTip = isLinked
            ? "The editor and the preview scroll and zoom together. Click to unlink them."
            : "The editor and the preview scroll and zoom separately. Click to link them."
        setAccessibilityLabel(isLinked ? "Linked" : "Unlinked")
        setAccessibilityHelp(toolTip)
        invalidateIntrinsicContentSize()
        updateColors()
    }

    private func updateColors() {
        layer?.borderColor = resolvedCGColor(Palette.controlBorder)
        layer?.backgroundColor = isLinked ? resolvedCGColor(Palette.controlFill) : NSColor.clear.cgColor
    }
}

/// "− 100% +" in a bordered group: zoom out, the zoom level (click for actual size), zoom in.
@MainActor
private final class ZoomGroup: NSView {
    var onZoom: ((Zoom.Step) -> Void)?
    private let levelButton = NSButton()
    private let separators = [NSView(), NSView()]

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        let zoomOut = NSButton()
        let zoomIn = NSButton()
        configure(zoomOut, title: "−", font: .systemFont(ofSize: 13), width: 24, toolTip: "Zoom Out", action: #selector(zoomOutClicked))
        configure(
            levelButton, title: "100%", font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium), width: 44,
            toolTip: "Actual Size", action: #selector(actualSizeClicked))
        configure(zoomIn, title: "+", font: .systemFont(ofSize: 13), width: 24, toolTip: "Zoom In", action: #selector(zoomInClicked))
        for separator in separators {
            separator.wantsLayer = true
            separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
            separator.heightAnchor.constraint(equalToConstant: 22).isActive = true
        }
        let stack = NSStackView(views: [zoomOut, separators[0], levelButton, separators[1], zoomIn])
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Zoom")
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setZoom(_ zoom: CGFloat) {
        setTitle("\(Int((zoom * 100).rounded()))%", of: levelButton)
    }

    private func configure(_ button: NSButton, title: String, font: NSFont, width: CGFloat, toolTip: String, action: Selector) {
        button.isBordered = false
        button.font = font
        setTitle(title, of: button)
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    private func setTitle(_ title: String, of button: NSButton) {
        button.attributedTitle = NSAttributedString(
            string: title, attributes: [.font: button.font ?? .systemFont(ofSize: 11), .foregroundColor: Palette.inkText])
    }

    @objc private func zoomOutClicked() { onZoom?(.smaller) }
    @objc private func actualSizeClicked() { onZoom?(.actualSize) }
    @objc private func zoomInClicked() { onZoom?(.larger) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        layer?.borderColor = resolvedCGColor(Palette.controlBorder)
        layer?.backgroundColor = resolvedCGColor(Palette.controlFill)
        for separator in separators {
            separator.layer?.backgroundColor = resolvedCGColor(Palette.hairline)
        }
    }
}
