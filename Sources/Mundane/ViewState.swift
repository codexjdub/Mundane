import Foundation
import Observation

enum ViewMode: String, CaseIterable, Identifiable {
    case month, threeMonths, year
    var id: String { rawValue }

    var label: String {
        switch self {
        case .month:       "month"
        case .threeMonths: "3 months"
        case .year:        "year"
        }
    }
}

@Observable
final class ViewState {
    var mode: ViewMode = .month

    /// Which control the pointer is over.
    ///
    /// This would normally be `@State` inside the control itself, but `@State` is
    /// a SwiftUI macro and Command Line Tools does not ship `SwiftUIMacros` — only
    /// Xcode does. Local view state therefore has to live in an @Observable object
    /// that outlives the view structs. See TODO.md.
    var hovered: String?

    /// First of the month currently on screen. Kept when switching views, so
    /// paging to December and then opening the year view lands on that year.
    var anchor: Date

    @ObservationIgnored let clock: Clock
    let settings: Settings

    init(clock: Clock, settings: Settings) {
        self.clock = clock
        self.settings = settings
        self.anchor = Self.firstOfMonth(clock.today)
    }

    /// Reading this in a view body registers the dependency on `clock.today`,
    /// so the grid redraws on day rollover without any wiring here.
    var today: Date { clock.today }

    /// Same, for the first day of the week: changing it in System Settings
    /// redraws an open panel.
    var weekStart: Int { clock.weekStart }

    /// Whether the period on screen contains today.
    var isShowingToday: Bool {
        let cal = MonthMeta.calendar
        switch mode {
        case .month:
            return cal.isDate(anchor, equalTo: clock.today, toGranularity: .month)
        case .threeMonths:
            // All three grids are on screen, so today being in any of them means
            // you have not paged away from it.
            return (-1 ... 1).contains { offset in
                guard let month = cal.date(byAdding: .month, value: offset, to: anchor)
                else { return false }
                return cal.isDate(month, equalTo: clock.today, toGranularity: .month)
            }
        case .year:
            return cal.isDate(anchor, equalTo: clock.today, toGranularity: .year)
        }
    }

    /// Page by whatever unit the current view shows.
    func page(_ step: Int) {
        let cal = MonthMeta.calendar
        switch mode {
        case .month, .threeMonths:
            anchor = cal.date(byAdding: .month, value: step, to: anchor) ?? anchor
        case .year:
            anchor = cal.date(byAdding: .year, value: step, to: anchor) ?? anchor
        }
    }

    /// Tab cycles the view, wrapping at the end.
    func cycleView() {
        let modes = ViewMode.allCases
        guard let index = modes.firstIndex(of: mode) else { return }
        mode = modes[(index + 1) % modes.count]
    }

    func goToToday() { anchor = Self.firstOfMonth(clock.today) }

    private static func firstOfMonth(_ date: Date) -> Date {
        let cal = MonthMeta.calendar
        let c = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: DateComponents(year: c.year, month: c.month, day: 1)) ?? date
    }
}
