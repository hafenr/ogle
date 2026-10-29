import AppKit

/// The recent files in a sheet (⇧⌘O), searchable by name and folder: Return opens the selected
/// file, Option-Return opens it with the editor shown, Command-Delete removes it from the list,
/// Esc closes the sheet. The start page shows the same list in a card.
@MainActor
final class OpenQuicklyViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    /// Called with the file to open and whether to show the editor.
    var onOpen: ((URL, Bool) -> Void)?

    private let recents: RecentFiles
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private var urls: [URL] = []

    init(recents: RecentFiles) {
        self.recents = recents
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let title = NSTextField(labelWithString: "Open Quickly")
        title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let shortcut = NSTextField(labelWithString: "⇧⌘O")
        shortcut.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        shortcut.textColor = .secondaryLabelColor

        searchField.placeholderString = "Search recent files and folders"
        searchField.controlSize = .large
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self

        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Main")))
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.setAccessibilityLabel("Recent files")
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let hints = NSTextField(labelWithString: "↩ Open      ⌥↩ Open with Neovim      ⌘⌫ Remove from list      esc Close")
        hints.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hints.textColor = .secondaryLabelColor
        let separator = NSBox()
        separator.boxType = .separator

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 400))
        for view in [title, shortcut, searchField, scrollView, separator, hints] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 540),
            container.heightAnchor.constraint(equalToConstant: 400),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            shortcut.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            shortcut.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            searchField.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            separator.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hints.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 10),
            hints.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            hints.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        view = container
        reload()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
    }

    private func reload() {
        let filter = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        urls = recents.urls.filter {
            filter.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(filter)
                || $0.deletingLastPathComponent().path.localizedCaseInsensitiveContains(filter)
        }
        tableView.reloadData()
        select(urls.isEmpty ? nil : 0)
    }

    private func select(_ row: Int?) {
        let previous = tableView.selectedRow
        if let row {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
        let rows = IndexSet([previous, tableView.selectedRow].filter { urls.indices.contains($0) })
        tableView.reloadData(forRowIndexes: rows, columnIndexes: [0])
    }

    private func open(row: Int, withEditor: Bool) {
        guard urls.indices.contains(row) else {
            NSSound.beep()
            return
        }
        let url = urls[row]
        dismiss(nil)
        onOpen?(url, withEditor)
    }

    @objc private func rowClicked() {
        open(row: tableView.clickedRow, withEditor: NSApp.currentEvent?.modifierFlags.contains(.option) ?? false)
    }

    // MARK: NSSearchFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        reload()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            if !urls.isEmpty { select(min(tableView.selectedRow + 1, urls.count - 1)) }
        case #selector(NSResponder.moveUp(_:)):
            if !urls.isEmpty { select(max(tableView.selectedRow - 1, 0)) }
        case #selector(NSResponder.insertNewline(_:)):
            open(row: tableView.selectedRow, withEditor: NSApp.currentEvent?.modifierFlags.contains(.option) ?? false)
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            open(row: tableView.selectedRow, withEditor: true)
        case #selector(NSResponder.deleteToBeginningOfLine(_:)):
            guard urls.indices.contains(tableView.selectedRow) else { return false }
            let row = tableView.selectedRow
            recents.remove(urls[row])
            reload()
            if !urls.isEmpty { select(min(row, urls.count - 1)) }
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss(nil)
        default:
            return false
        }
        return true
    }

    // MARK: NSTableViewDataSource, NSTableViewDelegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        urls.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: QuickFileCell.identifier, owner: nil) as? QuickFileCell ?? QuickFileCell()
        let url = urls[row]
        cell.show(url, lastOpened: recents.lastOpened(url), isSelected: row == tableView.selectedRow)
        return cell
    }
}

/// A recent file: name, folder and when it was opened; on lime while selected.
private final class QuickFileCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("QuickFileCell")

    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let folder = NSTextField(labelWithString: "")
    private let date = NSTextField(labelWithString: "")
    private var isSelected = false

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        wantsLayer = true
        layer?.cornerRadius = 8
        icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        folder.font = .systemFont(ofSize: 12)
        folder.lineBreakMode = .byTruncatingHead
        folder.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultHigh - 1, for: .horizontal)
        date.font = .systemFont(ofSize: 12)
        date.setContentCompressionResistancePriority(.required, for: .horizontal)
        date.setContentHuggingPriority(.required, for: .horizontal)
        for view in [icon, name, folder, date] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            folder.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 8),
            folder.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
            date.leadingAnchor.constraint(greaterThanOrEqualTo: folder.trailingAnchor, constant: 10),
            date.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            date.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ url: URL, lastOpened: Date?, isSelected: Bool) {
        self.isSelected = isSelected
        name.stringValue = url.lastPathComponent
        folder.stringValue = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        date.stringValue = lastOpened.map(RecentFiles.shortDate) ?? ""
        name.font = .systemFont(ofSize: NSFont.systemFontSize, weight: isSelected ? .semibold : .regular)
        // Ink on lime while selected, in either appearance.
        name.textColor = isSelected ? Palette.ink : .labelColor
        let secondary = isSelected ? NSColor(srgbHex: 0x3A3F47) : .secondaryLabelColor
        folder.textColor = secondary
        date.textColor = secondary
        icon.contentTintColor = isSelected ? Palette.ink : .secondaryLabelColor
        toolTip = url.path
        setAccessibilityLabel(url.lastPathComponent)
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        layer?.backgroundColor = isSelected ? resolvedCGColor(Palette.lime) : NSColor.clear.cgColor
    }
}
