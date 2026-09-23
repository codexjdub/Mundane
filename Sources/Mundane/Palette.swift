import AppKit
import SwiftUI

/// The one place a colour value is written.
///
/// Both the SwiftUI palette and `Tools/make-icon.swift` read from here. They used
/// to hold separate copies and had already drifted — the icon's card hairline was
/// 0xDEDED9 against the app's 0xE6E6E3.
enum Ink {
    struct Pair {
        let light: UInt32
        let dark: UInt32
        init(_ light: UInt32, _ dark: UInt32) { self.light = light; self.dark = dark }
    }

    static let paper    = Pair(0xFFFFFF, 0x23211F)
    static let edge     = Pair(0xE6E6E3, 0x3A3633)
    static let text     = Pair(0x2E2E2C, 0xE9E3DA)
    static let soft     = Pair(0xA8A8A3, 0x7B746C)
    static let shu      = Pair(0xD2543F, 0xE8705A)
    static let sunday   = Pair(0x9E3D38, 0xD98577)
    static let saturday = Pair(0x45608E, 0x88A5C6)
    static let ribbon   = Pair(0xD9D9D4, 0x4C453E)
    static let tint     = Pair(0xF5F5F2, 0x33302D)
    /// Behind the Saturday and Sunday columns. Separate from tint so the weekend
    /// band can be tuned without moving the switcher and strip track with it.
    static let band     = Pair(0xF5F5F2, 0x2C2A28)

    /// Icon-only: the grid dots are deliberately lighter than the app's `soft`,
    /// so they don't read as heavy against a pure white tile at 128px.
    static let iconDots = Pair(0xC4C4BE, 0xC4C4BE)
}

func nsColor(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green:   CGFloat((hex >> 8) & 0xFF) / 255,
            blue:    CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

private func dyn(_ pair: Ink.Pair) -> NSColor {
    NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? nsColor(pair.dark) : nsColor(pair.light)
    }
}

/// Colours are named once here. There used to be a second set of
/// `NSColor.mundane*` statics that nothing outside this file ever read, so every
/// colour had two names in two conventions and adding one meant two edits.
enum Palette {
    static let paper    = Color(nsColor: dyn(Ink.paper))
    static let edge     = Color(nsColor: dyn(Ink.edge))
    static let ink      = Color(nsColor: dyn(Ink.text))
    static let soft     = Color(nsColor: dyn(Ink.soft))
    static let shu      = Color(nsColor: dyn(Ink.shu))
    static let sunday   = Color(nsColor: dyn(Ink.sunday))
    static let saturday = Color(nsColor: dyn(Ink.saturday))
    static let ribbon   = Color(nsColor: dyn(Ink.ribbon))
    static let tint     = Color(nsColor: dyn(Ink.tint))
    static let band     = Color(nsColor: dyn(Ink.band))
}

enum Typeface {
    /// Hiragino Maru Gothic ProN W4 — the rounded Japanese gothic that ships with
    /// macOS. Falls back to the rounded system face if it is ever missing.
    private static let maruAvailable = NSFont(name: "HiraMaruProN-W4", size: 12) != nil

    static func maru(_ size: CGFloat) -> Font {
        maruAvailable ? .custom("HiraMaruProN-W4", fixedSize: size)
                      : .system(size: size, design: .rounded)
    }
}

enum SizeOption: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }

    var label: String {
        switch self {
        case .small:  "Small"
        case .medium: "Medium"
        case .large:  "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small:  0.85
        case .medium: 1.0
        case .large:  1.18
        }
    }
}

/// Cell geometry for one grid. The ribbon sits exactly on cell boundaries, so the
/// breathing room around the digits comes from the cell being larger than the mark.
struct GridMetrics {
    let cell: CGSize
    let fontSize: CGFloat
    let markSize: CGFloat
    let markRadius: CGFloat
    let ribbonWidth: CGFloat

    var width: CGFloat { cell.width * 7 }
    var cornerRadius: CGFloat { min(cell.width, cell.height) * 0.4 }
}

/// Every dimension in the panel, derived from one scale.
///
/// Sizes used to be written inline wherever they were needed, which meant they
/// drifted apart — changing one left the rest behind. Everything lives here now,
/// so Small / Medium / Large is a single multiplier rather than three sets of
/// numbers to keep in step.
struct Sizing {
    let scale: CGFloat

    init(_ option: SizeOption) { scale = option.scale }

    /// Lengths snap to whole points; fonts don't, so they scale smoothly.
    private func p(_ v: CGFloat) -> CGFloat { (v * scale).rounded() }
    private func f(_ v: CGFloat) -> CGFloat { v * scale }
    private func line(_ v: CGFloat) -> CGFloat { max(1, v * scale) }

    // grids
    var monthGrid: GridMetrics {
        GridMetrics(cell: CGSize(width: p(31), height: p(29)), fontSize: f(12),
                    markSize: p(22), markRadius: f(6.5), ribbonWidth: line(1.5))
    }
    /// Three grids at full size read better than three small ones.
    var threeGrid: GridMetrics { monthGrid }
    var yearGrid: GridMetrics {
        GridMetrics(cell: CGSize(width: p(26), height: p(24)), fontSize: f(12),
                    markSize: p(20), markRadius: f(6), ribbonWidth: line(1.5))
    }

    // type
    var title: CGFloat          { f(12.5) }
    var yearTitle: CGFloat      { f(21) }
    var monthLabel: CGFloat     { f(12) }
    var yearMonthLabel: CGFloat { f(11) }
    var arrowGlyph: CGFloat     { f(9) }
    var chipLabel: CGFloat      { f(11) }
    var stripLabel: CGFloat     { f(9.5) }
    var switcherLabel: CGFloat  { f(10) }
    var hankoGlyph: CGFloat     { f(12) }
    var hintLabel: CGFloat      { f(8.5) }

    // chrome
    var headerBottom: CGFloat   { p(7) }
    var arrowHPad: CGFloat      { p(4) }
    var arrowVPad: CGFloat      { p(2) }
    var arrowRadius: CGFloat    { p(5) }
    var chipHPad: CGFloat       { p(8) }
    var chipVPad: CGFloat       { p(3) }
    var chipRadius: CGFloat     { p(7) }
    var titleGap: CGFloat       { p(6) }

    // strips
    var stripHeight: CGFloat    { max(3, p(4)) }
    var stripGap: CGFloat       { p(8) }
    var stripTop: CGFloat       { p(9) }
    var lifeStripTop: CGFloat   { p(5) }

    // switcher
    var switcherTop: CGFloat    { p(9) }
    var switcherVPad: CGFloat   { p(3) }
    var switcherRadius: CGFloat { p(6) }
    var switcherOuter: CGFloat  { p(8) }
    var switcherMaxWidth: CGFloat { p(280) }
    var hintTop: CGFloat        { p(6) }

    // card
    var cardPadH: CGFloat       { p(12) }
    var cardPadTop: CGFloat     { p(9) }
    var cardPadBottom: CGFloat  { p(8) }
    var cardRadius: CGFloat     { p(12) }
    var trioSpacing: CGFloat    { p(14) }
    var yearColSpacing: CGFloat { p(12) }
    var yearRowSpacing: CGFloat { p(9) }
    var yearCellPadH: CGFloat   { p(4) }
    var yearCellPadV: CGFloat   { p(3) }

    // hanko
    var hankoSize: CGFloat      { p(30) }
    var hankoOverhang: CGFloat  { p(17) }
    var hankoRadius: CGFloat    { p(7) }
    var hankoStroke: CGFloat    { line(1.5) }
}
