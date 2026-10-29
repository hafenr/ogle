import AppKit
import WebKit

/// A heading of the displayed document, as listed in the sidebar's outline.
struct Heading: Equatable {
    let id: String
    let level: Int
    let title: String
}

@MainActor
final class PreviewViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private let pageURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web")!
    private var webView: DropTargetWebView!
    private let statusBar = StatusBarView()
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

    var documentURL: URL? { document?.url }
    /// The source line kept at the top of the view while it follows the editor.
    var sourceLine: Int? {
        didSet {
            guard isPageLoaded else { return }
            webView.callAsyncJavaScript(
                "mdpeek.followSourceLine(line)", arguments: ["line": sourceLine.map(NSNumber.init) ?? NSNull()],
                in: nil, in: .page)
        }
    }
    var zoom: CGFloat { webView.pageZoom }
    /// The view that should have keyboard focus, so the document scrolls with the keyboard.
    var focusView: NSView {
        loadViewIfNeeded()
        return webView
    }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: "mdpeek")
        webView = DropTargetWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.onDropMarkdown = { [weak self] url in self?.onOpenMarkdown?(url) }
        webView.allowsMagnification = true
        webView.isInspectable = true

        let container = NSView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        container.addSubview(statusBar)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
        // Read access to the whole file system so documents can reference images anywhere.
        webView.loadFileURL(pageURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    func show(_ url: URL) throws {
        document = (url, try Data(contentsOf: url))
        sourceLine = nil
        watcher = FileWatcher(url: url) { [weak self] in self?.reload() }
        statusBar.isActive = true
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
            "await mdpeek.render(html, baseURL, preserveScroll)",
            arguments: [
                "html": Markdown.html(from: document.data),
                "baseURL": document.url.deletingLastPathComponent().absoluteString,
                "preserveScroll": preserveScroll,
            ],
            in: nil, in: .page
        ) { result in
            if case .failure(let error) = result {
                NSLog("mdpeek: rendering %@ failed: %@", document.url.path, String(describing: error))
            }
        }
    }

    func scrollToHeading(_ id: String) {
        webView.callAsyncJavaScript("mdpeek.scrollToHeading(id)", arguments: ["id": id], in: nil, in: .page)
    }

    // MARK: Find

    func find(_ string: String, backwards: Bool = false) {
        guard !string.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        webView.find(string, configuration: configuration) { result in
            if !result.matchFound { NSSound.beep() }
        }
    }

    // MARK: Zoom

    func changeZoom(_ step: Zoom.Step) {
        // Actual size also undoes pinch magnification.
        if step == .actualSize { webView.magnification = 1 }
        webView.pageZoom = step.apply(to: webView.pageZoom)
        onZoomChange?(webView.pageZoom)
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
            statusBar.setWordCount((body["words"] as? NSNumber)?.intValue ?? 0)
            onOutlineChange?(headings)
            updateStatusSection()
        case "section":
            currentHeadingID = body["id"] as? String
            updateStatusSection()
            onSectionChange?(currentHeadingID)
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
            statusBar.setSection(nil)
            return
        }
        statusBar.setSection("\(headings[index].title) · \(index + 1) of \(headings.count)")
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isPageLoaded else { return }
        isPageLoaded = true
        if document == nil {
            webView.callAsyncJavaScript("mdpeek.showWelcome()", in: nil, in: .page)
        } else {
            render(preserveScroll: false)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("mdpeek: loading %@ failed: %@", pageURL.path, String(describing: error))
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
