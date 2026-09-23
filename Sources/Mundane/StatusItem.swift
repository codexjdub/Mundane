import AppKit

/// How the date reads in the menu bar.
enum DateStyle: String, CaseIterable {
    case monthDot      // 9・21
    case dayOnly       // 21
    case dayKanji      // 21日
    case monthDayKanji // 9月21日

    func string(for date: Date) -> String {
        let c = Calendar.autoupdatingCurrent.dateComponents([.month, .day], from: date)
        let m = c.month ?? 1
        let d = c.day ?? 1
        switch self {
        case .monthDot:      return "\(m)・\(d)"
        case .dayOnly:       return "\(d)"
        case .dayKanji:      return "\(d)日"
        case .monthDayKanji: return "\(m)月\(d)日"
        }
    }

    /// The widest string this style can ever produce.
    ///
    /// Derived by running `string(for:)` on the worst case rather than restating
    /// the formats, so changing a separator here cannot leave the reserved width
    /// measuring the old shape — the one failure this whole type exists to stop.
    /// With monospaced digits only the digit count matters, so a two-digit month
    /// and a two-digit day is the widest there is.
    var widestSample: String {
        let worst = Calendar.autoupdatingCurrent.date(
            from: DateComponents(year: 2000, month: 12, day: 28)) ?? Date()
        return string(for: worst)
    }
}

/// Owns the menu bar item and keeps its width from jittering.
///
/// Menu bar items pack rightward, so an item that changes width shoves every icon
/// to its left. Two things prevent that: monospaced digits (so 1 is as wide as 8)
/// and a fixed reserved length measured against the widest string the current
/// style can produce — recomputed when the style changes, not just at launch.
final class StatusItemController {
    let item: NSStatusItem
    private let font: NSFont

    var style: DateStyle {
        didSet {
            guard style != oldValue else { return }
            reserveWidth()
            render()
        }
    }

    private var date: Date

    init(style: DateStyle, date: Date) {
        self.style = style
        self.date = date

        // Match the system menu bar's size, but with monospaced digits.
        // (The panel uses Hiragino Maru Gothic; the menu bar stays system font so
        // it sits consistently among its neighbours.)
        let menuFont = NSFont.menuBarFont(ofSize: 0)
        self.font = NSFont.monospacedDigitSystemFont(ofSize: menuFont.pointSize, weight: .regular)

        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "MundaneStatusItem" // remember the user's cmd-drag position
        item.button?.font = font

        reserveWidth()
        render()
    }

    func update(date: Date) {
        self.date = date
        render()
    }

    private func render() {
        guard let button = item.button else { return }
        button.title = style.string(for: date)
        button.setAccessibilityLabel(Self.accessibilityDate.string(from: date))
    }

    private func reserveWidth() {
        let probe = NSStatusBarButton()
        probe.font = font
        probe.title = style.widestSample
        probe.sizeToFit()
        item.length = probe.frame.width
    }

    private static let accessibilityDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()
}
