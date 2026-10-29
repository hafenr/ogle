import AppKit

/// The editor and the preview side by side, above the status bar, which spans both.
@MainActor
final class ContentViewController: NSViewController {
    let split = NSSplitViewController()
    let statusBar = StatusBarView()

    init(items: [NSSplitViewItem]) {
        super.init(nibName: nil, bundle: nil)
        split.splitView.dividerStyle = .thin
        items.forEach(split.addSplitViewItem)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = NSView()
        addChild(split)
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
        view = container
    }
}
