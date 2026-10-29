import AppKit

/// The editor and the preview side by side, above the status bar, which spans both. While the
/// editor is shown, the button that links the two sits on the divider between them.
@MainActor
final class ContentViewController: NSViewController {
    let split = NSSplitViewController()
    let statusBar = StatusBarView()
    private let linkButton = DividerLinkButton()
    var onToggleLinked: (() -> Void)?

    /// Whether the editor and the preview are linked, or nil while the editor is hidden, which
    /// hides the button.
    var linkState: Bool? {
        didSet {
            linkButton.isLinked = linkState ?? true
            positionLinkButton()
        }
    }

    init(items: [NSSplitViewItem]) {
        super.init(nibName: nil, bundle: nil)
        split.splitView.dividerStyle = .thin
        items.forEach(split.addSplitViewItem)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = NSView()
        addChild(split)
        linkButton.target = self
        linkButton.action = #selector(linkClicked)
        linkButton.isHidden = true
        // Added last, so it stays above the split view.
        for view in [split.view, statusBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            split.view.topAnchor.constraint(equalTo: container.topAnchor),
            split.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            split.view.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.addSubview(linkButton)
        view = container
        NotificationCenter.default.addObserver(
            self, selector: #selector(splitViewDidResize), name: NSSplitView.didResizeSubviewsNotification, object: split.splitView)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        positionLinkButton()
    }

    @objc private func splitViewDidResize(_ notification: Notification) {
        positionLinkButton()
    }

    @objc private func linkClicked() {
        onToggleLinked?()
    }

    /// Centers the button on the divider, halfway down.
    private func positionLinkButton() {
        guard isViewLoaded else { return }
        let splitView = split.splitView
        guard linkState != nil, let editorItem = split.splitViewItems.first, !editorItem.isCollapsed,
            let editorView = splitView.arrangedSubviews.first, editorView.frame.width > 0
        else {
            linkButton.isHidden = true
            return
        }
        let center = view.convert(
            NSPoint(x: editorView.frame.maxX + splitView.dividerThickness / 2, y: splitView.bounds.midY), from: splitView)
        let size = DividerLinkButton.diameter
        linkButton.frame = NSRect(x: (center.x - size / 2).rounded(), y: (center.y - size / 2).rounded(), width: size, height: size)
        linkButton.isHidden = false
    }
}
