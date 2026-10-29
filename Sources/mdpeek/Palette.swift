import AppKit

/// The colors of the app icon, which the window's own controls use, and the neutral shades of
/// the redesign. Lime is only ever a fill or a highlight, never the color of text.
enum Palette {
    static var ink: NSColor { NSColor(srgbHex: 0x23262B) }
    static var lime: NSColor { NSColor(srgbHex: 0xC6F05A) }
    static var paper: NSColor { NSColor(srgbHex: 0xFAFAF7) }

    /// Ink for text and outlines; the label color in dark mode, where ink would not show.
    static var inkText: NSColor { dynamic(light: ink, dark: .labelColor) }
    /// The border of small controls.
    static var controlBorder: NSColor { dynamic(light: NSColor(srgbHex: 0xD6D6DA), dark: NSColor(white: 1, alpha: 0.16)) }
    /// The fill of small controls, and of a toggle while pressed.
    static var controlFill: NSColor { dynamic(light: .white, dark: NSColor(white: 1, alpha: 0.08)) }
    /// Thin lines between parts of a control.
    static var hairline: NSColor { dynamic(light: NSColor(srgbHex: 0xE3E3E6), dark: NSColor(white: 1, alpha: 0.1)) }
    /// A toggle's fill while pressed.
    static var pressedFill: NSColor { dynamic(light: NSColor(srgbHex: 0xE4E4E8), dark: NSColor(white: 1, alpha: 0.18)) }
    /// Bars above the page, such as the find bar.
    static var barBackground: NSColor { dynamic(light: NSColor(srgbHex: 0xFAFAFA), dark: NSColor(srgbHex: 0x161B22)) }
    /// The page's background, which the bars along the preview share.
    static var pageBackground: NSColor { dynamic(light: .white, dark: NSColor(srgbHex: 0x0D1117)) }

    nonisolated static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

extension NSColor {
    convenience init(srgbHex hex: Int, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension NSView {
    /// `color` as it appears in this view, for layer properties.
    func resolvedCGColor(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }
}
