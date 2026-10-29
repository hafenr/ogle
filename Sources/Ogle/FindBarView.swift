import AppKit

/// The bar between the toolbar and the preview for finding text in the document: a field with
/// the match count, previous and next, a case toggle, and Done. Return finds the next match
/// (Shift-Return the previous), Esc closes the bar.
@MainActor
final class FindBarView: NSView, NSTextFieldDelegate {
    /// Called as the text or the case toggle change.
    var onChange: (() -> Void)?
    /// Called with whether to go backwards.
    var onNext: ((Bool) -> Void)?
    var onDone: (() -> Void)?

    private let fieldBox = NSView()
    private let field = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")
    private let caseButton = NSButton()

    var query: String { field.stringValue }
    var isCaseSensitive: Bool { caseButton.state == .on }

    init() {
        super.init(frame: .zero)
        wantsLayer = true

        let icon = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)!)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "Find in document"
        field.setAccessibilityLabel("Find in document")
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        countLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        fieldBox.wantsLayer = true
        fieldBox.layer?.cornerRadius = 7
        fieldBox.layer?.borderWidth = 1.5
        for view in [icon, field, countLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            fieldBox.addSubview(view)
        }

        let previous = iconButton("chevron.up", label: "Previous Match", action: #selector(previousClicked))
        let next = iconButton("chevron.down", label: "Next Match", action: #selector(nextClicked))
        caseButton.setButtonType(.pushOnPushOff)
        caseButton.isBordered = false
        caseButton.wantsLayer = true
        caseButton.layer?.cornerRadius = 6
        caseButton.layer?.borderWidth = 1
        caseButton.attributedTitle = NSAttributedString(
            string: "Aa", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor])
        caseButton.attributedAlternateTitle = NSAttributedString(
            string: "Aa", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: Palette.inkText])
        caseButton.toolTip = "Match Case"
        caseButton.setAccessibilityLabel("Match Case")
        caseButton.target = self
        caseButton.action = #selector(caseClicked)
        let done = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        done.isBordered = false
        done.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        done.contentTintColor = .labelColor

        let separator = NSBox()
        separator.boxType = .separator
        for view in [fieldBox, previous, next, caseButton, done, separator] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let preferredWidth = fieldBox.widthAnchor.constraint(equalToConstant: 300)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            fieldBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            fieldBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            fieldBox.heightAnchor.constraint(equalToConstant: 28),
            preferredWidth,
            fieldBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            icon.leadingAnchor.constraint(equalTo: fieldBox.leadingAnchor, constant: 9),
            icon.centerYAnchor.constraint(equalTo: fieldBox.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            field.centerYAnchor.constraint(equalTo: fieldBox.centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 6),
            countLabel.trailingAnchor.constraint(equalTo: fieldBox.trailingAnchor, constant: -10),
            countLabel.centerYAnchor.constraint(equalTo: fieldBox.centerYAnchor),
            previous.leadingAnchor.constraint(equalTo: fieldBox.trailingAnchor, constant: 6),
            previous.centerYAnchor.constraint(equalTo: centerYAnchor),
            next.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 6),
            next.centerYAnchor.constraint(equalTo: centerYAnchor),
            caseButton.leadingAnchor.constraint(equalTo: next.trailingAnchor, constant: 6),
            caseButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            caseButton.heightAnchor.constraint(equalToConstant: 28),
            caseButton.widthAnchor.constraint(equalToConstant: 34),
            done.leadingAnchor.constraint(greaterThanOrEqualTo: caseButton.trailingAnchor, constant: 6),
            done.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            done.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Focuses the field with its text selected, so typing replaces it.
    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    /// Shows "2 of 8" (`index` counts from 1), or "No matches".
    func setResult(index: Int, count: Int) {
        countLabel.stringValue = query.isEmpty ? "" : count == 0 ? "No matches" : "\(index) of \(count)"
    }

    private func iconButton(_ symbol: String, label: String, action: Selector) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: action)
        button.isBordered = false
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = label
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    @objc private func previousClicked() { onNext?(true) }
    @objc private func nextClicked() { onNext?(false) }
    @objc private func doneClicked() { onDone?() }

    @objc private func caseClicked() {
        updateColors()
        onChange?()
    }

    func controlTextDidChange(_ notification: Notification) {
        onChange?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            onNext?(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onDone?()
            return true
        default:
            return false
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        layer?.backgroundColor = resolvedCGColor(Palette.barBackground)
        fieldBox.layer?.backgroundColor = resolvedCGColor(Palette.controlFill)
        fieldBox.layer?.borderColor = resolvedCGColor(Palette.inkText)
        caseButton.layer?.borderColor = resolvedCGColor(Palette.controlBorder)
        caseButton.layer?.backgroundColor = resolvedCGColor(caseButton.state == .on ? Palette.pressedFill : Palette.controlFill)
    }
}
