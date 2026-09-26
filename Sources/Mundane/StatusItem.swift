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
}

/// Owns the menu bar item.
///
/// macOS sizes it to the date, exactly as it would any text item, so it takes no
/// more room than it needs. It used to reserve the width of the widest date the
/// style could show, which kept its neighbours still but left blank space around
/// the date most of the month — and a fixed length also gets a margin from macOS
/// on top of the button's own padding, so the padding counted twice.
///
/// Menu bar items pack rightward, so a change in width moves every icon to the
/// left of this one. Monospaced digits (1 as wide as 8) keep that to the days
/// the date gains or loses a digit: the 1st and 10th, and for the formats with a
/// month in them, October and January.
final class StatusItemController {
    let item: NSStatusItem

    /// The system menu bar's size, with monospaced digits. The panel uses
    /// Hiragino Maru Gothic; the menu bar stays system font so it sits
    /// consistently among its neighbours.
    static let font: NSFont = {
        let menuFont = NSFont.menuBarFont(ofSize: 0)
        return NSFont.monospacedDigitSystemFont(ofSize: menuFont.pointSize, weight: .regular)
    }()

    var style: DateStyle {
        didSet {
            guard style != oldValue else { return }
            render()
        }
    }

    private var date: Date

    init(style: DateStyle, date: Date) {
        self.style = style
        self.date = date

        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "MundaneStatusItem" // remember the user's cmd-drag position
        item.button?.font = Self.font

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

    private static let accessibilityDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()
}
