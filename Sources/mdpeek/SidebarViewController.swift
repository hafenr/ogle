import AppKit

/// The outline of the current document, or the recently opened files: an "Outline | Files"
/// switch above a filter field and the list.
@MainActor
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {
    private enum Mode: Int {
        case outline, files
    }

    private enum Row {
        case file(URL)
        case heading(Heading)
    }

    private let recents: RecentFiles
    private let modeControl = NSSegmentedControl(labels: ["Outline", "Files"], trackingMode: .selectOne, target: nil, action: nil)
    private let filterField = NSSearchField()
    private let tableView = NSTableView()
    private let fileMenu = NSMenu()
    private var mode = Mode.files
    private var rows: [Row] = []
    private var headings: [Heading] = []
    private var currentHeadingID: String?
    private var current: URL?
    private var isSyncingSelection = false
    var onSelect: ((URL) -> Void)?
    var onSelectHeading: ((String) -> Void)?

    init(recents: RecentFiles) {
        self.recents = recents
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        modeControl.segmentDistribution = .fillEqually
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.setAccessibilityLabel("Sidebar content")

        filterField.sendsSearchStringImmediately = true
        filterField.target = self
        filterField.action = #selector(filterChanged)
        filterField.controlSize = .regular

        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Main")))
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        fileMenu.addItem(withTitle: "Show in Finder", action: #selector(showClickedRowInFinder), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: "Remove from Recents", action: #selector(removeClickedRow), keyEquivalent: "").target = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false

        let container = NSView()
        for view in [modeControl, filterField, scrollView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            modeControl.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 4),
            modeControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            modeControl.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            filterField.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 8),
            filterField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            filterField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        container.frame.size.width = 260
        view = container

        recents.onChange = { [weak self] in self?.reload() }
        setMode(current == nil ? .files : .outline)
    }

    /// Shows the file at `url` as the current one. The first document opened switches to its
    /// outline; after that the sidebar stays on whichever list the user chose.
    func select(_ url: URL) {
        let isFirst = current == nil
        current = url
        if isFirst {
            setMode(.outline)
        } else {
            syncSelection()
        }
    }

    func setHeadings(_ headings: [Heading]) {
        self.headings = headings
        if mode == .outline { reload() }
    }

    func setCurrentHeading(_ id: String?) {
        let previous = currentHeadingID
        currentHeadingID = id
        let changed = rows.indices.filter { index in
            if case .heading(let heading) = rows[index] { return heading.id == previous || heading.id == id }
            return false
        }
        tableView.reloadData(forRowIndexes: IndexSet(changed), columnIndexes: [0])
        if let row = changed.first(where: { isCurrentHeading(rows[$0]) }) {
            tableView.scrollRowToVisible(row)
        }
    }

    private func isCurrentHeading(_ row: Row) -> Bool {
        if case .heading(let heading) = row { return heading.id == currentHeadingID }
        return false
    }

    private func setMode(_ mode: Mode) {
        self.mode = mode
        modeControl.selectedSegment = mode.rawValue
        filterField.stringValue = ""
        filterField.placeholderString = mode == .outline ? "Filter headings" : "Filter files"
        tableView.menu = mode == .files ? fileMenu : nil
        reload()
        if mode == .outline, let row = rows.firstIndex(where: isCurrentHeading) {
            tableView.scrollRowToVisible(row)
        }
    }

    @objc private func modeChanged() {
        setMode(Mode(rawValue: modeControl.selectedSegment) ?? .files)
    }

    @objc private func filterChanged() {
        reload()
    }

    private func reload() {
        let filter = filterField.stringValue.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .outline:
            rows = headings.filter { filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) }.map(Row.heading)
        case .files:
            rows = recents.urls.filter {
                filter.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(filter)
                    || $0.deletingLastPathComponent().path.localizedCaseInsensitiveContains(filter)
            }.map(Row.file)
        }
        isSyncingSelection = true
        tableView.reloadData()
        isSyncingSelection = false
        syncSelection()
    }

    func syncSelection() {
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        let row = rows.firstIndex { row in
            if case .file(let url) = row { return url == current }
            return false
        }
        if let row {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
    }

    private func clickedFile() -> URL? {
        guard rows.indices.contains(tableView.clickedRow), case .file(let url) = rows[tableView.clickedRow] else { return nil }
        return url
    }

    @objc private func rowClicked() {
        guard rows.indices.contains(tableView.clickedRow), case .heading(let heading) = rows[tableView.clickedRow] else { return }
        onSelectHeading?(heading.id)
    }

    @objc private func removeClickedRow() {
        if let url = clickedFile() { recents.remove(url) }
    }

    @objc private func showClickedRowInFinder() {
        if let url = clickedFile() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        clickedFile() != nil
    }

    // MARK: NSTableViewDataSource, NSTableViewDelegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .file = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .file: 40
        case .heading: 28
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .file(let url):
            let cell = tableView.makeView(withIdentifier: FileCell.identifier, owner: nil) as? FileCell ?? FileCell()
            cell.show(url, lastOpened: recents.lastOpened(url))
            return cell
        case .heading(let heading):
            let cell = tableView.makeView(withIdentifier: HeadingCell.identifier, owner: nil) as? HeadingCell ?? HeadingCell()
            let minimumLevel = headings.map(\.level).min() ?? 1
            cell.show(heading, indent: heading.level - minimumLevel, isCurrent: heading.id == currentHeadingID)
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection, rows.indices.contains(tableView.selectedRow),
            case .file(let url) = rows[tableView.selectedRow]
        else { return }
        onSelect?(url)
    }
}

private final class FileCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("FileCell")

    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let directory = NSTextField(labelWithString: "")
    private let date = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        name.lineBreakMode = .byTruncatingMiddle
        directory.lineBreakMode = .byTruncatingHead
        directory.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        directory.textColor = .secondaryLabelColor
        date.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        date.textColor = .secondaryLabelColor
        date.setContentCompressionResistancePriority(.required, for: .horizontal)
        date.setContentHuggingPriority(.required, for: .horizontal)
        for label in [name, directory] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let text = NSStackView(views: [name, directory])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        for view in [icon, text, date] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            date.leadingAnchor.constraint(greaterThanOrEqualTo: text.trailingAnchor, constant: 6),
            date.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            date.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ url: URL, lastOpened: Date?) {
        name.stringValue = url.lastPathComponent
        directory.stringValue = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        date.stringValue = lastOpened.map(Self.shortDate) ?? ""
        toolTip = url.path
    }

    /// "now", "5m", "3h", "Yesterday", "Mon", "Oct 14".
    nonisolated private static func shortDate(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        let calendar = Calendar.current
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if calendar.isDateInToday(date) { return "\(Int(seconds / 3600))h" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if seconds < 6 * 86400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// A heading in the outline. The current one is set in semibold ink on a light pill, marked
/// with a lime dot outlined in ink.
private final class HeadingCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("HeadingCell")

    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()
    private var leading: NSLayoutConstraint!
    private var dotLeading: NSLayoutConstraint!
    private var isCurrent = false

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        wantsLayer = true
        layer?.cornerRadius = 6
        label.lineBreakMode = .byTruncatingTail
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.borderWidth = 1.5
        dot.setAccessibilityElement(false)
        for view in [dot, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        textField = label
        leading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18)
        dotLeading = dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6)
        NSLayoutConstraint.activate([
            leading,
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotLeading,
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ heading: Heading, indent: Int, isCurrent: Bool) {
        self.isCurrent = isCurrent
        label.stringValue = heading.title
        let isTop = indent == 0
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: isCurrent || isTop ? .semibold : .regular)
        label.textColor = isCurrent ? Palette.inkText : .labelColor
        let x = 18 + CGFloat(min(indent, 3)) * 12
        leading.constant = x
        dotLeading.constant = x - 12
        dot.isHidden = !isCurrent
        toolTip = heading.title
        setAccessibilityLabel(isCurrent ? "\(heading.title), current section" : heading.title)
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        layer?.backgroundColor = isCurrent ? resolvedCGColor(Palette.controlFill) : NSColor.clear.cgColor
        layer?.borderWidth = isCurrent ? 1 : 0
        layer?.borderColor = resolvedCGColor(Palette.hairline)
        dot.layer?.backgroundColor = resolvedCGColor(Palette.lime)
        dot.layer?.borderColor = resolvedCGColor(Palette.ink)
    }
}
