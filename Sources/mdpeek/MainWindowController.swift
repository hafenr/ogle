import AppKit
import UniformTypeIdentifiers

private extension NSToolbarItem.Identifier {
    static let find = Self("find")
    static let zoom = Self("zoom")
    static let editor = Self("editor")
    static let syncScrolling = Self("syncScrolling")
    static let openInEditor = Self("openInEditor")
    static let share = Self("share")
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation,
    NSSharingServicePickerToolbarItemDelegate
{
    private let recents = RecentFiles()
    private let sidebar: SidebarViewController
    private let editor = EditorViewController()
    private let sidebarItem: NSSplitViewItem
    private let editorItem: NSSplitViewItem
    private let splitView: NSSplitView
    /// The width of the editor when last shown.
    private var editorWidth: CGFloat?
    private let preview = PreviewViewController()
    /// Whether scrolling the editor or the preview scrolls the other.
    private var syncScrolling = true
    private var editorTopLine: (url: URL, line: Int)?
    /// The source line at the top of the preview, once scrolled away from the top.
    private var previewTopLine: Int?
    private var findItem: NSSearchToolbarItem?
    private var syncScrollingItem: NSToolbarItem?
    private let zoomControl = NSSegmentedControl(
        labels: ["−", "100%", "+"], trackingMode: .momentary, target: nil, action: nil)

    init() {
        sidebar = SidebarViewController(recents: recents)
        let split = NSSplitViewController()
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        editorItem = NSSplitViewItem(viewController: editor)
        editorItem.canCollapse = true
        editorItem.minimumThickness = 320
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(editorItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: preview))
        split.splitView.autosaveName = "MainSplitView"
        splitView = split.splitView
        // Nothing to list yet on first launch: start with the start page alone.
        if recents.urls.isEmpty { sidebarItem.isCollapsed = true }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1100, height: 800))
        window.title = "mdpeek"
        window.initialFirstResponder = preview.focusView
        window.center()
        window.setFrameAutosaveName("MainWindow")
        super.init(window: window)
        window.delegate = self
        // Loading the split view restores the state it saved of every item; the editor starts
        // closed regardless.
        editorItem.isCollapsed = true

        zoomControl.target = self
        zoomControl.action = #selector(zoomControlClicked(_:))
        zoomControl.setWidth(52, forSegment: 1)
        zoomControl.setToolTip("Zoom Out", forSegment: 0)
        zoomControl.setToolTip("Actual Size", forSegment: 1)
        zoomControl.setToolTip("Zoom In", forSegment: 2)

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        sidebar.onSelect = { [weak self] url in self?.show(url) }
        sidebar.onSelectHeading = { [weak self] id in self?.preview.scrollToHeading(id) }
        preview.onOpenMarkdown = { [weak self] url in self?.open(url) }
        preview.onOutlineChange = { [weak self] headings in self?.sidebar.setHeadings(headings) }
        preview.onSectionChange = { [weak self] id in self?.sidebar.setCurrentHeading(id) }
        preview.onZoomChange = { [weak self] zoom in
            self?.updateZoomLabel(zoom)
            self?.editor.zoom = zoom
        }
        editor.onScroll = { [weak self] url, line in
            self?.editorTopLine = (url, line)
            self?.updateSourceLine()
        }
        editor.onQuit = { [weak self] in self?.setEditorVisible(false) }
        preview.onScroll = { [weak self] line in self?.previewScrolled(to: line) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func open(_ url: URL) {
        let url = url.standardizedFileURL
        if show(url) {
            recents.add(url)
        }
    }

    @discardableResult
    private func show(_ url: URL) -> Bool {
        do {
            try preview.show(url)
        } catch {
            sidebar.syncSelection()
            presentError(error)
            return false
        }
        window?.title = url.lastPathComponent
        window?.subtitle = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        window?.representedURL = url
        sidebar.select(url)
        previewTopLine = nil
        if !editorItem.isCollapsed {
            editor.open(url, atLine: nil)
        }
        updateSourceLine()
        return true
    }

    private func setEditorVisible(_ visible: Bool) {
        if visible {
            editorItem.isCollapsed = false
            splitView.layoutSubtreeIfNeeded()
            // At its last width, or the first time sharing the space beside the sidebar evenly
            // with the preview.
            let start = sidebarItem.isCollapsed ? 0 : sidebar.view.frame.maxX + splitView.dividerThickness
            splitView.setPosition(start + (editorWidth ?? (splitView.bounds.maxX - start) / 2), ofDividerAt: 1)
            if let url = preview.documentURL {
                // Where the preview is, if scrolled; otherwise where Neovim shows the file.
                let line = syncScrolling ? previewTopLine : nil
                if let line { editorTopLine = (url, line) }
                editor.open(url, atLine: line)
            }
        } else {
            editorWidth = editor.view.frame.width
            editorItem.isCollapsed = true
        }
        syncScrollingItem?.isHidden = !visible
        window?.makeFirstResponder(visible ? editor.focusView : preview.focusView)
        updateSourceLine()
    }

    private func updateSourceLine() {
        guard syncScrolling, !editorItem.isCollapsed, let editorTopLine, let url = preview.documentURL,
            editorTopLine.url.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
        else {
            preview.sourceLine = nil
            return
        }
        preview.sourceLine = editorTopLine.line
        previewTopLine = editorTopLine.line
    }

    private func previewScrolled(to line: Int) {
        previewTopLine = line
        guard syncScrolling, !editorItem.isCollapsed, let url = preview.documentURL else { return }
        editorTopLine = (url, line)
        editor.scroll(url, toLine: line)
    }

    /// Asks whether to discard unsaved changes in the editor, if there are any. Returns
    /// whether to go ahead, after ending Neovim.
    func confirmDiscardingEditorChanges() -> Bool {
        guard editor.hasUnsavedChanges else { return true }
        showWindow(nil)
        if editorItem.isCollapsed { setEditorVisible(true) }
        let alert = NSAlert()
        alert.messageText = "Discard the unsaved changes in the editor?"
        alert.informativeText = "Neovim has unsaved changes. Save them with :w first to keep them."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes").hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        editor.stop()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmDiscardingEditorChanges()
    }

    // MARK: Actions

    @objc func toggleEditor(_ sender: Any?) {
        setEditorVisible(editorItem.isCollapsed)
    }

    @objc func toggleSyncScrolling(_ sender: Any?) {
        syncScrolling.toggle()
        updateSyncScrollingItem()
        updateSourceLine()
    }

    private func updateSyncScrollingItem() {
        let title = syncScrolling ? "Scroll the Editor and Preview Separately" : "Scroll the Editor and Preview Together"
        syncScrollingItem?.image = NSImage(systemSymbolName: syncScrolling ? "lock" : "lock.open", accessibilityDescription: title)
        syncScrollingItem?.toolTip = title
    }

    @objc func zoomIn(_ sender: Any?) { preview.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { preview.zoomOut() }
    @objc func actualSize(_ sender: Any?) { preview.resetZoom() }

    @objc private func zoomControlClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: preview.zoomOut()
        case 2: preview.zoomIn()
        default: preview.resetZoom()
        }
    }

    private func updateZoomLabel(_ zoom: CGFloat) {
        zoomControl.setLabel("\(Int((zoom * 100).rounded()))%", forSegment: 1)
    }

    @objc func showFind(_ sender: Any?) {
        findItem?.beginSearchInteraction()
    }

    @objc func findNext(_ sender: Any?) {
        preview.find(findItem?.searchField.stringValue ?? "")
    }

    @objc func findPrevious(_ sender: Any?) {
        preview.find(findItem?.searchField.stringValue ?? "", backwards: true)
    }

    @objc private func findFieldChanged(_ sender: NSSearchField) {
        let backwards = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        preview.find(sender.stringValue, backwards: backwards)
    }

    @objc func printDocument(_ sender: Any?) {
        preview.printDocument()
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let url = preview.documentURL, let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + ".pdf"
        panel.directoryURL = url.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self, response == .OK, let target = panel.url else { return }
                // Let the sheet close before the print operation starts its own.
                Task { @MainActor in self.preview.exportPDF(to: target) }
            }
        }
    }

    /// Opens the file in the app the system uses for it, or, if that is mdpeek, in the next
    /// app that can edit it.
    @objc func openInEditor(_ sender: Any?) {
        guard let url = preview.documentURL else { return }
        let workspace = NSWorkspace.shared
        let ownIdentifier = Bundle.main.bundleIdentifier
        let isOwn = { (app: URL) in Bundle(url: app)?.bundleIdentifier == ownIdentifier }
        var app = workspace.urlForApplication(toOpen: url).flatMap { isOwn($0) ? nil : $0 }
        app = app ?? workspace.urlsForApplications(toOpen: url).first { !isOwn($0) }
        app = app ?? workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")
        guard let app else {
            NSSound.beep()
            return
        }
        workspace.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(printDocument(_:)), #selector(exportPDF(_:)), #selector(openInEditor(_:)),
            #selector(showFind(_:)), #selector(findNext(_:)), #selector(findPrevious(_:)), #selector(toggleEditor(_:)):
            return preview.documentURL != nil
        case #selector(toggleSyncScrolling(_:)):
            menuItem.state = syncScrolling ? .on : .off
            return !editorItem.isCollapsed
        default:
            return true
        }
    }

    // MARK: NSSharingServicePickerToolbarItemDelegate

    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        preview.documentURL.map { [$0] } ?? []
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .find, .zoom, .syncScrolling, .editor, .openInEditor, .share]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .find:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Find"
            item.preferredWidthForSearchField = 200
            item.searchField.placeholderString = "Find"
            item.searchField.sendsWholeSearchString = true
            item.searchField.target = self
            item.searchField.action = #selector(findFieldChanged(_:))
            findItem = item
            return item
        case .zoom:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Zoom"
            item.view = zoomControl
            return item
        case .editor:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Editor"
            item.toolTip = "Toggle Editor"
            item.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Toggle Editor")
            item.isBordered = true
            item.target = self
            item.action = #selector(toggleEditor(_:))
            return item
        case .syncScrolling:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Sync Scrolling"
            item.isBordered = true
            item.isHidden = editorItem.isCollapsed
            item.target = self
            item.action = #selector(toggleSyncScrolling(_:))
            syncScrollingItem = item
            updateSyncScrollingItem()
            return item
        case .openInEditor:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Open in Editor"
            item.toolTip = "Open in Editor"
            item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Open in Editor")
            item.isBordered = true
            item.target = self
            item.action = #selector(openInEditor(_:))
            return item
        case .share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Share"
            item.delegate = self
            return item
        default:
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }
    }
}
