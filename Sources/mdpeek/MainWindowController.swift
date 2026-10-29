import AppKit
import UniformTypeIdentifiers

private extension NSToolbarItem.Identifier {
    static let find = Self("find")
    static let editor = Self("editor")
    static let more = Self("more")
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation,
    NSMenuDelegate
{
    private let recents = RecentFiles()
    private let sidebar: SidebarViewController
    private let editor = EditorViewController()
    private let sidebarItem: NSSplitViewItem
    private let editorItem: NSSplitViewItem
    private let content: ContentViewController
    private var statusBar: StatusBarView { content.statusBar }
    /// The split view of the editor and the preview.
    private var editorSplitView: NSSplitView { content.split.splitView }
    /// The width of the editor when last shown.
    private var editorWidth: CGFloat?
    private let preview = PreviewViewController()
    /// Whether the editor and the preview scroll together and share a zoom level. While
    /// unlinked, zooming applies to whichever has focus.
    private var linked = true
    private var editorTopLine: (url: URL, line: Int)?
    private var editorCursorLine: (url: URL, line: Int)?
    /// Whether the preview outlines the block holding Neovim's cursor, while linked.
    private var highlightsCursor = UserDefaults.standard.object(forKey: "highlightCursor") as? Bool ?? true {
        didSet { UserDefaults.standard.set(highlightsCursor, forKey: "highlightCursor") }
    }
    /// The source line at the top of the preview, once scrolled away from the top.
    private var previewTopLine: Int?
    private var findButton: NSButton?
    private var editorButton: NSButton?
    /// The picker behind the More menu's Share item.
    private var sharePicker: NSSharingServicePicker?

    init() {
        sidebar = SidebarViewController(recents: recents)
        let split = NSSplitViewController()
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        editorItem = NSSplitViewItem(viewController: editor)
        editorItem.canCollapse = true
        editorItem.minimumThickness = 320
        content = ContentViewController(items: [editorItem, NSSplitViewItem(viewController: preview)])
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: content))
        // Not "MainSplitView", which saved the layout of three panes side by side.
        split.splitView.autosaveName = "SidebarSplitView"
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

        statusBar.onZoom = { [weak self] step in self?.changeZoom(step) }
        statusBar.onToggleLinked = { [weak self] in self?.toggleLinked(nil) }
        updateZoomLabel()

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        sidebar.onSelect = { [weak self] url in self?.show(url) }
        sidebar.onSelectHeading = { [weak self] id in self?.preview.scrollToHeading(id) }
        preview.onOpenMarkdown = { [weak self] url in self?.open(url) }
        preview.onOutlineChange = { [weak self] headings in self?.sidebar.setHeadings(headings) }
        preview.onSectionChange = { [weak self] id in self?.sidebar.setCurrentHeading(id) }
        preview.onWordCountChange = { [weak self] words in self?.statusBar.setWordCount(words) }
        preview.onSectionTextChange = { [weak self] text in self?.statusBar.setSection(text) }
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
        editor.onUnsavedChangesChange = { [weak self] _ in self?.updateEditedState() }
        editor.onCursorMove = { [weak self] url, line in
            self?.editorCursorLine = (url, line)
            self?.updateCursorLine()
        }
        preview.onScroll = { [weak self] line in self?.previewScrolled(to: line) }
        preview.onFindBarChange = { [weak self] shown in self?.findButton?.state = shown ? .on : .off }
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
        window?.representedURL = url
        updateEditedState()
        sidebar.select(url)
        previewTopLine = nil
        statusBar.isActive = true
        updateEditorButton()
        updateCursorLine()
        if !editorItem.isCollapsed {
            editor.open(url, atLine: nil)
        }
        updateSourceLine()
        return true
    }

    /// While Neovim has unsaved changes, marks the window as edited, adds "— Edited" to the
    /// subtitle, and tells the preview it shows the last save.
    private func updateEditedState() {
        let edited = editor.hasUnsavedChanges
        window?.isDocumentEdited = edited
        if let url = preview.documentURL {
            let folder = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            window?.subtitle = edited ? "\(folder) — Edited" : folder
        }
        preview.showsUnsavedNotice = edited
    }

    private func setEditorVisible(_ visible: Bool) {
        if visible {
            editorItem.isCollapsed = false
            editorSplitView.layoutSubtreeIfNeeded()
            // At its last width, or the first time sharing the space evenly with the preview.
            editorSplitView.setPosition(editorWidth ?? editorSplitView.bounds.width / 2, ofDividerAt: 0)
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
        updateEditorButton()
        updateLinkToggle()
        updateCursorLine()
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

    /// Outlines, in the preview, the block holding Neovim's cursor: while linked, with the editor
    /// shown on the same file, unless turned off in the View menu.
    private func updateCursorLine() {
        guard highlightsCursor, linked, !editorItem.isCollapsed, let editorCursorLine, let url = preview.documentURL,
            editorCursorLine.url.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
        else {
            preview.cursorLine = nil
            return
        }
        preview.cursorLine = editorCursorLine.line
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
        updateLinkToggle()
        updateCursorLine()
        if linked {
            syncToFocusedPane()
        } else {
            updateSourceLine()
        }
        updateZoomLabel()
    }

    @objc func toggleCursorHighlight(_ sender: Any?) {
        highlightsCursor.toggle()
        updateCursorLine()
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
            Task {
                // Asks the page: previewTopLine only changes as the preview is scrolled, so it
                // misses reloads that moved the text since. No line yet: the preview is at the top.
                let line = await self.preview.sourceLineAtTop() ?? self.previewTopLine ?? 1
                guard self.linked, self.preview.documentURL == url else { return }
                self.previewTopLine = line
                self.editorTopLine = (url, line)
                self.editor.scroll(url, toLine: line)
            }
        }
    }

    /// Shows the link toggle while the editor is shown.
    private func updateLinkToggle() {
        statusBar.linkState = editorItem.isCollapsed ? nil : linked
    }

    /// Shows the editor button pressed while the editor is shown.
    private func updateEditorButton() {
        guard let editorButton else { return }
        let shown = !editorItem.isCollapsed
        editorButton.state = shown ? .on : .off
        editorButton.toolTip = shown ? "Hide Editor" : "Show Editor"
        editorButton.setAccessibilityLabel(editorButton.toolTip)
        editorButton.isEnabled = shown || preview.documentURL != nil
    }

    @objc func zoomIn(_ sender: Any?) { changeZoom(.larger) }
    @objc func zoomOut(_ sender: Any?) { changeZoom(.smaller) }
    @objc func actualSize(_ sender: Any?) { changeZoom(.actualSize) }

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
        statusBar.setZoom(zoomsEditor ? editor.zoom : preview.zoom)
    }

    @objc func showFind(_ sender: Any?) {
        preview.showFindBar()
    }

    @objc private func toggleFindBar(_ sender: Any?) {
        if preview.isFindBarShown {
            preview.hideFindBar()
        } else if preview.documentURL != nil {
            preview.showFindBar()
        } else {
            findButton?.state = .off
        }
    }

    @objc func findNext(_ sender: Any?) {
        preview.findNext(backwards: false)
    }

    @objc func findPrevious(_ sender: Any?) {
        preview.findNext(backwards: true)
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
        case #selector(toggleCursorHighlight(_:)):
            menuItem.state = highlightsCursor ? .on : .off
            return true
        case #selector(toggleLinked(_:)):
            menuItem.state = linked ? .on : .off
            return !editorItem.isCollapsed
        default:
            return true
        }
    }

    // MARK: NSMenuDelegate

    /// Fills the toolbar's More menu, whose Share item offers the services for the current file.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Open in Editor", action: #selector(openInEditor(_:)), keyEquivalent: "").target = self
        sharePicker = preview.documentURL.map { NSSharingServicePicker(items: [$0]) }
        menu.addItem(sharePicker?.standardShareMenuItem ?? NSMenuItem(title: "Share", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Export as PDF…", action: #selector(exportPDF(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Print…", action: #selector(printDocument(_:)), keyEquivalent: "").target = self
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .find, .editor, .more]
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
            let button = NSButton(
                image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Find")!,
                target: self, action: #selector(toggleFindBar(_:)))
            button.bezelStyle = .toolbar
            button.setButtonType(.pushOnPushOff)
            button.toolTip = "Find"
            findButton = button
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Find"
            item.view = button
            return item
        case .editor:
            let button = NSButton(
                image: NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: nil)!,
                target: self, action: #selector(toggleEditor(_:)))
            button.bezelStyle = .toolbar
            button.setButtonType(.pushOnPushOff)
            editorButton = button
            updateEditorButton()
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Editor"
            item.view = button
            return item
        case .more:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "More"
            item.toolTip = "More"
            item.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
            item.showsIndicator = false
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
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
