import AppKit

/// The round button on the divider between the editor and the preview that links them: a
/// closed chain on ink while they scroll and zoom together, a broken chain on white while
/// they do not.
@MainActor
final class DividerLinkButton: NSButton {
    static let diameter: CGFloat = 26

    var isLinked = true {
        didSet { update() }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        isBordered = false
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = Self.diameter / 2
        layer?.borderWidth = 1
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = NSSize(width: 0, height: -1)
        layer?.shadowRadius = 1.5
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func update() {
        image = Self.chainImage(broken: !isLinked)
        toolTip = isLinked
            ? "The editor and the preview scroll and zoom together. Click to unlink them."
            : "The editor and the preview scroll and zoom separately. Click to link them."
        setAccessibilityLabel(isLinked ? "Linked" : "Unlinked")
        setAccessibilityHelp(toolTip)
        updateColors()
    }

    private func updateColors() {
        if isLinked {
            // Ink with a paper chain, outlined in gray so it shows against dark editor themes
            // and dark mode too.
            layer?.backgroundColor = resolvedCGColor(Palette.ink)
            layer?.borderColor = resolvedCGColor(NSColor(srgbHex: 0x6E737C))
            layer?.borderWidth = 1.5
            contentTintColor = Palette.paper
            layer?.shadowOpacity = 0.18
        } else {
            layer?.borderWidth = 1
            layer?.backgroundColor = resolvedCGColor(Palette.dynamic(light: .white, dark: NSColor(srgbHex: 0x161B22)))
            layer?.borderColor = resolvedCGColor(Palette.dynamic(light: NSColor(srgbHex: 0xC9CBD1), dark: NSColor(white: 1, alpha: 0.22)))
            contentTintColor = .secondaryLabelColor
            layer?.shadowOpacity = 0.08
        }
    }

    /// The chain link of the design, drawn at 14 pt from its 16-unit outline; broken, its two
    /// halves are pulled apart with break marks between them.
    nonisolated static func chainImage(broken: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: true) { _ in
            let transform = NSAffineTransform()
            transform.scale(by: 14.0 / 16)
            transform.concat()
            let path = NSBezierPath()
            let shift: CGFloat = broken ? 0.8 : 0
            // Top right half, around (10.25, 5.25).
            path.move(to: NSPoint(x: 7.2 + shift, y: 4.6 - shift))
            path.line(to: NSPoint(x: 8.4 + shift, y: 3.4 - shift))
            path.appendArc(
                withCenter: NSPoint(x: 10.25 + shift, y: 5.25 - shift), radius: 2.6, startAngle: 225, endAngle: 405,
                clockwise: false)
            path.line(to: NSPoint(x: 10.9 + shift, y: 8.3 - shift))
            // Bottom left half, around (5.75, 10.75).
            path.move(to: NSPoint(x: 8.8 - shift, y: 11.4 + shift))
            path.line(to: NSPoint(x: 7.6 - shift, y: 12.6 + shift))
            path.appendArc(
                withCenter: NSPoint(x: 5.75 - shift, y: 10.75 + shift), radius: 2.6, startAngle: 45, endAngle: 225,
                clockwise: false)
            path.line(to: NSPoint(x: 5.1 - shift, y: 7.7 + shift))
            if broken {
                for (from, to) in [((4.6, 2.2), (4.6, 3.8)), ((2.2, 4.6), (3.8, 4.6)), ((11.4, 13.8), (11.4, 12.2)), ((13.8, 11.4), (12.2, 11.4))] {
                    path.move(to: NSPoint(x: from.0, y: from.1))
                    path.line(to: NSPoint(x: to.0, y: to.1))
                }
            } else {
                path.move(to: NSPoint(x: 6.5, y: 9.5))
                path.line(to: NSPoint(x: 9.5, y: 6.5))
            }
            path.lineWidth = 1.7
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
