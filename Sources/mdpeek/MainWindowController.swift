import AppKit
import UniformTypeIdentifiers

private extension NSToolbarItem.Identifier {
    static let find = Self("find")
    static let zoom = Self("zoom")
    static let editor = Self("editor")
    static let link = Self("link")
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
    /// Whether the editor and the preview scroll together and share a zoom level. While
    /// unlinked, zooming applies to whichever has focus.
    private var linked = true
    private var editorTopLine: (url: URL, line: Int)?
    /// The source line at the top of the preview, once scrolled away from the top.
    private var previewTopLine: Int?
    private var findItem: NSSearchToolbarItem?
    private var linkItem: NSToolbarItem?
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

        let window = MainWindow(
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
        window.onFirstResponderChange = { [weak self] in self?.updateZoomLabel() }
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
            guard let self else { return }
            if linked { editor.zoom = zoom }
            updateZoomLabel()
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
                let line = linked ? previewTopLine : nil
                if let line { editorTopLine = (url, line) }
                editor.open(url, atLine: line)
            }
        } else {
            editorWidth = editor.view.frame.width
            editorItem.isCollapsed = true
        }
        linkItem?.isHidden = !visible
        window?.makeFirstResponder(visible ? editor.focusView : preview.focusView)
        updateSourceLine()
    }

    private func updateSourceLine() {
        guard linked, !editorItem.isCollapsed, let editorTopLine, let url = preview.documentURL,
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
        guard linked, !editorItem.isCollapsed, let url = preview.documentURL else { return }
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

    @objc func toggleLinked(_ sender: Any?) {
        linked.toggle()
        updateLinkItem()
        if linked {
            syncToFocusedPane()
        } else {
            updateSourceLine()
        }
        updateZoomLabel()
    }

    /// On linking, brings the other pane to the zoom level and scroll position of the one with
    /// focus, the one the user was working in.
    private func syncToFocusedPane() {
        if editorHasFocus {
            // The editor follows the preview's zoom from here on, so this leaves both at its level.
            preview.setZoom(editor.zoom)
            updateSourceLine()
        } else {
            editor.zoom = preview.zoom
            preview.sourceLine = nil
            guard let url = preview.documentURL else { return }
            // No line yet: the preview is at the top.
            let line = previewTopLine ?? 1
            editorTopLine = (url, line)
            editor.scroll(url, toLine: line)
        }
    }

    private func updateLinkItem() {
        let title = linked ? "Scroll and Zoom the Editor and Preview Separately" : "Scroll and Zoom the Editor and Preview Together"
        linkItem?.image = NSImage(systemSymbolName: linked ? "lock" : "lock.open", accessibilityDescription: title)
        linkItem?.toolTip = title
    }

    @objc func zoomIn(_ sender: Any?) { changeZoom(.larger) }
    @objc func zoomOut(_ sender: Any?) { changeZoom(.smaller) }
    @objc func actualSize(_ sender: Any?) { changeZoom(.actualSize) }

    @objc private func zoomControlClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: changeZoom(.smaller)
        case 2: changeZoom(.larger)
        default: changeZoom(.actualSize)
        }
    }

    private var editorHasFocus: Bool {
        guard !editorItem.isCollapsed, let responder = window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: editor.view)
    }

    /// Whether zooming applies to the editor alone: while unlinked, with the editor focused.
    private var zoomsEditor: Bool { !linked && editorHasFocus }

    private func changeZoom(_ step: Zoom.Step) {
        if zoomsEditor {
            editor.zoom = step.apply(to: editor.zoom)
            updateZoomLabel()
        } else {
            // Reports the change, which the editor follows while linked.
            preview.changeZoom(step)
        }
    }

    /// Shows the zoom level of what zooming applies to.
    private func updateZoomLabel() {
        let zoom = zoomsEditor ? editor.zoom : preview.zoom
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
        case #selector(toggleLinked(_:)):
            menuItem.state = linked ? .on : .off
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
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .find, .zoom, .link, .editor, .openInEditor, .share]
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
        case .link:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Link Editor"
            item.isBordered = true
            item.isHidden = editorItem.isCollapsed
            item.target = self
            item.action = #selector(toggleLinked(_:))
            linkItem = item
            updateLinkItem()
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

/// Reports changes of the first responder, which decide whether zooming applies to the editor.
private final class MainWindow: NSWindow {
    var onFirstResponderChange: (() -> Void)?

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let changed = super.makeFirstResponder(responder)
        if changed { onFirstResponderChange?() }
        return changed
    }
}
