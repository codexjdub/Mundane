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
/// The item is exactly as wide as the date. Its length is set to the text's own
/// width, and macOS adds the 8 pt a side it gives every item — the least it
/// allows. Left to size itself, a text item gets about 10 pt a side instead:
/// 25日 took 50 pt that way and takes 46 this way. Drawing the date as a picture
/// reaches 46 too, but measured at 1x it sat 1–2 px low and 20% lighter than
/// real text, so the text stays text.
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

    /// The item's length for a date string: the text's own width, with half a
    /// point to spare so the last glyph is never clipped.
    static func length(for text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width + 0.5)
    }

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
        let text = style.string(for: date)
        item.length = Self.length(for: text)
        button.title = text
        button.setAccessibilityLabel(Self.accessibilityDate.string(from: date))
    }

    private static let accessibilityDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()
}
