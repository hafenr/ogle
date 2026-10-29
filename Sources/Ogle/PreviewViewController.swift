import AppKit
import WebKit

/// A heading of the displayed document, as listed in the sidebar's outline.
struct Heading: Equatable {
    let id: String
    let level: Int
    let title: String
}

/// A recently opened file, as the start page lists it.
struct RecentFile {
    let path: String
    let name: String
    let folder: String
    /// When it was opened: "now", "2h", "Yesterday", …
    let when: String
}

@MainActor
final class PreviewViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private let pageURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web")!
    private var webView: DropTargetWebView!
    private let findBar = FindBarView()
    /// The web view's top: at the top of the view, under the toolbar, or below the find bar.
    private var webViewTop: NSLayoutConstraint!
    private var webViewBelowFindBar: NSLayoutConstraint!
    private var isPageLoaded = false
    private var document: (url: URL, data: Data)?
    private var watcher: FileWatcher?
    private(set) var headings: [Heading] = []
    private(set) var currentHeadingID: String?

    /// Called for links to other Markdown files, and for Markdown files dropped on the view.
    var onOpenMarkdown: ((URL) -> Void)?
    var onOutlineChange: (([Heading]) -> Void)?
    var onSectionChange: ((String?) -> Void)?
    /// Called with the source line at the top of the view as the user scrolls it.
    var onScroll: ((Int) -> Void)?
    var onZoomChange: ((CGFloat) -> Void)?
    var onWordCountChange: ((Int) -> Void)?
    /// Called with the current section as the status bar shows it: "Download · 3 of 9".
    var onSectionTextChange: ((String?) -> Void)?
    var onFindBarChange: ((Bool) -> Void)?
    /// Called with a file picked on the start page and whether to show the editor too.
    var onOpenRecent: ((URL, Bool) -> Void)?
    var onRemoveRecent: ((URL) -> Void)?
    /// The recent files the start page lists.
    var recentFiles: [RecentFile] = [] {
        didSet { sendRecentFiles() }
    }

    var documentURL: URL? { document?.url }
    /// The source line kept at the top of the view while it follows the editor.
    var sourceLine: Int? {
        didSet {
            guard isPageLoaded else { return }
            webView.callAsyncJavaScript(
                "ogle.followSourceLine(line)", arguments: ["line": sourceLine.map(NSNumber.init) ?? NSNull()],
                in: nil, in: .page)
        }
    }
    /// The source line of the editor's cursor, whose block the page outlines, if any.
    var cursorLine: Int? {
        didSet {
            guard isPageLoaded, cursorLine != oldValue else { return }
            webView.callAsyncJavaScript(
                "ogle.setCursorLine(line)", arguments: ["line": cursorLine.map(NSNumber.init) ?? NSNull()],
                in: nil, in: .page)
        }
    }
    /// Whether to note that the preview shows the last save while the editor has unsaved changes.
    var showsUnsavedNotice = false {
        didSet {
            guard isPageLoaded, showsUnsavedNotice != oldValue else { return }
            webView.callAsyncJavaScript(
                "ogle.showUnsavedNotice(shown)", arguments: ["shown": showsUnsavedNotice], in: nil, in: .page)
        }
    }
    var zoom: CGFloat {
        loadViewIfNeeded()
        return webView.pageZoom
    }
    /// The view that should have keyboard focus, so the document scrolls with the keyboard.
    var focusView: NSView {
        loadViewIfNeeded()
        return webView
    }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: "ogle")
        webView = DropTargetWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.onDropMarkdown = { [weak self] url in self?.onOpenMarkdown?(url) }
        webView.allowsMagnification = true
        webView.isInspectable = true

        let container = NSView()
        findBar.isHidden = true
        findBar.onChange = { [weak self] in self?.findChanged() }
        findBar.onNext = { [weak self] backwards in self?.findNext(backwards: backwards) }
        findBar.onDone = { [weak self] in self?.hideFindBar() }
        for view in [webView!, findBar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        webViewTop = webView.topAnchor.constraint(equalTo: container.topAnchor)
        webViewBelowFindBar = webView.topAnchor.constraint(equalTo: findBar.bottomAnchor)
        NSLayoutConstraint.activate([
            findBar.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            findBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webViewTop,
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
        // Read access to the whole file system so documents can reference images anywhere.
        webView.loadFileURL(pageURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    func show(_ url: URL) throws {
        document = (url, try Data(contentsOf: url))
        sourceLine = nil
        watcher = FileWatcher(url: url) { [weak self] in self?.reload() }
        render(preserveScroll: false)
    }

    private func reload() {
        guard let document else { return }
        // Atomic saves briefly remove the file; the event for the replacement follows.
        guard FileManager.default.fileExists(atPath: document.url.path) else { return }
        let data: Data
        do {
            data = try Data(contentsOf: document.url)
        } catch {
            presentError(error)
            return
        }
        guard data != document.data else { return }
        self.document = (document.url, data)
        render(preserveScroll: true)
    }

    private func render(preserveScroll: Bool) {
        guard isPageLoaded, let document else { return }
        webView.callAsyncJavaScript(
            "await ogle.render(html, baseURL, preserveScroll)",
            arguments: [
                "html": Markdown.html(from: document.data),
                "baseURL": document.url.deletingLastPathComponent().absoluteString,
                "preserveScroll": preserveScroll,
            ],
            in: nil, in: .page
        ) { result in
            if case .failure(let error) = result {
                NSLog("ogle: rendering %@ failed: %@", document.url.path, String(describing: error))
            }
        }
    }

    /// The source line at the top of the view, as the page computes it now.
    func sourceLineAtTop() async throws -> Int? {
        guard isPageLoaded, document != nil else { return nil }
        let line = try await webView.callAsyncJavaScript("return ogle.sourceLineAtTop()", contentWorld: .page)
        return (line as? NSNumber)?.intValue
    }

    private func sendRecentFiles() {
        guard isPageLoaded else { return }
        let files = recentFiles.map { ["path": $0.path, "name": $0.name, "folder": $0.folder, "when": $0.when] }
        webView.callAsyncJavaScript("ogle.setRecentFiles(files)", arguments: ["files": files], in: nil, in: .page)
    }

    /// Focuses the search field of the start page's Open Quickly card.
    func focusOpenQuickly() {
        guard isPageLoaded, document == nil else { return }
        view.window?.makeFirstResponder(webView)
        webView.callAsyncJavaScript("ogle.focusOpenQuickly()", in: nil, in: .page)
    }

    func scrollToHeading(_ id: String) {
        webView.callAsyncJavaScript("ogle.scrollToHeading(id)", arguments: ["id": id], in: nil, in: .page)
    }

    // MARK: Find

    var isFindBarShown: Bool { !findBar.isHidden }

    /// Shows the find bar, focused, with its text selected.
    func showFindBar() {
        if findBar.isHidden {
            findBar.isHidden = false
            webViewTop.isActive = false
            webViewBelowFindBar.isActive = true
            onFindBarChange?(true)
            if !findBar.query.isEmpty { findChanged() }
        }
        findBar.focus()
    }

    /// Hides the find bar and the highlighted matches.
    func hideFindBar() {
        guard !findBar.isHidden else { return }
        findBar.isHidden = true
        webViewBelowFindBar.isActive = false
        webViewTop.isActive = true
        if isPageLoaded {
            webView.callAsyncJavaScript("ogle.clearFind()", in: nil, in: .page)
        }
        view.window?.makeFirstResponder(webView)
        onFindBarChange?(false)
    }

    /// Goes to the next (or previous) match, or shows the find bar if there is nothing to find.
    func findNext(backwards: Bool) {
        guard !findBar.isHidden, !findBar.query.isEmpty else {
            showFindBar()
            return
        }
        runFind("return ogle.findNext(backwards)", arguments: ["backwards": backwards])
    }

    private func findChanged() {
        runFind("return ogle.find(query, caseSensitive)", arguments: ["query": findBar.query, "caseSensitive": findBar.isCaseSensitive])
    }

    private func runFind(_ script: String, arguments: [String: Any]) {
        guard isPageLoaded, document != nil else { return }
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { [weak self] result in
            switch result {
            case .success(let value):
                guard let value = value as? [String: Any] else { return }
                MainActor.assumeIsolated { self?.showFindResult(value) }
            case .failure(let error):
                NSLog("ogle: finding failed: %@", String(describing: error))
            }
        }
    }

    private func showFindResult(_ result: [String: Any]) {
        let index = (result["index"] as? NSNumber)?.intValue ?? 0
        let count = (result["count"] as? NSNumber)?.intValue ?? 0
        findBar.setResult(index: index, count: count)
        if count == 0 && !findBar.query.isEmpty { NSSound.beep() }
    }

    // MARK: Zoom

    func changeZoom(_ step: Zoom.Step) {
        // Actual size also undoes pinch magnification.
        if step == .actualSize { webView.magnification = 1 }
        setZoom(step.apply(to: webView.pageZoom))
    }

    func setZoom(_ zoom: CGFloat) {
        webView.pageZoom = zoom
        onZoomChange?(zoom)
    }

    // MARK: Printing

    func printDocument() {
        runPrintOperation(with: NSPrintInfo.shared, showPanels: true)
    }

    /// Saves the document as a paginated PDF, as printing would.
    func exportPDF(to url: URL) {
        guard let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo else { return }
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = url
        runPrintOperation(with: printInfo, showPanels: false)
    }

    private func runPrintOperation(with printInfo: NSPrintInfo, showPanels: Bool) {
        guard document != nil, let window = view.window else { return }
        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = showPanels
        operation.showsProgressPanel = true
        // WKWebView's print view needs a frame, or it prints blank pages.
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "outline":
            let items = body["headings"] as? [[String: Any]] ?? []
            headings = items.compactMap { item in
                guard let id = item["id"] as? String, let title = item["title"] as? String,
                    let level = (item["level"] as? NSNumber)?.intValue
                else { return nil }
                return Heading(id: id, level: level, title: title)
            }
            onWordCountChange?((body["words"] as? NSNumber)?.intValue ?? 0)
            onOutlineChange?(headings)
            updateStatusSection()
        case "section":
            currentHeadingID = body["id"] as? String
            updateStatusSection()
            onSectionChange?(currentHeadingID)
        case "find":
            guard !findBar.isHidden else { return }
            let index = (body["index"] as? NSNumber)?.intValue ?? 0
            let count = (body["count"] as? NSNumber)?.intValue ?? 0
            findBar.setResult(index: index, count: count)
        case "escape":
            hideFindBar()
        case "openRecent":
            guard let path = body["path"] as? String else { return }
            onOpenRecent?(URL(fileURLWithPath: path), body["withEditor"] as? Bool ?? false)
        case "removeRecent":
            guard let path = body["path"] as? String else { return }
            onRemoveRecent?(URL(fileURLWithPath: path))
        case "scroll":
            guard let line = (body["line"] as? NSNumber)?.intValue else { return }
            onScroll?(line)
        case "open":
            NSApp.sendAction(#selector(AppDelegate.openDocument(_:)), to: nil, from: self)
        case "copy":
            guard let text = body["text"] as? String else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if body["kind"] as? String == "svg" {
                pasteboard.setData(Data(text.utf8), forType: NSPasteboard.PasteboardType("public.svg-image"))
            }
            pasteboard.setString(text, forType: .string)
        default:
            break
        }
    }

    private func updateStatusSection() {
        guard let index = headings.firstIndex(where: { $0.id == currentHeadingID }) else {
            onSectionTextChange?(nil)
            return
        }
        onSectionTextChange?("\(headings[index].title) · \(index + 1) of \(headings.count)")
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isPageLoaded else { return }
        isPageLoaded = true
        sendRecentFiles()
        if showsUnsavedNotice {
            webView.callAsyncJavaScript("ogle.showUnsavedNotice(true)", in: nil, in: .page)
        }
        if let cursorLine {
            webView.callAsyncJavaScript("ogle.setCursorLine(line)", arguments: ["line": cursorLine], in: nil, in: .page)
        }
        if document == nil {
            webView.callAsyncJavaScript("ogle.showWelcome()", in: nil, in: .page)
        } else {
            render(preserveScroll: false)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("ogle: loading %@ failed: %@", pageURL.path, String(describing: error))
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        // In-page anchors (headings, footnotes) are fragment navigations within index.html.
        if url.isFileURL && url.path == pageURL.path { return .allow }
        guard navigationAction.navigationType == .linkActivated else { return .cancel }
        if url.isFileURL && Markdown.fileExtensions.contains(url.pathExtension.lowercased()) {
            onOpenMarkdown?(url)
        } else {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }
}

/// Opens Markdown files dropped on the view. WebKit does not load dropped files in apps built
/// against current SDKs, so the drop is handled here instead of by the page.
private final class DropTargetWebView: WKWebView {
    var onDropMarkdown: ((URL) -> Void)?

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingUpdated(sender)
        return markdownURL(in: sender) == nil ? operation : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = markdownURL(in: sender) else { return super.performDragOperation(sender) }
        // Ends the page's side of the drag, so it removes its drop highlight.
        super.draggingExited(sender)
        onDropMarkdown?(url)
        return true
    }

    private func markdownURL(in info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first { Markdown.fileExtensions.contains($0.pathExtension.lowercased()) }
    }
}

/// Forwards script messages without the user content controller retaining the view controller.
@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
